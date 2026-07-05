import '../models/preset.dart';
import 'local_database.dart';

/// Hive tabanlı yerel veritabanı üzerinde çalışan basit repository katmanı.
///
/// Sohbet mesajları/oturumları ve preset CRUD işlemleri buradan yürütülür.
/// [LocalDatabase.init] uygulama başlangıcında çağrılmış olmalıdır.
class ChatRepository {
  // --- Mesajlar ---

  Future<void> addMessage(ChatMessage message) async {
    await LocalDatabase.messagesBox.put(message.id, message);
  }

  List<ChatMessage> getMessagesForSession(String sessionId) {
    return LocalDatabase.messagesBox.values
        .where((m) => m.sessionId == sessionId)
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }

  List<ChatMessage> getAllMessages() {
    final messages = LocalDatabase.messagesBox.values.toList();
    messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return messages;
  }

  Future<void> deleteMessage(String id) async {
    await LocalDatabase.messagesBox.delete(id);
  }

  // --- Sohbet oturumları ---

  Future<void> saveSession(ChatSession session) async {
    await LocalDatabase.sessionsBox.put(session.id, session);
  }

  List<ChatSession> getAllSessions() {
    final sessions = LocalDatabase.sessionsBox.values.toList();
    sessions.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return sessions;
  }

  ChatSession? getSession(String id) => LocalDatabase.sessionsBox.get(id);

  Future<void> deleteSession(String id) async {
    await LocalDatabase.sessionsBox.delete(id);
    final messageKeys = LocalDatabase.messagesBox.values
        .where((m) => m.sessionId == id)
        .map((m) => m.id)
        .toList();
    await LocalDatabase.messagesBox.deleteAll(messageKeys);
  }

  // --- Presetler ---

  Future<void> savePreset(Preset preset) async {
    await LocalDatabase.presetsBox.put(preset.id, preset.toJson());
  }

  Preset? getPreset(String id) {
    final json = LocalDatabase.presetsBox.get(id);
    if (json == null) return null;
    return Preset.fromJson(Map<String, dynamic>.from(json));
  }

  List<Preset> getAllPresets() {
    return LocalDatabase.presetsBox.values
        .map((json) => Preset.fromJson(Map<String, dynamic>.from(json)))
        .toList();
  }

  Future<void> deletePreset(String id) async {
    await LocalDatabase.presetsBox.delete(id);
  }
}
