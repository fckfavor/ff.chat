import 'dart:io';

import 'package:path/path.dart' as p;

import 'sandbox_config.dart';

/// Gercek sandbox (proot/chroot) yoneticisi — V2 iskeleti.
///
/// MVP'de proot binary + rootfs henuz bundle degilse fallback olarak
/// WorkspaceFs path guard + blockedPatterns ile calisir.
/// Proot mevcutsa ShellExecutor onu kullanir.
class SandboxService {
  SandboxService._();
  static final SandboxService instance = SandboxService._();

  bool _checked = false;
  bool _prootAvailable = false;
  bool _rootfsAvailable = false;
  String? _prootPath;
  String? _rootfsPath;

  /// Proot + rootfs durumunu kontrol et (lazy, bir kez).
  Future<Map<String, dynamic>> checkStatus() async {
    if (_checked) {
      return {
        'prootAvailable': _prootAvailable,
        'rootfsAvailable': _rootfsAvailable,
        'prootPath': _prootPath,
        'rootfsPath': _rootfsPath,
        'isolated': _prootAvailable && _rootfsAvailable,
      };
    }
    _checked = true;
    try {
      final workspaceRoot = await SandboxConfig.getWorkspaceRoot();
      // Proot olasi konumlari: app files dir + workspace kardesi
      final candidates = [
        p.join(p.dirname(workspaceRoot), 'bin', 'proot'),
        p.join(workspaceRoot, '..', 'bin', 'proot'),
        p.join(workspaceRoot, 'bin', 'proot'),
        '/data/data/com.fckfavor.ff_chat/files/usr/bin/proot',
        '/system/bin/proot',
      ];
      for (final c in candidates) {
        final f = File(p.normalize(c));
        if (await f.exists()) {
          _prootPath = f.path;
          _prootAvailable = true;
          break;
        }
      }
      // Rootfs kontrol — Alpine imzasi (etc/alpine-release) veya bin/sh
      final rootfs = await SandboxConfig.getRootfsPath();
      _rootfsPath = rootfs;
      final alpineMarker = File(p.join(rootfs, 'etc', 'alpine-release'));
      final rootfsBin = File(p.join(rootfs, 'bin', 'sh'));
      final rootfsEtc = Directory(p.join(rootfs, 'etc'));
      if (await alpineMarker.exists() || await rootfsBin.exists() || await rootfsEtc.exists()) {
        _rootfsAvailable = true;
      }
    } catch (_) {
      // Hata yut, fallback modda kal
    }
    return {
      'prootAvailable': _prootAvailable,
      'rootfsAvailable': _rootfsAvailable,
      'prootPath': _prootPath,
      'rootfsPath': _rootfsPath,
      'isolated': _prootAvailable && _rootfsAvailable,
    };
  }

  bool get isIsolated => _prootAvailable && _rootfsAvailable;

  String get modeLabel {
    if (isIsolated) return 'Proot (izole)';
    if (_prootAvailable) return 'Proot (rootfs yok)';
    return 'Fallback (Workspace guard)';
  }

  /// Komutu proot ile sarmala, yoksa normal shell'e don
  /// Donus: {executable, args}
  Future<Map<String, dynamic>> wrapCommand(String command, String workdirAbs) async {
    await checkStatus();
    if (!isIsolated) {
      // Fallback: normal shell, workdir zaten SandboxConfig ile guard'li
      return {'executable': null, 'args': null, 'useProot': false};
    }
    // Proot ile: proot -r rootfs -b workspace:/workspace -w /workspace /bin/sh -c "command"
    final workspaceRoot = await SandboxConfig.getWorkspaceRoot();
    final proot = _prootPath!;
    final rootfs = _rootfsPath!;
    // Workspace'i /workspace'e bind et, workdir'i /workspace altina cevir
    String prootWorkdir = '/workspace';
    if (workdirAbs != workspaceRoot) {
      final rel = p.relative(workdirAbs, from: workspaceRoot);
      prootWorkdir = p.join('/workspace', rel);
    }
    return {
      'executable': proot,
      'args': [
        '-r',
        rootfs,
        '-b',
        '$workspaceRoot:/workspace',
        '-w',
        prootWorkdir,
        '/bin/sh',
        '-c',
        command,
      ],
      'useProot': true,
    };
  }

  /// Durum ozeti (Ayarlar UI icin)
  Future<String> statusText() async {
    final s = await checkStatus();
    if (s['isolated'] == true) return 'Izole (proot + rootfs aktif)';
    if (s['prootAvailable'] == true) return 'Proot var ama rootfs yok — fallback mod';
    return 'Fallback mod (path guard + blocklist) — V2 icin proot bundle gerekli';
  }

  /// Cache'i temizle (test veya rootfs yuklendikten sonra)
  void reset() {
    _checked = false;
    _prootAvailable = false;
    _rootfsAvailable = false;
    _prootPath = null;
    _rootfsPath = null;
  }
}
