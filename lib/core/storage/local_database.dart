import 'package:hive_flutter/hive_flutter.dart';

import '../models/preset.dart';

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
  });

  final String id;
  final String title;
  final String presetId;
  final DateTime createdAt;
  DateTime? updatedAt;
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
    );
  }

  @override
  void write(BinaryWriter writer, ChatSession obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.presetId)
      ..writeByte(3)
      ..write(obj.createdAt)
      ..writeByte(4)
      ..write(obj.updatedAt);
  }
}

/// Hive kutularının (box) açılması ve yönetimi.
///
/// Preset'ler HiveObject olmadığı, düz Dart sınıfı olduğu için
/// doğrudan Map<String, dynamic> (Preset.toJson) olarak saklanır;
/// bu sayede Preset sınıfı için ayrı bir TypeAdapter yazmaya gerek kalmaz.
class LocalDatabase {
  LocalDatabase._();

  static const String messagesBoxName = 'chat_messages';
  static const String sessionsBoxName = 'chat_sessions';
  static const String presetsBoxName = 'presets';

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

    await Hive.openBox<ChatMessage>(messagesBoxName);
    await Hive.openBox<ChatSession>(sessionsBoxName);
    await Hive.openBox<Map>(presetsBoxName);

    _initialized = true;
  }

  static Box<ChatMessage> get messagesBox =>
      Hive.box<ChatMessage>(messagesBoxName);

  static Box<ChatSession> get sessionsBox =>
      Hive.box<ChatSession>(sessionsBoxName);

  static Box<Map> get presetsBox => Hive.box<Map>(presetsBoxName);
}
