// Geçici tanı (repro) testi: kullanıcı Ayarlar'dan bir preset seçmesine
// rağmen Sohbet ekranının hâlâ "Lütfen önce Ayarlar ekranından bir preset
// seçin." hatası verdiği şikayetini uçtan uca kanıtlamak/çürütmek için.
//
// SİLİNMESİN: Bir sonraki fazda kök neden düzeltmesinin regresyon testi
// olarak kullanılacak.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:ff_chat/core/storage/local_database.dart';
import 'package:ff_chat/core/storage/app_settings_repository.dart';
import 'package:ff_chat/main.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ff_chat_repro_');
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

    // flutter_secure_storage platform kanalını sahte (in-memory) olarak
    // yanıtlayarak testin gerçek cihaz/keychain'e ihtiyaç duymadan
    // çalışmasını sağlıyoruz.
    final store = <String, String>{};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (MethodCall call) async {
        switch (call.method) {
          case 'read':
            return store[call.arguments['key']];
          case 'write':
            store[call.arguments['key']] = call.arguments['value'];
            return null;
          case 'delete':
            store.remove(call.arguments['key']);
            return null;
          case 'readAll':
            return store;
          case 'deleteAll':
            store.clear();
            return null;
          case 'containsKey':
            return store.containsKey(call.arguments['key']);
          default:
            return null;
        }
      },
    );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      null,
    );
    // Not: Hive.deleteFromDisk() / box.close() / box.clear() gibi Hive
    // kutularına dokunan HERHANGİ bir işlem, bu kutularda bekleyen bir disk
    // flush yazması varsa (bu testte varsayılan preset kalıcı hale
    // getirilirken oluşan yazma gibi) Windows'taki flutter_tester ortamında
    // aynı kutunun yazma kuyruğunda sıraya girip süresiz asılı kalabiliyor
    // (bkz. "Fix: widget_test.dart Windows flutter_tester" commit'i). Bu
    // yüzden burada kutulara kasıtlı olarak dokunmuyoruz; bu test dosyası
    // kendi izole VM isolate'inde çalıştığından süreç normal şekilde
    // sonlanınca geçici dizin de işletim sistemi tarafından temizlenir.
  });

  testWidgets(
      'Ayarlar ekranı ilk açıldığında varsayılan preset HİÇBİR dropdown '
      'etkileşimi olmadan kalıcı hale getirilmeli, aksi halde Sohbet '
      'ekranı hep "preset seçin" hatası verir.', (WidgetTester tester) async {
    await tester.pumpWidget(const FfChatApp());
    await tester.pumpAndSettle();

    // 1) Ayarlar ekranina gec — NavigationBar'daki settings ikonu
    final navBar = find.descendant(
      of: find.byType(NavigationBar),
      matching: find.byIcon(Icons.settings_outlined),
    );
    expect(navBar, findsOneWidget);
    await tester.tap(navBar);
    await tester.pumpAndSettle();

    // Dropdown'da bir preset zaten seçili görünüyor mu? (ilk preset varsayılan
    // olarak _selectedPresetId'ye düşüyor)
    expect(find.byType(DropdownButtonFormField<String>), findsWidgets);

    // KANIT: kullanıcı hiçbir şeye dokunmadan (dropdown zaten dolu
    // görünüyor), kalıcı depoda preset id var mı olmalı mı?
    final repo = AppSettingsRepository();
    final persistedBeforeAnyInteraction = repo.getPresetId();
    // ignore: avoid_print
    print(
        'REPRO: Ayarlar ekranı açıldı, kullanıcı dokunmadan önce kalıcı '
        'presetId = $persistedBeforeAnyInteraction');

    expect(
      persistedBeforeAnyInteraction,
      isNotNull,
      reason: 'Ayarlar ekranı ilk açıldığında (kullanıcı dropdown\'a hiç '
          'dokunmasa bile) varsayılan/kayıtlı preset _loadSettings içinde '
          'hemen setPresetId ile kalıcı hale getirilmelidir. Aksi halde '
          'ChatScreen._settingsRepo.getPresetId() null döner ve kullanıcı '
          'dropdown\'da bir preset seçili görse dahi "Lütfen önce Ayarlar '
          'ekranından bir preset seçin." hatası alır.',
    );

    // Base URL ve model adını doldur (preset dışı zorunlu alanlar).
    await tester.enterText(
      find.widgetWithText(TextField, '').first,
      'https://api.example.com/v1/chat/completions',
    );
    await tester.pumpAndSettle();

    // 2) Kullanıcı dropdown'a HİÇ dokunmadan doğrudan Sohbet sekmesine geçer
    await tester.tap(find.descendant(
      of: find.byType(NavigationBar),
      matching: find.byIcon(Icons.chat_bubble_outline),
    ));
    await tester.pumpAndSettle();

    // 3) Mesaj yaz ve gönder.
    await tester.enterText(find.byType(TextField).first, 'merhaba');
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.send));
    // SnackBar'ın görünmesi için birkaç frame bekle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final errorFound = find
        .text('Lütfen önce Ayarlar ekranından bir preset seçin.')
        .evaluate()
        .isNotEmpty;
    // ignore: avoid_print
    print('REPRO: Sohbet ekranında "preset seçin" hatası görüldü mü? '
        '$errorFound');

    expect(
      errorFound,
      isFalse,
      reason: 'Ayarlar ekranı açılıp kapandığında varsayılan preset kalıcı '
          'hale getirildiği için Sohbet ekranı "preset seçin" hatası '
          'vermemeli.',
    );
  });
}
