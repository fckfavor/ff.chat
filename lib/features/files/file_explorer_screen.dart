import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/workspace/workspace_fs.dart';
import '../editor/editor_screen.dart';

class FileExplorerScreen extends StatefulWidget {
  const FileExplorerScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<FileExplorerScreen> createState() => _FileExplorerScreenState();
}

class _FileExplorerScreenState extends State<FileExplorerScreen> {
  final _fs = WorkspaceFs.instance;
  String _currentPath = '.';
  List<FsEntry> _entries = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final entries = await _fs.list(_currentPath);
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _navigateTo(String path) {
    setState(() => _currentPath = path);
    _load();
  }

  void _goUp() {
    if (_currentPath == '.' || _currentPath.isEmpty) return;
    final parent = p.dirname(_currentPath);
    _navigateTo(parent == '.' ? '.' : parent);
  }

  List<String> get _breadcrumbs {
    if (_currentPath == '.' || _currentPath.isEmpty) return ['workspace'];
    return ['workspace', ..._currentPath.split('/').where((s) => s.isNotEmpty)];
  }

  Future<void> _openEntry(FsEntry entry) async {
    if (entry.isDirectory) {
      _navigateTo(entry.relativePath);
    } else {
      // Dosyayi editorde ac
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => EditorScreen(relativePath: entry.relativePath)),
      );
      _load();
    }
  }

  Future<void> _showCreateDialog() async {
    final nameController = TextEditingController();
    bool isDir = false;
    final result = await showDialog<String?>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Yeni olustur'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  hintText: 'or: main.dart / src',
                  border: OutlineInputBorder(),
                ),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                value: isDir,
                onChanged: (v) => setState(() => isDir = v ?? false),
                title: const Text('Klasor olarak olustur'),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Iptal')),
            FilledButton(
              onPressed: () => Navigator.pop(context, '${isDir ? "d:" : "f:"}${nameController.text.trim()}'),
              child: const Text('Olustur'),
            ),
          ],
        ),
      ),
    );
    if (result == null || result.length < 3) return;
    final isDirectory = result.startsWith('d:');
    final name = result.substring(2).trim();
    if (name.isEmpty) return;
    final targetPath = _currentPath == '.' ? name : '$_currentPath/$name';
    try {
      if (isDirectory) {
        await _fs.createDir(targetPath);
      } else {
        await _fs.writeFile(targetPath, '');
        if (!mounted) return;
        // Yeni dosyayi direkt editorde ac
        await Navigator.push(context, MaterialPageRoute(builder: (_) => EditorScreen(relativePath: targetPath)));
      }
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Olusturma hatasi: $e')));
    }
  }

  Future<void> _showEntryActions(FsEntry entry) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text(entry.name, style: const TextStyle(fontWeight: FontWeight.bold))),
            const Divider(height: 1),
            ListTile(leading: const Icon(Icons.edit), title: const Text('Yeniden adlandir'), onTap: () => Navigator.pop(context, 'rename')),
            ListTile(leading: const Icon(Icons.delete, color: Colors.red), title: const Text('Sil', style: TextStyle(color: Colors.red)), onTap: () => Navigator.pop(context, 'delete')),
            ListTile(leading: const Icon(Icons.info_outline), title: const Text('Bilgi'), onTap: () => Navigator.pop(context, 'info')),
          ],
        ),
      ),
    );
    if (action == null) return;
    if (action == 'delete') {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Sil?'),
          content: Text('${entry.relativePath} silinecek. Emin misin?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Iptal')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sil')),
          ],
        ),
      );
      if (confirm != true) return;
      try {
        await _fs.delete(entry.relativePath);
        _load();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${entry.name} silindi')));
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Silme hatasi: $e')));
      }
    } else if (action == 'rename') {
      final controller = TextEditingController(text: entry.name);
      final newName = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Yeniden adlandir'),
          content: TextField(controller: controller, decoration: const InputDecoration(border: OutlineInputBorder()), autofocus: true),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Iptal')),
            FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Kaydet')),
          ],
        ),
      );
      if (newName == null || newName.isEmpty || newName == entry.name) return;
      final newPath = p.join(p.dirname(entry.relativePath), newName);
      try {
        await _fs.rename(entry.relativePath, newPath);
        _load();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Yeniden adlandirma hatasi: $e')));
      }
    } else if (action == 'info') {
      final stat = await _fs.stat(entry.relativePath);
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(entry.name),
          content: Text('Yol: ${entry.relativePath}\n'
              'Tip: ${entry.isDirectory ? "Klasor" : "Dosya"}\n'
              'Boyut: ${stat.size} bytes\n'
              'Degistirilme: ${stat.modified}'),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Kapat'))],
        ),
      );
    }
  }

  Widget _buildBody(BuildContext context) {
    return Column(
      children: [
        // Breadcrumb + actions
        Container(
          width: double.infinity,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              if (_currentPath != '.')
                IconButton(icon: const Icon(Icons.arrow_upward, size: 18), onPressed: _goUp, tooltip: 'Yukari', padding: EdgeInsets.zero, constraints: const BoxConstraints()),
              if (_currentPath != '.') const SizedBox(width: 8),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final crumb in _breadcrumbs.asMap().entries)
                        GestureDetector(
                          onTap: () {
                            if (crumb.key == 0) {
                              _navigateTo('.');
                            } else {
                              final path = _breadcrumbs.sublist(1, crumb.key + 1).join('/');
                              _navigateTo(path);
                            }
                          },
                          child: Text(
                            crumb.value,
                            style: TextStyle(
                              fontWeight: crumb.key == _breadcrumbs.length - 1 ? FontWeight.bold : FontWeight.normal,
                              color: crumb.key == _breadcrumbs.length - 1 ? Theme.of(context).colorScheme.primary : Colors.grey[700],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Text('${_entries.length} oge', style: const TextStyle(fontSize: 12, color: Colors.grey)),
              if (widget.embedded) ...[
                const SizedBox(width: 8),
                IconButton(icon: const Icon(Icons.refresh, size: 18), onPressed: _load, tooltip: 'Yenile', padding: EdgeInsets.zero, constraints: const BoxConstraints()),
              ],
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(child: Text('Hata: $_error'))
                  : _entries.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.folder_open, size: 48, color: Colors.grey),
                              const SizedBox(height: 8),
                              const Text('Klasor bos', style: TextStyle(color: Colors.grey)),
                              const SizedBox(height: 12),
                              FilledButton.icon(onPressed: _showCreateDialog, icon: const Icon(Icons.add), label: const Text('Dosya/Klasor olustur')),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.separated(
                            itemCount: _entries.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final e = _entries[index];
                              return ListTile(
                                leading: Icon(e.isDirectory ? Icons.folder : Icons.description, color: e.isDirectory ? Colors.amber[700] : Colors.grey[600]),
                                title: Text(e.name, style: TextStyle(fontWeight: e.isDirectory ? FontWeight.w600 : FontWeight.normal)),
                                subtitle: e.isDirectory ? null : Text('${e.size ?? 0} bytes • ${e.modified?.toString().substring(0, 16) ?? ""}', style: const TextStyle(fontSize: 11)),
                                trailing: IconButton(icon: const Icon(Icons.more_vert, size: 18), onPressed: () => _showEntryActions(e)),
                                onTap: () => _openEntry(e),
                                onLongPress: () => _showEntryActions(e),
                              );
                            },
                          ),
                        ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) {
      // Embedded modda Scaffold'siz, CodeWorkspaceScreen'in TabBarView icinde
      return Stack(
        children: [
          _buildBody(context),
          Positioned(
            right: 16,
            bottom: 16,
            child: FloatingActionButton.small(onPressed: _showCreateDialog, child: const Icon(Icons.add)),
          ),
        ],
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dosyalar'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load, tooltip: 'Yenile'),
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            tooltip: 'Workspace temizle',
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Workspace temizlensin mi?'),
                  content: const Text('Tum dosyalar silinecek!'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Iptal')),
                    FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Temizle')),
                  ],
                ),
              );
              if (confirm != true) return;
              await _fs.clearWorkspace();
              _load();
            },
          ),
        ],
      ),
      body: _buildBody(context),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateDialog,
        child: const Icon(Icons.add),
      ),
    );
  }
}
