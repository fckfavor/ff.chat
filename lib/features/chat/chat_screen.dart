import 'package:flutter/material.dart';

import '../../core/http/dynamic_http_client.dart';
import '../../core/models/preset.dart';
import '../../core/storage/app_settings_repository.dart';
import '../../core/storage/chat_repository.dart';
import '../../core/storage/local_database.dart';
import '../../core/storage/secure_key_storage.dart';

/// Minimalist sohbet ekranı: mesaj listesi + alt input.
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

  @override
  void initState() {
    super.initState();
    _sessionId = DateTime.now().millisecondsSinceEpoch.toString();
    _messages.addAll(_chatRepository.getMessagesForSession(_sessionId));
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

  Future<void> _sendMessage() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _sending) return;

    final presetId = _settingsRepo.getPresetId();
    final preset = presetId != null ? _chatRepository.getPreset(presetId) : null;
    if (preset == null) {
      _showError('Lütfen önce Ayarlar ekranından bir preset seçin.');
      return;
    }

    final modelName = _settingsRepo.getModelName() ?? '';
    final temperature = _settingsRepo.getTemperature();
    final apiKey = await _secureStorage.getApiKey(preset.id);

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

    final history = _messages
        .map((m) => {'role': m.role, 'content': m.content})
        .toList();

    try {
      if (preset.streamStrategy == StreamStrategy.none) {
        final result = await _httpClient.sendSingle(
          preset: preset,
          apiKey: apiKey,
          modelName: modelName,
          conversationHistory: history,
          temperature: temperature,
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
        )) {
          buffer.write(chunk);
          setState(() => _streamingText = buffer.toString());
          _scrollToBottom();
        }
        await _appendAssistantMessage(preset.id, buffer.toString());
      }
    } on ApiException catch (e) {
      _showError(_friendlyErrorMessage(e));
    } catch (e) {
      _showError('Beklenmeyen bir hata oluştu: $e');
    } finally {
      setState(() {
        _sending = false;
        _streamingText = '';
      });
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
    setState(() => _messages.add(assistantMessage));
    await _chatRepository.addMessage(assistantMessage);
    _scrollToBottom();
  }

  String _friendlyErrorMessage(ApiException e) {
    switch (e.statusCode) {
      case 401:
        return 'API anahtarı geçersiz veya eksik. Lütfen Ayarlar\'ı kontrol edin.';
      case 429:
        return 'İstek limiti aşıldı. Lütfen bir süre sonra tekrar deneyin.';
      default:
        if (e.statusCode >= 500) {
          return 'Sunucu tarafında bir sorun oluştu. Lütfen daha sonra tekrar deneyin.';
        }
        return 'İstek başarısız oldu (${e.statusCode}): ${e.parsedMessage}';
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red.shade700),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ff.chat')),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
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
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      minLines: 1,
                      maxLines: 5,
                      decoration: const InputDecoration(
                        hintText: 'Mesajınızı yazın...',
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
    final bubbleColor = isUser
        ? theme.colorScheme.primary
        : theme.colorScheme.surfaceContainerHighest;
    final textColor = isUser ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(content, style: TextStyle(color: textColor)),
      ),
    );
  }
}
