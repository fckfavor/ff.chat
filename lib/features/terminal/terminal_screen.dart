import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/workspace/sandbox_config.dart';
import '../../core/workspace/shell_executor.dart';

/// Basit terminal emülatörü — xterm kadar agir degil, MVP icin yeterli.
///
/// Ozellikler:
/// - Komut gecmisi (yukari/asagi)
/// - workingDir takibi (cd komutu)
/// - ShellExecutor ile gercek /system/bin/sh calistirir
/// - Ciktiyi monospace, koyu tema ile gosterir (Termux hissi)
class TerminalScreen extends StatefulWidget {
  const TerminalScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  final _shell = ShellExecutor.instance;
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();

  final List<_TerminalLine> _lines = [];
  String _currentWorkdir = '.';
  bool _running = false;
  final List<String> _history = [];
  int _historyIndex = -1;

  @override
  void initState() {
    super.initState();
    _printMotd();
  }

  void _printMotd() {
    _lines.add(_TerminalLine(
      text: 'ff.chat terminal — workspace: ./\n'
          'Komut yaz ve calistir. Or: ls -la, cat file.txt, mkdir project\n'
          'Tip: "clear" ekrani temizler, "pwd" konumu gosterir.\n',
      type: _LineType.system,
    ));
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _execute(String rawCommand) async {
    final command = rawCommand.trim();
    if (command.isEmpty) return;

    setState(() {
      _lines.add(_TerminalLine(text: '➜ $command', type: _LineType.input));
      _running = true;
      _history.add(command);
      _historyIndex = _history.length;
    });
    _scrollToBottom();

    // Builtin komutlar
    if (command == 'clear') {
      setState(() {
        _lines.clear();
        _running = false;
      });
      return;
    }
    if (command == 'help') {
      setState(() {
        _lines.add(_TerminalLine(
          text: 'Komutlar: ls, cat, echo, mkdir, rm, pwd, clear, help\n'
              'Workspace: ${_currentWorkdir}\n'
              'Ornek: echo "hello" > hello.txt && cat hello.txt',
          type: _LineType.output,
        ));
        _running = false;
      });
      _scrollToBottom();
      return;
    }
    if (command.startsWith('cd ')) {
      final target = command.substring(3).trim();
      final newDir = await _resolveCd(target);
      setState(() {
        _currentWorkdir = newDir;
        _lines.add(_TerminalLine(text: 'cd -> $newDir', type: _LineType.system));
        _running = false;
      });
      _scrollToBottom();
      return;
    }
    if (command == 'cd') {
      setState(() {
        _currentWorkdir = '.';
        _lines.add(const _TerminalLine(text: 'cd -> .', type: _LineType.system));
        _running = false;
      });
      _scrollToBottom();
      return;
    }
    if (command == 'pwd') {
      final root = await SandboxConfig.getWorkspaceRoot();
      setState(() {
        _lines.add(_TerminalLine(text: '$_currentWorkdir (host: $root/$_currentWorkdir)', type: _LineType.output));
        _running = false;
      });
      _scrollToBottom();
      return;
    }

    // Gercek shell
    try {
      final result = await _shell.run(command, workingDir: _currentWorkdir);
      setState(() {
        if (result.combined.trim().isNotEmpty) {
          _lines.add(_TerminalLine(
            text: result.combined,
            type: result.success ? _LineType.output : _LineType.error,
          ));
        }
        if (!result.success && result.combined.trim().isEmpty) {
          _lines.add(_TerminalLine(text: '[exit ${result.exitCode}]', type: _LineType.error));
        }
        _running = false;
      });
    } catch (e) {
      setState(() {
        _lines.add(_TerminalLine(text: 'error: $e', type: _LineType.error));
        _running = false;
      });
    }
    _scrollToBottom();
  }

  Future<String> _resolveCd(String target) async {
    if (target.isEmpty || target == '~') return '.';
    if (target == '..') {
      // Basit parent
      if (_currentWorkdir == '.' || _currentWorkdir.isEmpty) return '.';
      final parts = _currentWorkdir.split('/');
      if (parts.length <= 1) return '.';
      return parts.sublist(0, parts.length - 1).join('/');
    }
    if (target.startsWith('/')) return target.substring(1);
    if (_currentWorkdir == '.') return target;
    return '$_currentWorkdir/$target';
  }

  void _onSubmitted(String value) {
    if (_running) return;
    _inputController.clear();
    _execute(value);
  }

  void _onKey(RawKeyEvent event) {
    if (event is! RawKeyDownEvent) return;
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (_history.isEmpty) return;
      setState(() {
        if (_historyIndex > 0) _historyIndex--;
        _inputController.text = _history[_historyIndex];
        _inputController.selection = TextSelection.fromPosition(
          TextPosition(offset: _inputController.text.length),
        );
      });
    } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (_history.isEmpty) return;
      setState(() {
        if (_historyIndex < _history.length - 1) {
          _historyIndex++;
          _inputController.text = _history[_historyIndex];
        } else {
          _historyIndex = _history.length;
          _inputController.clear();
        }
        _inputController.selection = TextSelection.fromPosition(
          TextPosition(offset: _inputController.text.length),
        );
      });
    }
  }

  Widget _buildBody(BuildContext context) {
    return Column(
      children: [
        // Cikti alani
        Expanded(
          child: Container(
            color: const Color(0xFF1E1E1E),
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(10),
              itemCount: _lines.length,
              itemBuilder: (context, index) {
                final line = _lines[index];
                Color color;
                switch (line.type) {
                  case _LineType.input:
                    color = const Color(0xFF4EC9B0);
                    break;
                  case _LineType.output:
                    color = const Color(0xFFD4D4D4);
                    break;
                  case _LineType.error:
                    color = const Color(0xFFF48771);
                    break;
                  case _LineType.system:
                    color = const Color(0xFF858585);
                    break;
                }
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: SelectableText(
                    line.text,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontFamilyFallback: const ['Courier'],
                      fontSize: 13,
                      color: color,
                      height: 1.3,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        if (_running) const LinearProgressIndicator(minHeight: 2),
        // Input alani
        RawKeyboardListener(
          focusNode: _focusNode,
          onKey: _onKey,
          child: Container(
            color: Theme.of(context).colorScheme.surface,
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Text(
                  '$_currentWorkdir\$',
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _inputController,
                    autofocus: false,
                    enabled: !_running,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                    decoration: const InputDecoration(
                      hintText: 'komut yaz...',
                      border: OutlineInputBorder(),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                    onSubmitted: _onSubmitted,
                    textInputAction: TextInputAction.send,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _running ? null : () => _onSubmitted(_inputController.text),
                  icon: _running
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.play_arrow),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) {
      return Column(
        children: [
          // Mini header for embedded
          Container(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                Text('$_currentWorkdir', style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
                const Spacer(),
                IconButton(icon: const Icon(Icons.delete_sweep, size: 16), onPressed: () => setState(() => _lines.clear()), tooltip: 'Temizle', padding: EdgeInsets.zero, constraints: const BoxConstraints()),
                IconButton(icon: const Icon(Icons.info_outline, size: 16), onPressed: _showInfo, tooltip: 'Bilgi', padding: EdgeInsets.zero, constraints: const BoxConstraints()),
              ],
            ),
          ),
          Expanded(child: _buildBody(context)),
        ],
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text('Terminal — $_currentWorkdir'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            tooltip: 'Temizle',
            onPressed: () => setState(() => _lines.clear()),
          ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'Bilgi',
            onPressed: () => _showInfo(),
          ),
        ],
      ),
      body: _buildBody(context),
    );
  }

  void _showInfo() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Terminal Bilgi'),
        content: const Text(
          'Bu terminal gercek bir Linux shell calistirir (/system/bin/sh).\n\n'
          'Workspace: app private storage/workspace\n'
          'Her komut izole calisir, 30s timeout ve 1MB cikti limiti var.\n\n'
          'cd sadece UI state degistirir, gercek shell her komutta ayri process.\n'
          'Uzun sureli komutlar icin tek satirda && kullan: "npm install && npm run build"',
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Kapat'))],
      ),
    );
  }
}

enum _LineType { input, output, error, system }

class _TerminalLine {
  const _TerminalLine({required this.text, required this.type});
  final String text;
  final _LineType type;
}
