import 'dart:io';

import '../workspace/sandbox_config.dart';

/// Hook servisi — her tool cagrisindan once/sonra calisan kancalar.
///
/// MVP'de sadece file_write/file_edit sonrasi `dart format` hook'u var.
/// Ileride lint, test vb genisletilebilir.
/// Profesyonel dev tool kalitesi: injection kapali, permission bypass yok.
class HookService {
  HookService._();
  static final HookService instance = HookService._();

  bool _enabled = true;

  bool get enabled => _enabled;
  set enabled(bool v) => _enabled = v;

  /// Dosya yazildiktan sonra hook calistir (or: dart format)
  /// Hata yutulur — hook basarisiz olsa bile ana tool basarili sayilir.
  /// Guvenlik: path SandboxConfig.resolve ile workspace'e kilitlenir,
  /// Process.run args listesi ile shell interpolasyonu devre disi (injection imkansiz).
  Future<void> onPostTool(String toolName, Map<String, dynamic> args) async {
    if (!_enabled) return;
    if (toolName != 'file_write' && toolName != 'file_edit') return;
    final path = args['path']?.toString() ?? '';
    if (!path.endsWith('.dart')) return;

    // Workspace icine cozumle — traversal engellenir, ayrica hook file_write'in
    // kendi onayindan gecmis path'i kullanir (ayri dialog acmaz, izin disiplini korunur)
    String absolutePath;
    try {
      absolutePath = await SandboxConfig.resolve(path);
    } catch (_) {
      return;
    }

    try {
      final result = await Process.run(
        'dart',
        ['format', absolutePath],
        workingDirectory: await SandboxConfig.getWorkspaceRoot(),
      ).timeout(const Duration(seconds: 5));
      if (result.exitCode != 0) {
        // no-op, hook hatasi ana akisi bozmaz (dart yoksa veya format hatasi)
      }
    } catch (_) {
      // dart yoksa, timeout, veya baska hata — yut
    }
  }

  /// Tool oncesi hook (ileride lint pre-check icin)
  Future<bool> onPreTool(String toolName, Map<String, dynamic> args) async {
    // Su an pre hook yok, her zaman devam et
    return true;
  }
}
