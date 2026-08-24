import 'package:hive/hive.dart';

import '../models/preset.dart';
import '../presets/builtin_presets.dart';
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

  /// Hem kullanıcı tanımlı (kayıtlı) presetleri hem de uygulamayla birlikte
  /// gelen built-in presetleri (BuiltinPresets.all) arar. ChatScreen gibi
  /// ekranlar, Ayarlar'da seçilen bir built-in preset id'sini bu metodla
  /// çözmelidir; sadece [getPreset] kullanmak built-in presetleri hiç
  /// bulamaz (o metod yalnızca presetsBox'ta kayıtlı özel presetlere bakar).
  Preset? resolvePreset(String id) {
    final custom = getPreset(id);
    if (custom != null) return custom;
    for (final p in BuiltinPresets.all) {
      if (p.id == id) return p;
    }
    return null;
  }

  List<Preset> getAllPresets() {
    return LocalDatabase.presetsBox.values
        .map((json) => Preset.fromJson(Map<String, dynamic>.from(json)))
        .toList();
  }

  Future<void> deletePreset(String id) async {
    await LocalDatabase.presetsBox.delete(id);
  }

  // --- Todolar (Agent plan) ---

  Box<TodoItem>? _safeTodosBox() {
    try {
      if (Hive.isBoxOpen(LocalDatabase.todosBoxName)) {
        return Hive.box<TodoItem>(LocalDatabase.todosBoxName);
      }
      // Test ortaminda box henuz acilmamissa, LocalDatabase uzerinden dene
      try {
        return LocalDatabase.todosBox;
      } catch (_) {
        return null;
      }
    } catch (_) {
      return null;
    }
  }

  List<TodoItem> getTodosForSession(String sessionId) {
    final box = _safeTodosBox();
    if (box == null) return [];
    return box.values.where((t) => t.sessionId == sessionId).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  Future<void> putTodo(TodoItem todo) async {
    final box = _safeTodosBox();
    if (box == null) return;
    await box.put(todo.id, todo);
  }

  Future<void> saveTodos(String sessionId, List<Map<String, dynamic>> todos) async {
    final box = _safeTodosBox();
    if (box == null) return;
    // Once bu oturumun eski todolarini sil
    final oldKeys = box.values.where((t) => t.sessionId == sessionId).map((t) => t.id).toList();
    await box.deleteAll(oldKeys);
    for (final t in todos) {
      final item = TodoItem(
        id: t['id']?.toString() ?? '${DateTime.now().microsecondsSinceEpoch}_${t['content']}',
        sessionId: sessionId,
        content: t['content']?.toString() ?? '',
        status: t['status']?.toString() ?? 'pending',
        priority: t['priority']?.toString() ?? 'medium',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await box.put(item.id, item);
    }
  }

  Future<void> deleteTodosForSession(String sessionId) async {
    final box = _safeTodosBox();
    if (box == null) return;
    final keys = box.values.where((t) => t.sessionId == sessionId).map((t) => t.id).toList();
    await box.deleteAll(keys);
  }

  Future<void> updateTodoStatus(String id, String status) async {
    final box = _safeTodosBox();
    if (box == null) return;
    final todo = box.get(id);
    if (todo != null) {
      todo.status = status;
      todo.updatedAt = DateTime.now();
      await todo.save();
    }
  }
}
