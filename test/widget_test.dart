// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:ff_chat/core/storage/local_database.dart';
import 'package:ff_chat/main.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ff_chat_test_');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(ChatMessageAdapter());
    }
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(ChatSessionAdapter());
    }
    await Hive.openBox<ChatMessage>(LocalDatabase.messagesBoxName);
    await Hive.openBox<ChatSession>(LocalDatabase.sessionsBoxName);
    await Hive.openBox<Map>(LocalDatabase.presetsBoxName);
    await Hive.openBox(LocalDatabase.settingsBoxName);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  testWidgets('App builds and shows navigation destinations', (
    WidgetTester tester,
  ) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const FfChatApp());
    await tester.pump(const Duration(seconds: 1));

    // Verify that the bottom navigation destinations are present.
    expect(find.text('Sohbet'), findsOneWidget);
    expect(find.text('Ayarlar'), findsOneWidget);
  });
}
