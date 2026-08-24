import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/agent/agent_loop.dart';
import '../../core/agent/context_compaction.dart';
import '../../core/agent/permission_gate.dart';
import '../../core/agent/tool_definitions.dart';
import '../../core/http/dynamic_http_client.dart';
import '../../core/presets/builtin_presets.dart';
import '../../core/workspace/workspace_fs.dart';
import '../settings/settings_screen.dart';
import '../../core/http/dynamic_http_client.dart';
import '../../core/http/friendly_error.dart';
import '../../core/models/preset.dart';
import '../../core/storage/app_settings_repository.dart';
import '../../core/storage/chat_repository.dart';
import '../../core/storage/local_database.dart';
import '../../core/storage/secure_key_storage.dart';

/// Minimalist sohbet ekrani: mesaj listesi + alt input + Agent mode + Permission Gate.
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
  bool _planMode = false; // Gercek Plan Modu: once plan yaz, onaydan sonra uygula
  bool _planApproved = false;
  List<Map<String, dynamic>> _todos = [];
  List<String> _quickModels = [];
  bool _quickModelsLoading = false;

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
    // Todolari yukle
    final storedTodos = _chatRepository.getTodosForSession(_sessionId);
    if (storedTodos.isNotEmpty) {
      _todos = storedTodos.map((t) => {'content': t.content, 'status': t.status, 'priority': t.priority}).toList();
    }
    // Hizli model listesini yukle
    _loadQuickModels();
  }

  void _onTodosUpdated(List<Map<String, dynamic>> todos) {
    setState(() => _todos = List<Map<String, dynamic>>.from(todos));
    // Hive'a persist et
    _chatRepository.saveTodos(_sessionId, todos);
  }

  Future<void> _loadQuickModels() async {
    final presetId = _settingsRepo.getPresetId();
    final preset = presetId != null ? _chatRepository.resolvePreset(presetId) : null;
    if (preset == null) return;
    // Known models varsa onlari kullan (Anthropic gibi)
    if (preset.knownModels != null && preset.knownModels!.isNotEmpty) {
      if (mounted) setState(() => _quickModels = preset.knownModels!);
      return;
    }
    // Yoksa gecici olarak bossa birak, Settings'te Test ile dolacak
    // Dinamik fetch denemesi (sadece http destekleyen preset'lerde)
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
      // sessizce yut, Settings'te denenecek
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
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Model: $m')));
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
        return 'Komut: ${args['command'] ?? ''}\nWorkdir: ${args['workdir'] ?? '.'}';
      case 'file_write':
        final content = args['content']?.toString() ?? '';
        final preview = content.length > 300 ? '${content.substring(0, 300)}...' : content;
        return 'Yol: ${args['path'] ?? ''}\nIcerik:\n$preview';
      case 'file_edit':
        final oldStr = args['old_string']?.toString() ?? '';
        final newStr = args['new_string']?.toString() ?? '';
        final oldPrev = oldStr.length > 150 ? '${oldStr.substring(0, 150)}...' : oldStr;
        final newPrev = newStr.length > 150 ? '${newStr.substring(0, 150)}...' : newStr;
        return 'Yol: ${args['path'] ?? ''}\n- $oldPrev\n+ $newPrev';
      case 'file_glob':
        return 'Glob: ${args['pattern'] ?? ''}\nKlasor: ${args['path'] ?? '.'}';
      case 'file_grep':
        return 'Grep: ${args['pattern'] ?? ''}\nYol: ${args['path'] ?? '.'}\nGlob: ${args['glob'] ?? 'tumu'}';
      case 'file_delete':
        return 'Silinecek: ${args['path'] ?? ''}';
      case 'file_read':
        return 'Okunacak: ${args['path'] ?? ''}';
      case 'file_list':
        return 'Listelenecek: ${args['path'] ?? '.'}';
      default:
        return args.toString();
    }
  }

  Future<PermissionResponse> _handlePermission(String toolName, Map<String, dynamic> args) async {
    if (!mounted) return PermissionResponse.deny();
    final mode = PermissionGate.instance.mode;

    // Bypass modunda zaten buraya gelmemeli ama gelirse auto-approve
    if (mode == PermissionMode.bypass) return PermissionResponse.allow();

    final preview = _toolPreview(toolName, args);
    bool dontAskAgain = false;

    // Ana izin dialogu
    final action = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Row(
            children: [
              Icon(
                toolName == 'shell_exec' ? Icons.terminal : Icons.description,
                size: 20,
                color: toolName == 'shell_exec' ? Colors.red : Colors.blue,
              ),
              const SizedBox(width: 8),
              Expanded(child: Text('Izin gerekli — $toolName', style: const TextStyle(fontSize: 16))),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    preview,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Color(0xFFD4D4D4)),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Bu islem workspace icinde calisacak. Onayliyor musun?',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  value: dontAskAgain,
                  onChanged: (v) => setState(() => dontAskAgain = v ?? false),
                  title: const Text('Bu oturumda bu tool icin bir daha sorma', style: TextStyle(fontSize: 11)),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
                if (mode == PermissionMode.planAsk)
                  const Text('Mod: Plan/Ask (en guvenli)', style: TextStyle(fontSize: 10, color: Colors.green)),
                if (mode == PermissionMode.acceptEdits)
                  const Text('Mod: Accept Edits (dosya otomatik, shell sorar)', style: TextStyle(fontSize: 10, color: Colors.orange)),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, 'deny'),
              child: const Text('Reddet'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'edit'),
              child: const Text('Duzenle'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, dontAskAgain ? 'allow_session' : 'allow'),
              child: const Text('Onayla'),
            ),
          ],
        ),
      ),
    );

    if (action == null || action == 'deny') {
      return PermissionResponse.deny();
    }
    if (action == 'allow' || action == 'allow_session') {
      final allowSession = action == 'allow_session';
      if (allowSession) PermissionGate.instance.allowForSession(toolName);
      return PermissionResponse.allow(dontAskAgain: allowSession);
    }
    if (action == 'edit') {
      // Duzenle -> args'i duzenle
      final edited = await _showEditDialog(toolName, args);
      if (edited == null) return PermissionResponse.deny(); // edit iptal -> reddet
      // Duzenlenen args ile onayla
      if (dontAskAgain) PermissionGate.instance.allowForSession(toolName);
      return PermissionResponse.allow(editedArgs: edited, dontAskAgain: dontAskAgain);
    }
    return PermissionResponse.deny();
  }

  Future<Map<String, dynamic>?> _showEditDialog(String toolName, Map<String, dynamic> args) async {
    if (toolName == 'shell_exec') {
      final controller = TextEditingController(text: args['command']?.toString() ?? '');
      final workdirController = TextEditingController(text: args['workdir']?.toString() ?? '.');
      final result = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Komutu duzenle'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: controller, decoration: const InputDecoration(labelText: 'Komut', border: OutlineInputBorder()), maxLines: 3, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
              const SizedBox(height: 8),
              TextField(controller: workdirController, decoration: const InputDecoration(labelText: 'Workdir', border: OutlineInputBorder()), style: const TextStyle(fontSize: 12)),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Iptal')),
            FilledButton(onPressed: () => Navigator.pop(context, {'command': controller.text, 'workdir': workdirController.text}), child: const Text('Kaydet ve calistir')),
          ],
        ),
      );
      return result;
    } else if (toolName == 'file_write') {
      final pathController = TextEditingController(text: args['path']?.toString() ?? '');
      final contentController = TextEditingController(text: args['content']?.toString() ?? '');
      final result = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Dosyayi duzenle'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: pathController, decoration: const InputDecoration(labelText: 'Yol', border: OutlineInputBorder()), style: const TextStyle(fontSize: 12)),
                const SizedBox(height: 8),
                SizedBox(
                  height: 200,
                  child: TextField(controller: contentController, decoration: const InputDecoration(labelText: 'Icerik', border: OutlineInputBorder()), maxLines: null, expands: true, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Iptal')),
            FilledButton(onPressed: () => Navigator.pop(context, {'path': pathController.text, 'content': contentController.text}), child: const Text('Kaydet ve calistir')),
          ],
        ),
      );
      return result;
    } else if (toolName == 'file_delete') {
      final pathController = TextEditingController(text: args['path']?.toString() ?? '');
      final result = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Silinecek yolu duzenle'),
          content: TextField(controller: pathController, decoration: const InputDecoration(labelText: 'Yol', border: OutlineInputBorder())),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Iptal')),
            FilledButton(onPressed: () => Navigator.pop(context, {'path': pathController.text}), child: const Text('Kaydet ve calistir')),
          ],
        ),
      );
      return result;
    } else if (toolName == 'file_edit') {
      final pathController = TextEditingController(text: args['path']?.toString() ?? '');
      final oldController = TextEditingController(text: args['old_string']?.toString() ?? '');
      final newController = TextEditingController(text: args['new_string']?.toString() ?? '');
      final result = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Duzenlemeyi duzenle (diff)'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: pathController, decoration: const InputDecoration(labelText: 'Yol', border: OutlineInputBorder()), style: const TextStyle(fontSize: 12)),
                  const SizedBox(height: 8),
                  TextField(controller: oldController, decoration: const InputDecoration(labelText: 'old_string (unique)', border: OutlineInputBorder()), maxLines: 4, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
                  const SizedBox(height: 8),
                  TextField(controller: newController, decoration: const InputDecoration(labelText: 'new_string', border: OutlineInputBorder()), maxLines: 4, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Iptal')),
            FilledButton(onPressed: () => Navigator.pop(context, {'path': pathController.text, 'old_string': oldController.text, 'new_string': newController.text}), child: const Text('Kaydet ve calistir')),
          ],
        ),
      );
      return result;
    } else if (toolName == 'file_glob') {
      final patternController = TextEditingController(text: args['pattern']?.toString() ?? '');
      final pathController = TextEditingController(text: args['path']?.toString() ?? '.');
      final result = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Glob duzenle'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: patternController, decoration: const InputDecoration(labelText: 'Pattern (or **/*.dart)', border: OutlineInputBorder()), style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 8),
            TextField(controller: pathController, decoration: const InputDecoration(labelText: 'Path', border: OutlineInputBorder()), style: const TextStyle(fontSize: 12)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Iptal')),
            FilledButton(onPressed: () => Navigator.pop(context, {'pattern': patternController.text, 'path': pathController.text}), child: const Text('Kaydet ve calistir')),
          ],
        ),
      );
      return result;
    } else if (toolName == 'file_grep') {
      final patternController = TextEditingController(text: args['pattern']?.toString() ?? '');
      final pathController = TextEditingController(text: args['path']?.toString() ?? '.');
      final globController = TextEditingController(text: args['glob']?.toString() ?? '');
      final result = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Grep duzenle'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: patternController, decoration: const InputDecoration(labelText: 'Pattern (regex)', border: OutlineInputBorder()), style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 8),
            TextField(controller: pathController, decoration: const InputDecoration(labelText: 'Path', border: OutlineInputBorder()), style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 8),
            TextField(controller: globController, decoration: const InputDecoration(labelText: 'Glob (opsiyonel, or *.dart)', border: OutlineInputBorder()), style: const TextStyle(fontSize: 12)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Iptal')),
            FilledButton(onPressed: () => Navigator.pop(context, {'pattern': patternController.text, 'path': pathController.text, 'glob': globController.text}), child: const Text('Kaydet ve calistir')),
          ],
        ),
      );
      return result;
    }
    return null;
  }

  Future<void> _attachFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(allowMultiple: false, withData: false);
      if (result == null || result.files.isEmpty) return;
      final picked = result.files.first;
      String? content;
      String displayName = picked.name;
      // Workspace'e kopyala (genel erisim: nereden isterse)
      if (picked.path != null) {
        final file = File(picked.path!);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          // 2MB uzeri binary ise sadece yol ekle, icerik degil
          if (bytes.length > 2 * 1024 * 1024) {
            content = null;
          } else {
            try {
              content = String.fromCharCodes(bytes);
              // Binary kontrol: cok fazla non-printable
              final nonPrintable = content.codeUnits.where((c) => c < 32 && c != 10 && c != 13 && c != 9).length;
              if (nonPrintable > content.length * 0.3) content = null;
            } catch (_) {
              content = null;
            }
          }
          // Workspace'e kopyala
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
      // Mesaj kutusuna ekle
      final prefix = '[Attached: $displayName]';
      if (content != null && content.trim().isNotEmpty) {
        final truncated = content.length > 4000 ? '${content.substring(0, 4000)}\n...[truncated]' : content;
        final insertion = '$prefix\n```\n$truncated\n```\n';
        final current = _textController.text;
        _textController.text = current.isEmpty ? insertion : '$current\n\n$insertion';
      } else {
        final insertion = '$prefix (binary veya bos, workspace\'e kopyalandi: $displayName)';
        final current = _textController.text;
        _textController.text = current.isEmpty ? insertion : '$current\n\n$insertion';
      }
      _textController.selection = TextSelection.fromPosition(TextPosition(offset: _textController.text.length));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$displayName eklendi')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Dosya ekleme hatasi: $e')));
    }
  }

  Future<void> _sendMessage() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _sending) return;

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
      _textController.clear();
    });
    await _chatRepository.addMessage(userMessage);
    _scrollToBottom();

    final rawHistory = _messages.map((m) => {'role': m.role, 'content': m.content}).toList();
    final history = ContextCompactor.instance.compactForSession(rawHistory);
    if (history.length != rawHistory.length && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Context compacted: ${rawHistory.length} -> ${history.length} mesaj'), duration: const Duration(seconds: 2)),
      );
    }
    final baseUrl = _settingsRepo.getBaseUrl();
    final useAgent = _agentMode && ToolDefinitions.presetSupportsTools(preset.id);

    try {
      if (useAgent) {
        final buffer = StringBuffer();
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
          buffer.write(chunk);
          if (!mounted) return;
          setState(() => _streamingText = buffer.toString());
          _scrollToBottom();
        }
        await _appendAssistantMessage(preset.id, buffer.toString());
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
          _streamingText = '';
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
    _scrollToBottom();
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red.shade700),
    );
  }

  void _clearChat() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sohbet temizlensin mi?'),
        content: const Text('Bu oturumdaki tum mesajlar silinecek.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Iptal')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Temizle')),
        ],
      ),
    );
    if (confirm != true) return;
    for (final m in List<ChatMessage>.from(_messages)) {
      await _chatRepository.deleteMessage(m.id);
    }
    await _chatRepository.deleteTodosForSession(_sessionId);
    PermissionGate.instance.clearSession();
    setState(() {
      _messages.clear();
      _todos.clear();
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
          if (supportsAgent && _agentMode)
            Row(
              children: [
                const Text('Plan', style: TextStyle(fontSize: 11)),
                Switch(
                  value: _planMode,
                  onChanged: (v) => setState(() {
                    _planMode = v;
                    _planApproved = false;
                  }),
                ),
              ],
            ),
          IconButton(icon: const Icon(Icons.delete_outline), onPressed: _messages.isEmpty ? null : _clearChat, tooltip: 'Temizle'),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Ayarlar',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
      body: Column(
        children: [
          if (supportsAgent && _agentMode)
            Container(
              width: double.infinity,
              color: permMode == PermissionMode.bypass
                  ? Colors.red.withValues(alpha: 0.12)
                  : Colors.green.withValues(alpha: 0.1),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  Icon(
                    permMode == PermissionMode.bypass ? Icons.warning : Icons.smart_toy,
                    size: 14,
                    color: permMode == PermissionMode.bypass ? Colors.red : Colors.green,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      permMode == PermissionMode.bypass
                          ? 'Agent BYPASS — hic sormadan calisir (riskli)'
                          : permMode == PermissionMode.acceptEdits
                              ? 'Agent Accept Edits — dosya otomatik, shell sorar'
                              : 'Agent Plan/Ask — her shell/yazma/silme sorar (onerilen)',
                      style: TextStyle(fontSize: 11, color: permMode == PermissionMode.bypass ? Colors.red : Colors.green),
                    ),
                  ),
                ],
              ),
            ),
          if (supportsAgent && !_agentMode)
            Container(
              width: double.infinity,
              color: Colors.orange.withValues(alpha: 0.1),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: const Text('Agent kapali — sadece chat', style: TextStyle(fontSize: 11, color: Colors.orange)),
            ),
          if (supportsAgent && _agentMode && _planMode)
            Container(
              width: double.infinity,
              color: _planApproved ? Colors.green.withValues(alpha: 0.1) : Colors.purple.withValues(alpha: 0.1),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  Icon(_planApproved ? Icons.check_circle : Icons.assignment, size: 14, color: _planApproved ? Colors.green : Colors.purple),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _planApproved ? 'Plan onaylandi — uygulama serbest' : 'Plan Modu: once plan yazilacak, onay bekleniyor',
                      style: TextStyle(fontSize: 11, color: _planApproved ? Colors.green : Colors.purple),
                    ),
                  ),
                  if (!_planApproved && _todos.isNotEmpty)
                    FilledButton.tonal(
                      onPressed: () => setState(() => _planApproved = true),
                      style: FilledButton.styleFrom(minimumSize: Size.zero, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                      child: const Text('Uygula', style: TextStyle(fontSize: 11)),
                    ),
                ],
              ),
            ),
          if (_todos.isNotEmpty)
            Container(
              width: double.infinity,
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.checklist, size: 14),
                      const SizedBox(width: 6),
                      Text('Plan (${_todos.where((t) => t['status'] == 'completed').length}/${_todos.length})', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      const Spacer(),
                      TextButton(
                        onPressed: () => setState(() => _todos.clear()),
                        style: TextButton.styleFrom(minimumSize: Size.zero, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2)),
                        child: const Text('Temizle', style: TextStyle(fontSize: 10)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ..._todos.map((todo) {
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
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Row(
                        children: [
                          Icon(icon, size: 12, color: color),
                          const SizedBox(width: 6),
                          Expanded(child: Text(todo['content']?.toString() ?? '', style: TextStyle(fontSize: 11, color: color, decoration: status == 'completed' ? TextDecoration.lineThrough : null))),
                          if (todo['priority'] == 'high') const Icon(Icons.flag, size: 10, color: Colors.red),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          Expanded(
            child: _messages.isEmpty && _streamingText.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.chat_bubble_outline, size: 48, color: Colors.grey),
                          const SizedBox(height: 12),
                          const Text('Henuz mesaj yok', style: TextStyle(color: Colors.grey)),
                          const SizedBox(height: 8),
                          Text(
                            supportsAgent && _agentMode
                                ? 'Ornek: "workspace\'te main.dart olustur ve hello world yaz"'
                                : 'Bir mesaj yazarak baslayin',
                            style: TextStyle(fontSize: 12, color: Colors.grey.withValues(alpha: 0.9)),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(12),
                    itemCount: _messages.length + (_streamingText.isNotEmpty ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _messages.length) {
                        return _MessageBubble(role: 'assistant', content: _streamingText);
                      }
                      final message = _messages[index];
                      return _MessageBubble(role: message.role, content: message.content);
                    },
                  ),
          ),
          if (_sending && _streamingText.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.attach_file),
                    tooltip: 'Dosya ekle (genel erisim)',
                    onPressed: _sending ? null : _attachFile,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      minLines: 1,
                      maxLines: 5,
                      enabled: !_sending,
                      decoration: const InputDecoration(
                        hintText: 'Mesajinizi yazin...',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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

    final isToolTrace = content.contains('tool:') || content.contains('shell_exec') || content.contains('file_');

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
        decoration: BoxDecoration(
          color: isToolTrace && !isUser ? const Color(0xFF1E1E1E) : bubbleColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: SelectableText(
          content,
          style: TextStyle(
            color: isToolTrace && !isUser ? const Color(0xFF4EC9B0) : textColor,
            fontFamily: isToolTrace && !isUser ? 'monospace' : null,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}
