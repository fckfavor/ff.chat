import 'package:flutter/material.dart';

import '../../core/workspace/workspace_fs.dart';

/// Basit kod editoru — dosya oku/yaz.
///
/// Gelecekte code_text_field + syntax highlight eklenecek,
/// MVP'de duz TextField yeterli.
class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key, required this.relativePath});

  final String relativePath;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  final _fs = WorkspaceFs.instance;
  final _controller = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _dirty = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    _controller.addListener(() {
      if (!_dirty && !_loading) {
        setState(() => _dirty = true);
      }
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final content = await _fs.readFile(widget.relativePath);
      if (!mounted) return;
      _controller.text = content;
      setState(() {
        _loading = false;
        _dirty = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await _fs.writeFile(widget.relativePath, _controller.text);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _dirty = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${widget.relativePath} kaydedildi')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kaydetme hatasi: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<bool> _onWillPop() async {
    if (!_dirty) return true;
    final res = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Kaydedilmemis degisiklikler'),
        content: const Text('Cikmadan once kaydetmek ister misin?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgec')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Kaydetmeden cik')),
          FilledButton(onPressed: () async { await _save(); if (mounted) Navigator.pop(context, true); }, child: const Text('Kaydet ve cik')),
        ],
      ),
    );
    return res ?? false;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldPop = await _onWillPop();
        if (shouldPop && context.mounted) Navigator.pop(context);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.relativePath, style: const TextStyle(fontSize: 14)),
          actions: [
            if (_dirty)
              IconButton(
                icon: _saving
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.save),
                onPressed: _saving ? null : _save,
                tooltip: 'Kaydet',
              ),
            IconButton(icon: const Icon(Icons.refresh), onPressed: _load, tooltip: 'Yenile'),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline, size: 48, color: Colors.red),
                          const SizedBox(height: 12),
                          Text(_error!, textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          FilledButton(onPressed: _load, child: const Text('Tekrar dene')),
                        ],
                      ),
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.all(8),
                    child: TextField(
                      controller: _controller,
                      maxLines: null,
                      expands: true,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 13, height: 1.4),
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.all(12),
                      ),
                      textAlignVertical: TextAlignVertical.top,
                    ),
                  ),
        bottomNavigationBar: _dirty
            ? SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: const Icon(Icons.save),
                    label: Text(_saving ? 'Kaydediliyor...' : 'Kaydet'),
                  ),
                ),
              )
            : null,
      ),
    );
  }
}
