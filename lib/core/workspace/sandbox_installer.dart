import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'sandbox_config.dart';
import 'sandbox_service.dart';

/// V2 Sandbox kurulumu — proot (static) + Alpine minirootfs indirip
/// app dosya alanina kurar. Kurulumdan sonra ShellExecutor otomatik proot kullanir.
///
/// NOT: Android 10+ (API 29) uygulama veri dizininden exec'i engeller.
/// Bu yuzden uygulama targetSdk=28 ile derlenir (Termux'un yaptigi gibi).
class SandboxInstaller {
  SandboxInstaller._();
  static final SandboxInstaller instance = SandboxInstaller._();

  static const _prootVersion = 'v5.1.0';
  static const _alpineVersion = '3.20.3';

  bool _isArm64() {
    final v = Platform.version.toLowerCase();
    return v.contains('aarch64') || v.contains('arm64');
  }

  String get _abi => _isArm64() ? 'aarch64' : 'x86_64';

  Uri get _prootUrl => Uri.parse(
      'https://github.com/proot-me/proot-static-build/releases/download/$_prootVersion/proot-$_prootVersion-$_abi-static');

  Uri get _rootfsUrl => Uri.parse(
      'https://dl-cdn.alpinelinux.org/alpine/v$_alpineVersion/releases/$_abi/alpine-minirootfs-$_alpineVersion-$_abi.tar.gz');

  Future<Directory> _filesDir() async {
    final workspaceRoot = await SandboxConfig.getWorkspaceRoot();
    // workspaceRoot = <documents>/workspace -> parent = <documents>
    return Directory(p.dirname(workspaceRoot));
  }

  Future<String> _prootPath() async {
    final files = await _filesDir();
    return p.join(files.path, 'bin', 'proot');
  }

  /// Indirme + kurulum. [onProgress]: 0.0..1.0 ve durum etiketi.
  Future<void> install({void Function(double progress, String label)? onProgress}) async {
    void report(double p, String label) => onProgress?.call(p.clamp(0.0, 1.0), label);

    final files = await _filesDir();
    final binDir = Directory(p.join(files.path, 'bin'));
    await binDir.create(recursive: true);
    final rootfsPath = await SandboxConfig.getRootfsPath();
    await Directory(rootfsPath).create(recursive: true);
    final tmpDir = Directory(p.join(files.path, 'tmp_install'));
    await tmpDir.create(recursive: true);

    try {
      // ---- 1) proot ----
      final prootPath = await _prootPath();
      if (!File(prootPath).existsSync()) {
        report(0.05, 'proot indiriliyor ($_abi)...');
        final prootBytes = await _download(_prootUrl, (received, total) {
          final frac = total > 0 ? received / total : 0.0;
          report(0.05 + frac * 0.25, 'proot indiriliyor (${_fmtMB(received)}/${total > 0 ? _fmtMB(total) : "?"})...');
        });
        final f = File(prootPath);
        await f.writeAsBytes(prootBytes, flush: true);
        await _chmodExec(prootPath);
        report(0.30, 'proot kuruldu');
      } else {
        report(0.30, 'proot zaten mevcut');
      }

      // ---- 2) Alpine rootfs ----
      final marker = File(p.join(rootfsPath, 'etc', 'alpine-release'));
      if (!marker.existsSync()) {
        report(0.35, 'Alpine minirootfs indiriliyor...');
        final tgzPath = p.join(tmpDir.path, 'minirootfs.tar.gz');
        await _downloadToFile(_rootfsUrl, File(tgzPath), (received, total) {
          final frac = total > 0 ? received / total : 0.0;
          report(0.35 + frac * 0.45, 'Alpine indiriliyor (${_fmtMB(received)}/${total > 0 ? _fmtMB(total) : "?"})...');
        });

        report(0.80, 'rootfs aciliyor...');
        final gzipped = await File(tgzPath).readAsBytes();
        final tarBytes = Uint8List.fromList(GZipDecoder().decodeBytes(gzipped));
        final archive = TarDecoder().decodeBytes(tarBytes);

        var count = 0;
        for (final entry in archive) {
          final name = entry.name;
          // Guvenlik: path escape engelle
          if (name.startsWith('/') || name.contains('..')) continue;
          final outPath = p.join(rootfsPath, name);
          if (entry.isFile) {
            final outFile = File(outPath);
            await outFile.parent.create(recursive: true);
            await outFile.writeAsBytes(entry.content as List<int>, flush: true);
            // Exec bitini koru (busybox vb.)
            final execBit = entry.mode & 73; // 0o111
            if (execBit != 0) {
              await _chmodExec(outPath);
            }
          } else {
            await Directory(outPath).create(recursive: true);
          }
          count++;
          if (count % 400 == 0) {
            report(0.80 + (count / 2000) * 0.15, 'rootfs aciliyor ($count dosya)...');
          }
        }
        report(0.95, 'rootfs hazir ($count dosya)');
        try {
          await File(tgzPath).delete();
        } catch (_) {}
      } else {
        report(0.95, 'Alpine zaten kurulu');
      }

      // ---- 3) DNS + apk repos ayarlari ----
      try {
        await File(p.join(rootfsPath, 'etc', 'resolv.conf')).writeAsString(
          'nameserver 8.8.8.8\nnameserver 1.1.1.1\n',
          flush: true,
        );
      } catch (_) {}

      // ---- 4) dogrulama ----
      SandboxService.instance.reset();
      final status = await SandboxService.instance.checkStatus();
      if (status['isolated'] != true) {
        throw Exception('Kurulum tamamlandi ama izolasyon dogrulanamadi — tekrar dene');
      }
      report(1.0, 'SANDBOX HAZIR — izole mod aktif');
    } finally {
      try {
        await tmpDir.delete(recursive: true);
      } catch (_) {}
    }
  }

  Future<void> uninstall() async {
    final rootfsPath = await SandboxConfig.getRootfsPath();
    final prootPath = await _prootPath();
    if (Directory(rootfsPath).existsSync()) {
      await Directory(rootfsPath).delete(recursive: true);
    }
    final pf = File(prootPath);
    if (pf.existsSync()) await pf.delete();
    SandboxService.instance.reset();
  }

  Future<Uint8List> _download(Uri url, void Function(int received, int total)? onChunk) async {
    final client = http.Client();
    try {
      final streamed = await client.send(http.Request('GET', url));
      if (streamed.statusCode != 200) {
        throw Exception('Indirme hatasi HTTP ${streamed.statusCode}: $url');
      }
      final total = streamed.contentLength ?? 0;
      final builder = BytesBuilder(copy: false);
      var received = 0;
      await for (final chunk in streamed.stream) {
        builder.add(chunk);
        received += chunk.length;
        onChunk?.call(received, total);
      }
      return builder.takeBytes();
    } finally {
      client.close();
    }
  }

  Future<void> _downloadToFile(Uri url, File file, void Function(int received, int total)? onChunk) async {
    final bytes = await _download(url, onChunk);
    await file.writeAsBytes(bytes, flush: true);
  }

  Future<void> _chmodExec(String path) async {
    try {
      await Process.run('/system/bin/chmod', ['755', path]);
    } catch (_) {
      // Windows/test ortaminda chmod yok — sessiz gec
    }
  }

  String _fmtMB(int bytes) => '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
}
