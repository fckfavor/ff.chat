import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Sandbox'un fiziksel konumlari ve izolasyon kurallari.
///
/// MVP'de [workspaceRoot] = app documents/workspace
/// V2'de [rootfsPath] icine alpine miniroot extract edilip proot ile chroot yapilacak.
class SandboxConfig {
  SandboxConfig._();

  static String? _cachedWorkspaceRoot;
  static String? _cachedRootfsPath;

  static bool _isTestBinding() {
    try {
      final type = WidgetsBinding.instance.runtimeType.toString();
      return type.contains('Test');
    } catch (_) {
      return false;
    }
  }

  /// Workspace kok dizini — tum kullanici dosyalari burada.
  /// Ornek Android: /data/data/com.fckfavor.ff_chat/app_flutter/workspace
  static Future<String> getWorkspaceRoot() async {
    if (_cachedWorkspaceRoot != null) return _cachedWorkspaceRoot!;
    // Test ortaminda path_provider platform kanali yok — aninda fallback
    if (_isTestBinding()) {
      final fallback = p.join(Directory.systemTemp.path, 'ff_chat_workspace');
      try {
        await Directory(fallback).create(recursive: true);
      } catch (_) {}
      _cachedWorkspaceRoot = fallback;
      return fallback;
    }
    try {
      final dir = await getApplicationDocumentsDirectory()
          .timeout(const Duration(seconds: 1), onTimeout: () => throw TimeoutException('path_provider timeout'));
      final path = p.join(dir.path, 'workspace');
      await Directory(path).create(recursive: true);
      _cachedWorkspaceRoot = path;
      return path;
    } catch (_) {
      // Test ortami veya platform kanali yoksa fallback: systemTemp
      final fallback = p.join(Directory.systemTemp.path, 'ff_chat_workspace');
      try {
        await Directory(fallback).create(recursive: true);
      } catch (_) {}
      _cachedWorkspaceRoot = fallback;
      return fallback;
    }
  }

  /// Senkron versiyon (init sonrasi). Init cagrilmadan kullanma.
  static String get workspaceRootSync {
    if (_cachedWorkspaceRoot != null) return _cachedWorkspaceRoot!;
    // Test ortaminda init cagrilmadan erisilirse fallback
    final fallback = p.join(Directory.systemTemp.path, 'ff_chat_workspace');
    _cachedWorkspaceRoot = fallback;
    // Olusturmayi dene ama hata yut
    try {
      Directory(fallback).createSync(recursive: true);
    } catch (_) {}
    return fallback;
  }

  /// Proot rootfs yolu (V2). Simdilik workspace'in kardesi.
  static Future<String> getRootfsPath() async {
    if (_cachedRootfsPath != null) return _cachedRootfsPath!;
    if (_isTestBinding()) {
      final fallback = p.join(Directory.systemTemp.path, 'ff_chat_rootfs');
      _cachedRootfsPath = fallback;
      return fallback;
    }
    try {
      final dir = await getApplicationDocumentsDirectory()
          .timeout(const Duration(seconds: 1), onTimeout: () => throw TimeoutException('path_provider timeout'));
      final path = p.join(dir.path, 'rootfs');
      _cachedRootfsPath = path;
      return path;
    } catch (_) {
      final fallback = p.join(Directory.systemTemp.path, 'ff_chat_rootfs');
      _cachedRootfsPath = fallback;
      return fallback;
    }
  }

  /// Workspace'i init et (main() icinde cagrilmali).
  static Future<void> init() async {
    await getWorkspaceRoot();
    await getRootfsPath();
  }

  /// Verilen relative path'i sanitize edip workspace icinde mutlak yola cozer.
  /// Path traversal (../../etc/passwd) engellenir.
  static Future<String> resolve(String relativePath) async {
    final root = await getWorkspaceRoot();
    return _resolveSync(root, relativePath);
  }

  static String _resolveSync(String root, String relativePath) {
    // Basit normalizasyon: bos, / ile baslayan, .. icerenleri temizle.
    var cleaned = relativePath.trim();
    // Mutlak path verildiyse workspace'e gore relative yap.
    if (p.isAbsolute(cleaned)) {
      cleaned = p.relative(cleaned, from: '/');
    }
    // Nokta ve bos segmentleri kaldir
    cleaned = p.normalize(cleaned);
    // p.normalize ".." birakabilir, onlari elle filtrele
    final parts = p.split(cleaned).where((s) => s != '.' && s.isNotEmpty).toList();
    final filtered = <String>[];
    for (final part in parts) {
      if (part == '..') {
        if (filtered.isNotEmpty) filtered.removeLast();
        // root disina cikma girisimi sessizce yutulur (sandbox)
        continue;
      }
      // Tehlikeli karakterleri reddet: null byte, vs
      if (part.contains('\u0000')) continue;
      filtered.add(part);
    }
    final relative = p.joinAll(filtered);
    final absolute = p.join(root, relative);
    final normalized = p.normalize(absolute);
    // Son guard: normalized hala root icinde mi?
    if (!p.isWithin(root, normalized) && normalized != root) {
      // Disari cikmaya calisti, root'a kilitle
      return root;
    }
    return normalized;
  }

  /// Sync resolve (cached root varsa).
  static String resolveSync(String relativePath) {
    return _resolveSync(workspaceRootSync, relativePath);
  }

  /// Calistirilmasina izin verilmeyen tehlikeli komut pattern'leri.
  /// Agent'in `rm -rf /` gibi seyleri direkt calistirmasini engellemek icin
  /// on-filters; son karar ShellExecutor'da.
  static const List<String> blockedPatterns = [
    r'rm\s+-rf\s+/$',
    r'rm\s+-rf\s+/\*',
    r':\(\)\s*\{\s*:\s*\|\s*:\s*&\s*;\s*\}', // fork bomb
    r'mkfs\.',
    r'dd\s+.*of=/dev/',
  ];

  static bool isBlocked(String command) {
    for (final pattern in blockedPatterns) {
      if (RegExp(pattern).hasMatch(command)) return true;
    }
    return false;
  }
}
