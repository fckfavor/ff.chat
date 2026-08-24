import 'package:hive_flutter/hive_flutter.dart';

import '../models/http_tool_plugin.dart';

/// Yerel veritabanında saklanan tek bir sohbet mesajı.
class ChatMessage extends HiveObject {
  ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.timestamp,
    required this.presetId,
    this.sessionId,
  });

  final String id;
  final String role; // 'user' | 'assistant' | 'system'
  final String content;
  final DateTime timestamp;
  final String presetId;
  final String? sessionId;
}

/// Bir sohbet oturumunu (mesaj grubu) temsil eder.
class ChatSession extends HiveObject {
  ChatSession({
    required this.id,
    required this.title,
    required this.presetId,
    required this.createdAt,
    this.updatedAt,
    this.summary,
  });

  final String id;
  final String title;
  final String presetId;
  final DateTime createdAt;
  DateTime? updatedAt;
  String? summary; // compaction ozeti (optional, migration-safe)
}

// --- Manuel Hive TypeAdapter'ları ---
// build_runner / code generation kullanmadan basit tutuldu.

class ChatMessageAdapter extends TypeAdapter<ChatMessage> {
  @override
  final int typeId = 1;

  @override
  ChatMessage read(BinaryReader reader) {
    final numFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numFields; i++) reader.readByte(): reader.read(),
    };
    return ChatMessage(
      id: fields[0] as String,
      role: fields[1] as String,
      content: fields[2] as String,
      timestamp: fields[3] as DateTime,
      presetId: fields[4] as String,
      sessionId: fields[5] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, ChatMessage obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.role)
      ..writeByte(2)
      ..write(obj.content)
      ..writeByte(3)
      ..write(obj.timestamp)
      ..writeByte(4)
      ..write(obj.presetId)
      ..writeByte(5)
      ..write(obj.sessionId);
  }
}

class ChatSessionAdapter extends TypeAdapter<ChatSession> {
  @override
  final int typeId = 2;

  @override
  ChatSession read(BinaryReader reader) {
    final numFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numFields; i++) reader.readByte(): reader.read(),
    };
    return ChatSession(
      id: fields[0] as String,
      title: fields[1] as String,
      presetId: fields[2] as String,
      createdAt: fields[3] as DateTime,
      updatedAt: fields[4] as DateTime?,
      summary: fields[5] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, ChatSession obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.presetId)
      ..writeByte(3)
      ..write(obj.createdAt)
      ..writeByte(4)
      ..write(obj.updatedAt)
      ..writeByte(5)
      ..write(obj.summary);
  }
}

/// Todo maddesi — Agent planini takip eder.
class TodoItem extends HiveObject {
  TodoItem({
    required this.id,
    required this.sessionId,
    required this.content,
    required this.status, // pending | in_progress | completed | cancelled
    this.priority = 'medium',
    required this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String sessionId;
  final String content;
  String status;
  String priority;
  final DateTime createdAt;
  DateTime? updatedAt;
}

class TodoItemAdapter extends TypeAdapter<TodoItem> {
  @override
  final int typeId = 3;

  @override
  TodoItem read(BinaryReader reader) {
    final numFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numFields; i++) reader.readByte(): reader.read(),
    };
    return TodoItem(
      id: fields[0] as String,
      sessionId: fields[1] as String,
      content: fields[2] as String,
      status: fields[3] as String,
      priority: fields[4] as String? ?? 'medium',
      createdAt: fields[5] as DateTime,
      updatedAt: fields[6] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, TodoItem obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.sessionId)
      ..writeByte(2)
      ..write(obj.content)
      ..writeByte(3)
      ..write(obj.status)
      ..writeByte(4)
      ..write(obj.priority)
      ..writeByte(5)
      ..write(obj.createdAt)
      ..writeByte(6)
      ..write(obj.updatedAt);
  }
}

/// Hive kutularının (box) açılması ve yönetimi.
///
/// Preset'ler HiveObject olmadığı, düz Dart sınıfı olduğu için
/// doğrudan `Map<String, dynamic>` (Preset.toJson) olarak saklanır;
/// bu sayede Preset sınıfı için ayrı bir TypeAdapter yazmaya gerek kalmaz.
class LocalDatabase {
  LocalDatabase._();

  static const String messagesBoxName = 'chat_messages';
  static const String sessionsBoxName = 'chat_sessions';
  static const String presetsBoxName = 'presets';
  static const String settingsBoxName = 'app_settings';
  static const String todosBoxName = 'todos';
  static const String pluginsBoxName = 'tool_plugins';

  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    await Hive.initFlutter();

    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(ChatMessageAdapter());
    }
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(ChatSessionAdapter());
    }
    if (!Hive.isAdapterRegistered(3)) {
      Hive.registerAdapter(TodoItemAdapter());
    }
    if (!Hive.isAdapterRegistered(4)) {
      Hive.registerAdapter(HttpToolPluginAdapter());
    }

    await Hive.openBox<ChatMessage>(messagesBoxName);
    await Hive.openBox<ChatSession>(sessionsBoxName);
    await Hive.openBox<Map>(presetsBoxName);
    await Hive.openBox(settingsBoxName);
    await Hive.openBox<TodoItem>(todosBoxName);
    await Hive.openBox<HttpToolPlugin>(pluginsBoxName);

    _initialized = true;
  }

  static Box<ChatMessage> get messagesBox =>
      Hive.box<ChatMessage>(messagesBoxName);

  static Box<ChatSession> get sessionsBox =>
      Hive.box<ChatSession>(sessionsBoxName);

  static Box<Map> get presetsBox => Hive.box<Map>(presetsBoxName);

  static Box get settingsBox => Hive.box(settingsBoxName);

  static Box<TodoItem> get todosBox => Hive.box<TodoItem>(todosBoxName);

  static Box<HttpToolPlugin> get pluginsBox => Hive.box<HttpToolPlugin>(pluginsBoxName);
}
