import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/agent/agent_loop.dart';
import '../../core/agent/context_compaction.dart';
import '../../core/agent/permission_gate.dart';
import '../../core/agent/tool_definitions.dart';
import '../../core/http/dynamic_http_client.dart';
import '../../core/http/friendly_error.dart';
import '../../core/models/preset.dart';
import '../../core/storage/app_settings_repository.dart';
import '../../core/storage/chat_repository.dart';
import '../../core/storage/local_database.dart';
import '../../core/storage/secure_key_storage.dart';
import '../../core/workspace/workspace_fs.dart';
import '../settings/settings_screen.dart';
import 'widgets/tool_activity_card.dart';

/// Agent workbench — Claude Code mobil: canli tool kartlari, alt onay bar,
/// slash komutlari. Sadece sohbet degil, calisan bir ajan goruntusu.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _chatRepository = ChatRepository();
  final _settingsRepo = AppSettingsRepository();
  final _secureStorage = SecureKeyStorage();
  final _httpClient = DynamicHttpClient();

  final _textController = TextEditingController();
  final _scrollController = ScrollController();

  late final String _sessionId;
  final List<ChatMessage> _messages = [];

  bool _sending = false;
  String _streamingText = '';
  bool _agentMode = true;
  bool _planMode = false;
  bool _planApproved = false;
  List<Map<String, dynamic>> _todos = [];
  List<String> _quickModels = [];
  bool _quickModelsLoading = false;

  // Canli tool kartlari (bu turde uretilenler)
  final List<ToolActivity> _activities = [];
  // Bekleyen izin istegleri (alt barda gosterilir)
  _PendingApproval? _pendingApproval;
  String _statusLine = '';

  @override
  void initState() {
    super.initState();
    final existingSessionId = _settingsRepo.getCurrentSessionId();
    if (existingSessionId != null) {
      _sessionId = existingSessionId;
    } else {
      _sessionId = DateTime.now().millisecondsSinceEpoch.toString();
      _settingsRepo.setCurrentSessionId(_sessionId);
    }
    _messages.addAll(_chatRepository.getMessagesForSession(_sessionId));
    final storedTodos = _chatRepository.getTodosForSession(_sessionId);
    if (storedTodos.isNotEmpty) {
      _todos = storedTodos.map((t) => {'content': t.content, 'status': t.status, 'priority': t.priority}).toList();
    }
    _loadQuickModels();
  }

  void _onTodosUpdated(List<Map<String, dynamic>> todos) {
    setState(() => _todos = List<Map<String, dynamic>>.from(todos));
    _chatRepository.saveTodos(_sessionId, todos);
  }

  Future<void> _loadQuickModels() async {
    final presetId = _settingsRepo.getPresetId();
    final preset = presetId != null ? _chatRepository.resolvePreset(presetId) : null;
    if (preset == null) return;
    if (preset.knownModels != null && preset.knownModels!.isNotEmpty) {
      if (mounted) setState(() => _quickModels = preset.knownModels!);
      return;
    }
    if (preset.modelsListEndpointTemplate == null || preset.modelsListEndpointTemplate!.isEmpty) return;
    final baseUrl = _settingsRepo.getBaseUrl();
    if (baseUrl == null || baseUrl.isEmpty) return;
    setState(() => _quickModelsLoading = true);
    try {
      final apiKey = await _secureStorage.getApiKey(preset.id) ?? '';
      final models = await DynamicHttpClient().fetchModelList(preset: preset, apiKey: apiKey, baseUrl: baseUrl);
      final cleaned = models.map((m) => m.replaceFirst('models/', '')).toList();
      if (mounted) setState(() => _quickModels = cleaned);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _quickModelsLoading = false);
    }
  }

  void _showQuickModelSelector() {
    final current = _settingsRepo.getModelName() ?? '';
    final presetId = _settingsRepo.getPresetId();
    final preset = presetId != null ? _chatRepository.resolvePreset(presetId) : null;
    final repoModels = _quickModels.isNotEmpty ? _quickModels : (preset?.knownModels ?? []);
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(padding: const EdgeInsets.all(16), child: Text('Model sec — ${preset?.name ?? "preset"}', style: const TextStyle(fontWeight: FontWeight.bold))),
            if (_quickModelsLoading) const Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()),
            if (repoModels.isEmpty && !_quickModelsLoading)
              const Padding(padding: EdgeInsets.all(16), child: Text('Model listesi yok, Settings\'ten Test et veya manuel gir')),
            ...repoModels.map((m) => ListTile(
                  title: Text(m),
                  trailing: m == current ? const Icon(Icons.check, color: Colors.green) : null,
                  onTap: () async {
                    await _settingsRepo.setModelName(m);
                    if (mounted) Navigator.pop(context);
                    if (mounted) setState(() {});
                  },
                )),
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Manuel gir...'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildModelChip() {
    final current = _settingsRepo.getModelName();
    final display = (current == null || current.isEmpty) ? 'model sec' : current;
    final isEmpty = current == null || current.isEmpty;
    return GestureDetector(
      onTap: _showQuickModelSelector,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isEmpty ? Colors.orange.withValues(alpha: 0.15) : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isEmpty ? Colors.orange : Colors.grey.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.model_training, size: 14, color: isEmpty ? Colors.orange : Colors.grey[700]),
            const SizedBox(width: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 110),
              child: Text(display, style: TextStyle(fontSize: 10, color: isEmpty ? Colors.orange : Colors.grey[800]), overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 2),
            const Icon(Icons.arrow_drop_down, size: 14),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _httpClient.close();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  String _toolPreview(String toolName, Map<String, dynamic> args) {
    switch (toolName) {
      case 'shell_exec':
        return '\$ ${args['command'] ?? ''}';
      case 'file_write':
        final content = args['content']?.toString() ?? '';
        final preview = content.length > 400 ? '${content.substring(0, 400)}...' : content;
        return '${args['path'] ?? ''}\n$preview';
      case 'file_edit':
        final oldStr = args['old_string']?.toString() ?? '';
        final newStr = args['new_string']?.toString() ?? '';
        final oldPrev = oldStr.length > 250 ? '${oldStr.substring(0, 250)}...' : oldStr;
        final newPrev = newStr.length > 250 ? '${newStr.substring(0, 250)}...' : newStr;
        return '${args['path'] ?? ''}\n--- SIL\n$oldPrev\n+++ EKLE\n$newPrev';
      default:
        return args.toString();
    }
  }

  /// Claude Code tarzi: modal dialog YOK, ekranin altinda onay bar bekler.
  Future<PermissionResponse> _handlePermission(String toolName, Map<String, dynamic> args) async {
    if (!mounted) return PermissionResponse.deny();
    if (PermissionGate.instance.mode == PermissionMode.bypass) return PermissionResponse.allow();

    final completer = Completer<PermissionResponse>();
    final approval = _PendingApproval(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      toolName: toolName,
      preview: _toolPreview(toolName, args),
      completer: completer,
    );
    setState(() => _pendingApproval = approval);
    _scrollToBottom();

    final response = await completer.future;
    if (response.dontAskAgain) PermissionGate.instance.allowForSession(toolName);
    if (mounted) setState(() => _pendingApproval = null);
    return response;
  }

  // --- Canli akis parse yardimcilari ---

  void _handleAgentChunk(String chunk) {
    final trimmed = chunk.trimLeft();

    // Tool baslangici: \n> tool: `name` `args`\n
    if (trimmed.startsWith('> tool: `')) {
      final match = RegExp(r'^> tool: `([^`]+)` `([\s\S]*?)`\n?$').firstMatch(trimmed);
      if (match != null) {
        setState(() {
          _activities.add(ToolActivity(
            id: '${DateTime.now().microsecondsSinceEpoch}_${_activities.length}',
            toolName: match.group(1)!,
            argsPreview: match.group(2)!,
          ));
          _statusLine = 'calisiyor: ${match.group(1)}';
        });
        _scrollToBottom();
        return;
      }
    }

    // Tool sonucu: \n< NAME: preview\n
    if (trimmed.startsWith('< ')) {
      final body = trimmed.substring(2).trimRight();
      final colonIdx = body.indexOf(':');
      final name = colonIdx > 0 ? body.substring(0, colonIdx).trim() : body;
      var output = colonIdx > 0 ? body.substring(colonIdx + 1).trim() : '';
      final isError = output.startsWith('[!]') || body.contains('Kullanıcı reddetti');
      // En son ayni isimli running karti bul ve tamamla
      for (final a in _activities.reversed) {
        if (a.toolName == name && a.status == 'running') {
          setState(() {
            a.status = isError ? 'error' : 'done';
            a.output = output.isEmpty ? '(cikti yok)' : output;
          });
          break;
        }
      }
      return;
    }

    // Subagent / sistem satirlari -> ayri bilgi karti gibi ama text olarak kalsin
    setState(() {
      _streamingText += chunk;
    });
    _scrollToBottom();
  }

  Future<void> _attachFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(allowMultiple: false, withData: false);
      if (result == null || result.files.isEmpty) return;
      final picked = result.files.first;
      String? content;
      String displayName = picked.name;
      if (picked.path != null) {
        final file = File(picked.path!);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          if (bytes.length <= 2 * 1024 * 1024) {
            try {
              content = String.fromCharCodes(bytes);
              final nonPrintable = content.codeUnits.where((c) => c < 32 && c != 10 && c != 13 && c != 9).length;
              if (nonPrintable > content.length * 0.3) content = null;
            } catch (_) {
              content = null;
            }
          }
          try {
            await WorkspaceFs.instance.writeBytes(displayName, bytes);
          } catch (_) {}
        }
      } else if (picked.bytes != null) {
        try {
          content = String.fromCharCodes(picked.bytes!);
          await WorkspaceFs.instance.writeBytes(displayName, picked.bytes!);
        } catch (_) {
          content = null;
        }
      }
      if (!mounted) return;
      final prefix = '[Attached: $displayName]';
      if (content != null && content.trim().isNotEmpty) {
        final truncated = content.length > 4000 ? '${content.substring(0, 4000)}\n...[truncated]' : content;
        final insertion = '$prefix\n```\n$truncated\n```\n';
        final current = _textController.text;
        _textController.text = current.isEmpty ? insertion : '$current\n\n$insertion';
      } else {
        final insertion = '$prefix (workspace\'e kopyalandi)';
        final current = _textController.text;
        _textController.text = current.isEmpty ? insertion : '$current\n\n$insertion';
      }
      _textController.selection = TextSelection.fromPosition(TextPosition(offset: _textController.text.length));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Dosya ekleme hatasi: $e')));
    }
  }

  bool _handleSlashCommand(String text) {
    final parts = text.split(RegExp(r'\s+'));
    final cmd = parts.first.toLowerCase();
    switch (cmd) {
      case '/clear':
        _clearChat();
        return true;
      case '/model':
        _showQuickModelSelector();
        return true;
      case '/help':
        _appendLocalSystemMessage('/clear temizle • /model sec • /plan on|off • /mode planAsk|acceptEdits|bypass • dosya ekle: klips ikonu');
        return true;
      case '/plan':
        if (!_agentMode) {
          _appendLocalSystemMessage('Once Agent switch acik olmali.');
          return true;
        }
        setState(() {
          _planMode = parts.length > 1 && parts[1].toLowerCase() == 'on';
          _planApproved = false;
        });
        _appendLocalSystemMessage('Plan Modu: ${_planMode ? "ACIK — once plan, sonra Uygula" : "KAPALI"}');
        return true;
      case '/mode':
        if (parts.length < 2) {
          _appendLocalSystemMessage('Kullanim: /mode planAsk|acceptEdits|bypass');
          return true;
        }
        final m = parts[1].toLowerCase();
        final target = m == 'acceptedits' || m == 'accept_edits'
            ? PermissionMode.acceptEdits
            : m == 'bypass'
                ? PermissionMode.bypass
                : PermissionMode.planAsk;
        if (target == PermissionMode.bypass) {
          _showError('Bypass modu Ayarlar\'dan onay ile acilir.');
          return true;
        }
        PermissionGate.instance.setMode(target);
        setState(() {});
        _appendLocalSystemMessage('Izin modu: ${target.displayName}');
        return true;
    }
    return false;
  }

  void _appendLocalSystemMessage(String text) {
    setState(() {
      _messages.add(ChatMessage(
        id: '${DateTime.now().microsecondsSinceEpoch}_sys',
        role: 'assistant',
        content: text,
        timestamp: DateTime.now(),
        presetId: 'local',
        sessionId: _sessionId,
      ));
    });
  }

  Future<void> _sendMessage() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _sending) return;

    // Slash komutlari — LLM'e gitmez
    if (text.startsWith('/')) {
      _textController.clear();
      _handleSlashCommand(text);
      return;
    }

    final presetId = _settingsRepo.getPresetId();
    final preset = presetId != null ? _chatRepository.resolvePreset(presetId) : null;
    if (preset == null) {
      _showError('Lutfen once Ayarlar ekranindan bir preset secin.');
      return;
    }

    final modelName = _settingsRepo.getModelName() ?? '';
    if (modelName.trim().isEmpty) {
      _showError('Lutfen once Ayarlar ekranindan bir model adi girin.');
      return;
    }
    final temperature = _settingsRepo.getTemperature();
    final apiKey = await _secureStorage.getApiKey(preset.id);
    final needsApiKey = preset.headers.values.any((v) => v.contains('{{API_KEY}}')) ||
        preset.urlQueryParams.values.any((v) => v.contains('{{API_KEY}}'));
    if (needsApiKey && (apiKey == null || apiKey.trim().isEmpty)) {
      _showError('Lutfen once Ayarlar ekranindan API anahtarinizi girin.');
      return;
    }

    final userMessage = ChatMessage(
      id: '${DateTime.now().microsecondsSinceEpoch}_user',
      role: 'user',
      content: text,
      timestamp: DateTime.now(),
      presetId: preset.id,
      sessionId: _sessionId,
    );

    setState(() {
      _messages.add(userMessage);
      _sending = true;
      _streamingText = '';
      _activities.clear();
      _statusLine = 'dusunuyor...';
      _textController.clear();
    });
    await _chatRepository.addMessage(userMessage);
    _scrollToBottom();

    final rawHistory = _messages.map((m) => {'role': m.role, 'content': m.content}).toList();
    final history = ContextCompactor.instance.compactForSession(rawHistory);
    final baseUrl = _settingsRepo.getBaseUrl();
    final useAgent = _agentMode && ToolDefinitions.presetSupportsTools(preset.id);

    try {
      if (useAgent) {
        final textBuffer = StringBuffer(); // sadece temiz metin (tool trace'siz)
        await for (final chunk in AgentLoop.instance.runTextStream(
          preset: preset,
          apiKey: apiKey,
          modelName: modelName,
          conversationHistory: history,
          temperature: temperature,
          baseUrl: baseUrl,
          onPermissionRequest: _handlePermission,
          onTodosUpdated: _onTodosUpdated,
          planMode: _planMode,
          planApproved: _planApproved,
        )) {
          _handleAgentChunk(chunk);
          // Tool trace satirlarini metinden ayikla
          if (!chunk.trimLeft().startsWith('> tool: `') &&
              !chunk.trimLeft().startsWith('< ') &&
              !chunk.startsWith('[subagent') &&
              !chunk.startsWith('\n[subagent') &&
              !chunk.contains('Kullanici reddetti — ajan alternatif')) {
            textBuffer.write(chunk);
          }
          if (!mounted) return;
          setState(() {});
        }
        await _appendAssistantMessage(preset.id, textBuffer.toString());
      } else if (preset.streamStrategy == StreamStrategy.none) {
        final result = await _httpClient.sendSingle(
          preset: preset,
          apiKey: apiKey,
          modelName: modelName,
          conversationHistory: history,
          temperature: temperature,
          baseUrl: baseUrl,
        );
        await _appendAssistantMessage(preset.id, result);
      } else {
        final buffer = StringBuffer();
        await for (final chunk in _httpClient.sendStream(
          preset: preset,
          apiKey: apiKey,
          modelName: modelName,
          conversationHistory: history,
          temperature: temperature,
          baseUrl: baseUrl,
        )) {
          buffer.write(chunk);
          if (!mounted) return;
          setState(() => _streamingText = buffer.toString());
          _scrollToBottom();
        }
        await _appendAssistantMessage(preset.id, buffer.toString());
      }
    } on ApiException catch (e) {
      _showError(friendlyErrorMessage(e));
    } catch (e) {
      _showError('Beklenmeyen bir hata olustu: $e');
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
          _statusLine = '';
          for (final a in _activities) {
            if (a.status == 'running') a.status = 'done';
          }
        });
      }
    }
  }

  Future<void> _appendAssistantMessage(String presetId, String content) async {
    if (content.trim().isEmpty) return;
    final assistantMessage = ChatMessage(
      id: '${DateTime.now().microsecondsSinceEpoch}_assistant',
      role: 'assistant',
      content: content,
      timestamp: DateTime.now(),
      presetId: presetId,
      sessionId: _sessionId,
    );
    if (mounted) {
      setState(() => _messages.add(assistantMessage));
    } else {
      _messages.add(assistantMessage);
    }
    await _chatRepository.addMessage(assistantMessage);
    setState(() => _streamingText = '');
    _scrollToBottom();
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red.shade700),
    );
  }

  void _clearChat() async {
    for (final m in List<ChatMessage>.from(_messages)) {
      await _chatRepository.deleteMessage(m.id);
    }
    await _chatRepository.deleteTodosForSession(_sessionId);
    PermissionGate.instance.clearSession();
    setState(() {
      _messages.clear();
      _todos.clear();
      _activities.clear();
      _streamingText = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final presetId = _settingsRepo.getPresetId();
    final preset = presetId != null ? _chatRepository.resolvePreset(presetId) : null;
    final supportsAgent = preset != null && ToolDefinitions.presetSupportsTools(preset.id);
    final permMode = PermissionGate.instance.mode;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('ff.chat', style: TextStyle(fontSize: 18)),
            const SizedBox(width: 8),
            _buildModelChip(),
          ],
        ),
        actions: [
          if (supportsAgent)
            Row(
              children: [
                const Text('Agent', style: TextStyle(fontSize: 12)),
                Switch(
                  value: _agentMode,
                  onChanged: (v) => setState(() {
                    _agentMode = v;
                    if (!v) {
                      _planMode = false;
                      _planApproved = false;
                    }
                  }),
                ),
              ],
            ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (v) {
              if (v == 'clear') _clearChat();
              if (v == 'settings') Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
              if (v == 'help') _handleSlashCommand('/help');
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'help', child: Text('Komutlar (/help)')),
              const PopupMenuItem(value: 'clear', child: Text('Sohbeti temizle')),
              const PopupMenuItem(value: 'settings', child: Text('Ayarlar')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Durum seridi
          if (supportsAgent && _agentMode)
            Container(
              width: double.infinity,
              color: permMode == PermissionMode.bypass
                  ? Colors.red.withValues(alpha: 0.12)
                  : Colors.green.withValues(alpha: 0.08),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              child: Row(
                children: [
                  Icon(
                    permMode == PermissionMode.bypass ? Icons.warning : Icons.smart_toy,
                    size: 13,
                    color: permMode == PermissionMode.bypass ? Colors.red : Colors.green,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      permMode == PermissionMode.bypass
                          ? 'BYPASS — hic sormaz (riskli)'
                          : permMode == PermissionMode.acceptEdits
                              ? 'Accept Edits — shell sorar'
                              : 'Plan/Ask — riskli islem sorar',
                      style: TextStyle(fontSize: 10, color: permMode == PermissionMode.bypass ? Colors.red : Colors.green),
                    ),
                  ),
                  if (_planMode)
                    GestureDetector(
                      onTap: () {
                        if (_todos.isNotEmpty && !_planApproved) {
                          setState(() => _planApproved = true);
                        } else {
                          setState(() => _planApproved = false);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: (_planApproved ? Colors.green : Colors.purple).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                        child: Text(_planApproved ? 'PLAN ONAYLI' : 'PLAN MODU', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: _planApproved ? Colors.green : Colors.purple)),
                      ),
                    ),
                ],
              ),
            ),
          // Todo checklist
          if (_todos.isNotEmpty) _buildTodoPanel(),
          // Mesajlar + canli tool kartlari
          Expanded(
            child: _messages.isEmpty && _activities.isEmpty && _streamingText.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.terminal, size: 44, color: Colors.grey.withValues(alpha: 0.6)),
                          const SizedBox(height: 12),
                          Text('Ajana bir gorev ver', style: TextStyle(color: Colors.grey.withValues(alpha: 0.9))),
                          const SizedBox(height: 8),
                          Text('"todo app yap, calistir, test et"\n\n/komutlar icin /help', style: TextStyle(fontSize: 12, color: Colors.grey.withValues(alpha: 0.7)), textAlign: TextAlign.center),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(10),
                    itemCount: _messages.length + _activities.length + ((_streamingText.isNotEmpty) ? 1 : 0),
                    itemBuilder: (context, index) {
                      // Once gecmis mesajlar
                      if (index < _messages.length) {
                        final message = _messages[index];
                        return _MessageBubble(role: message.role, content: message.content);
                      }
                      final liveIndex = index - _messages.length;
                      // Canli tool kartlari
                      if (liveIndex < _activities.length) {
                        return ToolActivityCard(activity: _activities[liveIndex]);
                      }
                      // Streaming metin
                      return _MessageBubble(role: 'assistant', content: _streamingText);
                    },
                  ),
          ),
          // Status line
          if (_sending)
            Padding(
              padding: const EdgeInsets.only(left: 14, bottom: 4),
              child: Row(
                children: [
                  const SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 8),
                  Text(_statusLine.isEmpty ? 'calisiyor...' : _statusLine, style: const TextStyle(fontSize: 11, color: Colors.blueGrey)),
                ],
              ),
            ),
          // Alt onay bar — Claude Code tarzi
          if (_pendingApproval != null)
            PermissionPromptBar(
              key: ValueKey(_pendingApproval!.id),
              toolName: _pendingApproval!.toolName,
              preview: _pendingApproval!.preview,
              onRespond: (r) => _pendingApproval!.completer.complete(r),
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.attach_file),
                    tooltip: 'Dosya ekle',
                    onPressed: _sending ? null : _attachFile,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      minLines: 1,
                      maxLines: 5,
                      enabled: !_sending,
                      decoration: InputDecoration(
                        hintText: _sending ? 'ajan calisiyor...' : 'Gorev yaz (/help)',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sending ? null : _sendMessage,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTodoPanel() {
    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.checklist, size: 13),
              const SizedBox(width: 6),
              Text('Plan (${_todos.where((t) => t['status'] == 'completed').length}/${_todos.length})', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              const Spacer(),
              GestureDetector(
                onTap: () => setState(() => _todos.clear()),
                child: Text('temizle', style: TextStyle(fontSize: 10, color: Colors.grey[600])),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Wrap(
            spacing: 10,
            runSpacing: 3,
            children: _todos.map((todo) {
              final status = todo['status']?.toString() ?? 'pending';
              IconData icon;
              Color color;
              switch (status) {
                case 'in_progress':
                  icon = Icons.hourglass_top;
                  color = Colors.blue;
                  break;
                case 'completed':
                  icon = Icons.check_circle;
                  color = Colors.green;
                  break;
                case 'cancelled':
                  icon = Icons.cancel;
                  color = Colors.red;
                  break;
                default:
                  icon = Icons.radio_button_unchecked;
                  color = Colors.grey;
              }
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 11, color: color),
                  const SizedBox(width: 4),
                  Text(todo['content']?.toString() ?? '', style: TextStyle(fontSize: 10.5, color: color, decoration: status == 'completed' ? TextDecoration.lineThrough : null)),
                ],
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _PendingApproval {
  _PendingApproval({
    required this.id,
    required this.toolName,
    required this.preview,
    required this.completer,
  });

  final String id;
  final String toolName;
  final String preview;
  final Completer<PermissionResponse> completer;
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.role, required this.content});

  final String role;
  final String content;

  @override
  Widget build(BuildContext context) {
    final isUser = role == 'user';
    final theme = Theme.of(context);
    final bubbleColor = isUser ? theme.colorScheme.primary : theme.colorScheme.surfaceContainerHighest;
    final textColor = isUser ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.85),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
        ),
        child: SelectableText(content, style: TextStyle(color: textColor, fontSize: 14, height: 1.35)),
      ),
    );
  }
}
