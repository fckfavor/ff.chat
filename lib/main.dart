import 'package:flutter/material.dart';

import 'core/monetization/ad_service.dart';
import 'core/monetization/feature_gate.dart';
import 'core/monetization/update_check_service.dart';
import 'core/storage/local_database.dart';
import 'features/chat/chat_screen.dart';
import 'features/settings/settings_screen.dart';

/// Uygulamanın mevcut sürümü (pubspec.yaml ile senkron tutulmalı).
const String _appVersion = '1.0.0';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LocalDatabase.init();

  await FeatureGateService.instance.refresh();

  final updateStatus = await UpdateCheckService().checkForUpdate(_appVersion);

  final adService = NoOpAdService();
  await adService.init();

  runApp(FfChatApp(updateStatus: updateStatus));
}

class FfChatApp extends StatelessWidget {
  const FfChatApp({super.key, this.updateStatus = UpdateStatus.none});

  final UpdateStatus updateStatus;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ff.chat',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.light,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.dark,
        ),
      ),
      home: updateStatus == UpdateStatus.force
          ? const ForceUpdateScreen()
          : RootScreen(showSoftUpdateBanner: updateStatus == UpdateStatus.soft),
    );
  }
}

/// Zorunlu güncelleme gerektiğinde gösterilen, kapatılamayan ekran.
class ForceUpdateScreen extends StatelessWidget {
  const ForceUpdateScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.system_update, size: 48),
                const SizedBox(height: 16),
                const Text(
                  'Güncelleme Gerekli',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Uygulamayı kullanmaya devam edebilmek için lütfen '
                  'en güncel sürüme geçin.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Sohbet ve Ayarlar ekranları arasında geçişi sağlayan basit
/// bottom navigation iskeleti.
class RootScreen extends StatefulWidget {
  const RootScreen({super.key, this.showSoftUpdateBanner = false});

  final bool showSoftUpdateBanner;

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  int _selectedIndex = 0;
  late bool _showSoftUpdateBanner = widget.showSoftUpdateBanner;

  static const _screens = [ChatScreen(), SettingsScreen()];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          if (_showSoftUpdateBanner)
            MaterialBanner(
              content: const Text('Yeni bir sürüm mevcut.'),
              actions: [
                TextButton(
                  onPressed: () => setState(() => _showSoftUpdateBanner = false),
                  child: const Text('Kapat'),
                ),
              ],
            ),
          Expanded(
            child: IndexedStack(index: _selectedIndex, children: _screens),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) =>
            setState(() => _selectedIndex = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.chat_bubble_outline), label: 'Sohbet'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'Ayarlar'),
        ],
      ),
    );
  }
}
