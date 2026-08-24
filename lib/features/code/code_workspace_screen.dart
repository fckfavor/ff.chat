import 'package:flutter/material.dart';

import '../files/file_explorer_screen.dart';
import '../settings/settings_screen.dart';
import '../terminal/terminal_screen.dart';

/// Code workspace — Files + Terminal'i tek ekranda birlestiren sarmalayici.
/// Claude Desktop hissi icin: alt nav 2'ye indi, Code sekmesi icinde TabBar.
class CodeWorkspaceScreen extends StatefulWidget {
  const CodeWorkspaceScreen({super.key});

  @override
  State<CodeWorkspaceScreen> createState() => _CodeWorkspaceScreenState();
}

class _CodeWorkspaceScreenState extends State<CodeWorkspaceScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Code'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Ayarlar',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.folder_outlined), text: 'Dosyalar'),
            Tab(icon: Icon(Icons.terminal), text: 'Terminal'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          FileExplorerScreen(embedded: true),
          TerminalScreen(embedded: true),
        ],
      ),
      // FAB sadece Dosyalar tab'inda goster (Terminal'de terminal kendi input'u var)
      floatingActionButton: _tabController.index == 0
          ? FloatingActionButton(
              onPressed: () {
                // FileExplorerScreen'in FAB aksiyonunu tetiklemek icin
                // embedded modda FAB disarida oldugundan, bir event gondermek yerine
                // kullaniciya bilgi goster — ya da FileExplorerScreen'e callback ile bagla
                // Simdilik: Dosyalar tab'inda FAB'a basinca FileExplorer'in kendi create dialog'unu acmak icin
                // FileExplorerScreen(embedded:true) icinde FAB yok, bu FAB tiklandiginda
                // bir global key ile tetiklenebilir. MVP'de sadece bilgi:
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Dosya olusturmak icin Dosyalar tab\'inda sag alttaki + kullanilir — Terminal\'den de mkdir ile olusturabilirsin')),
                );
              },
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}
