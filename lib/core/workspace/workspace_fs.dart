import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'sandbox_config.dart';

/// Dosya sistemi girdisi — FileExplorer icin.
class FsEntry {
  FsEntry({
    required this.name,
    required this.relativePath,
    required this.absolutePath,
    required this.isDirectory,
    this.size,
    this.modified,
  });

  final String name;
  final String relativePath;
  final String absolutePath;
  final bool isDirectory;
  final int? size;
  final DateTime? modified;

  bool get isFile => !isDirectory;
}

/// Grep sonucu tek bir eslesme.
class GrepMatch {
  GrepMatch({
    required this.file,
    required this.line,
    required this.column,
    required this.preview,
  });

  final String file;
  final int line;
  final int column;
  final String preview;

  @override
  String toString() => '$file:$line:$column: $preview';
}

/// Workspace dosya sistemi — tum islemler sandbox icinde.
///
/// Tum path'ler workspace'e gore relative verilir: "project/main.dart" gibi.
/// Mutlak path verilirse otomatik relative'e cevrilir ve sandbox icine kilitlenir.
class WorkspaceFs {
  WorkspaceFs._();

  static final WorkspaceFs instance = WorkspaceFs._();

  Future<String> _resolve(String path) => SandboxConfig.resolve(path);

  String _toRelative(String absolute) {
    try {
      final root = SandboxConfig.workspaceRootSync;
      if (absolute == root) return '.';
      return p.relative(absolute, from: root);
    } catch (_) {
      return absolute;
    }
  }

  /// Workspace kokunu dondurur.
  Future<String> getRoot() => SandboxConfig.getWorkspaceRoot();

  /// Dosya/dizin var mi?
  Future<bool> exists(String path) async {
    final abs = await _resolve(path);
    return File(abs).existsSync() || Directory(abs).existsSync();
  }

  /// Dizin listele. `path` bos veya "." ise kok listelenir.
  Future<List<FsEntry>> list(String path) async {
    final abs = await _resolve(path);
    final dir = Directory(abs);
    if (!await dir.exists()) return [];
    final entities = await dir.list(followLinks: false).toList();
    final result = <FsEntry>[];
    for (final e in entities) {
      final stat = await e.stat();
      final isDir = stat.type == FileSystemEntityType.directory;
      final name = p.basename(e.path);
      result.add(FsEntry(
        name: name,
        absolutePath: e.path,
        relativePath: _toRelative(e.path),
        isDirectory: isDir,
        size: isDir ? null : stat.size,
        modified: stat.modified,
      ));
    }
    // Dizinler once, sonra alfabetik
    result.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return result;
  }

  /// Dosya oku (text). Binary dosyalar icin readBytes kullan.
  Future<String> readFile(String path) async {
    final abs = await _resolve(path);
    final file = File(abs);
    if (!await file.exists()) {
      throw FileSystemException('Dosya bulunamadi', abs);
    }
    // 10MB limit — buyuk dosyayi tek seferde bellege alma
    final stat = await file.stat();
    if (stat.size > 10 * 1024 * 1024) {
      throw FileSystemException('Dosya cok buyuk (10MB limit)', abs);
    }
    return file.readAsString();
  }

  Future<Uint8List> readBytes(String path) async {
    final abs = await _resolve(path);
    final file = File(abs);
    if (!await file.exists()) throw FileSystemException('Dosya bulunamadi', abs);
    return file.readAsBytes();
  }

  /// Dosya yaz (yoksa olustur, varsa uzerine yaz). Gerekirse parent dizinleri olusturur.
  Future<void> writeFile(String path, String content) async {
    final abs = await _resolve(path);
    final file = File(abs);
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
  }

  Future<void> writeBytes(String path, Uint8List bytes) async {
    final abs = await _resolve(path);
    final file = File(abs);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
  }

  /// Var olan dosyada unique substring degistir (Claude Code file_edit mantigi).
  /// oldString dosyada tam olarak 1 kez gecmeli, 0 veya >1 ise hata firlatir.
  /// Basarili olursa diff preview string'i dondurur.
  Future<String> editFile(String path, String oldString, String newString) async {
    final abs = await _resolve(path);
    final file = File(abs);
    if (!await file.exists()) {
      throw FileSystemException('Dosya bulunamadi - edit icin once file_write ile olustur', abs);
    }
    final stat = await file.stat();
    if (stat.size > 10 * 1024 * 1024) {
      throw FileSystemException('Dosya cok buyuk (10MB limit)', abs);
    }
    if (oldString.isEmpty) {
      throw FileSystemException('old_string bos olamaz (unique match gerekli)', abs);
    }
    if (oldString == newString) {
      throw FileSystemException('old_string ve new_string ayni - degisiklik yok', abs);
    }
    final content = await file.readAsString();
    final count = _countOccurrences(content, oldString);
    if (count == 0) {
      throw FileSystemException('old_string bulunamadi (0 match). Dosya degismedi.', abs);
    }
    if (count > 1) {
      throw FileSystemException('old_string $count kez bulundu, unique olmali. Daha genis context ver (or: 2-3 satir ile).', abs);
    }
    final newContent = content.replaceFirst(oldString, newString);
    await file.writeAsString(newContent);
    return _generateDiff(path, content, newContent, oldString, newString);
  }

  /// Yazmadan sadece diff uret (izin preview icin).
  Future<String> editFileDryRun(String path, String oldString, String newString) async {
    final abs = await _resolve(path);
    final file = File(abs);
    if (!await file.exists()) return '[dry-run] dosya yok: $path';
    if (oldString.isEmpty) return '[dry-run] old_string bos';
    try {
      final content = await file.readAsString();
      final count = _countOccurrences(content, oldString);
      if (count == 0) return '[dry-run] old_string bulunamadi (0 match)';
      if (count > 1) return '[dry-run] old_string $count kez bulundu, unique degil';
      final newContent = content.replaceFirst(oldString, newString);
      return _generateDiff(path, content, newContent, oldString, newString);
    } catch (e) {
      return '[dry-run] hata: $e';
    }
  }

  int _countOccurrences(String content, String pattern) {
    if (pattern.isEmpty) return 0;
    int count = 0;
    int index = 0;
    while (true) {
      index = content.indexOf(pattern, index);
      if (index == -1) break;
      count++;
      index += pattern.length;
      if (count > 2) break; // 2'yi gecince unique degil zaten
    }
    return count;
  }

  String _generateDiff(String path, String oldContent, String newContent, String oldString, String newString) {
    // Satir numaralarini bul
    final oldIndex = oldContent.indexOf(oldString);
    final startLine = oldIndex == -1 ? 1 : oldContent.substring(0, oldIndex).split('\n').length;
    final oldLines = oldString.split('\n').length;
    final newLines = newString.split('\n').length;
    final sb = StringBuffer();
    sb.writeln('--- $path');
    sb.writeln('+++ $path');
    sb.writeln('@@ -$startLine,$oldLines +$startLine,$newLines @@');
    // Kisalt
    String truncatedOld = oldString.length > 500 ? '${oldString.substring(0, 500)}...[truncated]' : oldString;
    String truncatedNew = newString.length > 500 ? '${newString.substring(0, 500)}...[truncated]' : newString;
    for (final line in truncatedOld.split('\n')) {
      sb.writeln('- $line');
    }
    for (final line in truncatedNew.split('\n')) {
      sb.writeln('+ $line');
    }
    return sb.toString();
  }

  /// Glob pattern ile dosya ara (native, shell gerektirmez).
  /// Or: "**/*.dart", "lib/*.dart", "*.md"
  Future<List<FsEntry>> glob(String pattern, {String rootPath = '.'}) async {
    if (pattern.trim().isEmpty) return [];
    final absRoot = await _resolve(rootPath);
    final rootDir = Directory(absRoot);
    if (!await rootDir.exists()) return [];
    final regex = _globToRegExp(pattern);
    final results = <FsEntry>[];
    const skipDirs = {'.git', '.dart_tool', 'build', '.idea', 'node_modules', '__pycache__'};
    await for (final entity in rootDir.list(recursive: true, followLinks: false)) {
      if (results.length >= 1000) break;
      // Skip istenmeyen dizinler
      final rel = _toRelative(entity.path);
      final parts = rel.split('/');
      if (parts.any((p) => skipDirs.contains(p))) continue;
      // Sadece dosyalar (glob genelde dosya arar), ama dizin de match ederse ekle
      final stat = await entity.stat();
      final isDir = stat.type == FileSystemEntityType.directory;
      // relativePath posix normalize ile match et
      final posixRel = rel.replaceAll('\\', '/');
      if (regex.hasMatch(posixRel) || regex.hasMatch(p.basename(entity.path))) {
        results.add(FsEntry(
          name: p.basename(entity.path),
          absolutePath: entity.path,
          relativePath: rel,
          isDirectory: isDir,
          size: isDir ? null : stat.size,
          modified: stat.modified,
        ));
      }
    }
    results.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      return a.relativePath.toLowerCase().compareTo(b.relativePath.toLowerCase());
    });
    return results;
  }

  RegExp _globToRegExp(String glob) {
    // Gecici placeholderlar
    var pattern = glob.trim().replaceAll('\\', '/');
    pattern = pattern.replaceAll('.', r'\.');
    pattern = pattern.replaceAll('**/', '___DOUBLESTAR_SLASH___');
    pattern = pattern.replaceAll('**', '___DOUBLESTAR___');
    pattern = pattern.replaceAll('*', '[^/]*');
    pattern = pattern.replaceAll('?', '[^/]');
    pattern = pattern.replaceAll('___DOUBLESTAR_SLASH___', '(.*/)?');
    pattern = pattern.replaceAll('___DOUBLESTAR___', '.*');
    // Parantez vs escape
    pattern = pattern.replaceAll('{', '(?:').replaceAll('}', ')').replaceAll(',', '|');
    return RegExp('^$pattern\$');
  }

  /// Icerik ara (native grep, shell gerektirmez).
  /// pattern regex veya plain string, optional glob ile dosya filtresi.
  Future<List<GrepMatch>> grep(
    String pattern, {
    String path = '.',
    String? glob,
    bool caseSensitive = true,
  }) async {
    if (pattern.trim().isEmpty) return [];
    final absRoot = await _resolve(path);
    final rootDir = Directory(absRoot);
    if (!await rootDir.exists()) return [];
    RegExp regex;
    try {
      regex = RegExp(pattern, caseSensitive: caseSensitive);
    } catch (e) {
      throw FileSystemException('Gecersiz regex: $e', pattern);
    }
    final globRegex = glob != null && glob.trim().isNotEmpty ? _globToRegExp(glob) : null;
    const skipDirs = {'.git', '.dart_tool', 'build', '.idea', 'node_modules', '__pycache__'};
    const maxMatches = 500;
    const maxFiles = 500;
    final results = <GrepMatch>[];
    int scannedFiles = 0;

    await for (final entity in rootDir.list(recursive: true, followLinks: false)) {
      if (results.length >= maxMatches) break;
      if (scannedFiles >= maxFiles) break;
      final rel = _toRelative(entity.path);
      final parts = rel.split('/');
      if (parts.any((p) => skipDirs.contains(p))) continue;
      final stat = await entity.stat();
      if (stat.type != FileSystemEntityType.file) continue;
      if (stat.size > 5 * 1024 * 1024) continue; // 5MB uzeri skip
      if (stat.size == 0) continue;
      // Glob filtresi
      if (globRegex != null) {
        final posixRel = rel.replaceAll('\\', '/');
        if (!globRegex.hasMatch(posixRel) && !globRegex.hasMatch(p.basename(entity.path))) continue;
      }
      // Binary check (ilk 512 byte'da null var mi)
      try {
        final raf = await File(entity.path).open();
        final header = await raf.read(512);
        await raf.close();
        if (header.contains(0)) continue;
      } catch (_) {
        continue;
      }
      scannedFiles++;
      try {
        final lines = await File(entity.path).readAsLines();
        for (int i = 0; i < lines.length; i++) {
          if (results.length >= maxMatches) break;
          final line = lines[i];
          final match = regex.firstMatch(line);
          if (match != null) {
            final preview = line.length > 200 ? '${line.substring(0, 200)}...' : line;
            results.add(GrepMatch(
              file: rel,
              line: i + 1,
              column: match.start + 1,
              preview: preview.trim(),
            ));
          }
        }
      } catch (_) {
        continue;
      }
    }
    return results;
  }

  /// Dizin olustur.
  Future<void> createDir(String path) async {
    final abs = await _resolve(path);
    await Directory(abs).create(recursive: true);
  }

  /// Dosya veya dizini sil (recursive).
  Future<void> delete(String path) async {
    final abs = await _resolve(path);
    final root = await SandboxConfig.getWorkspaceRoot();
    if (abs == root) {
      throw FileSystemException('Kok dizin silinemez', abs);
    }
    final file = File(abs);
    if (await file.exists()) {
      await file.delete();
      return;
    }
    final dir = Directory(abs);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
      return;
    }
    throw FileSystemException('Silinecek dosya/dizin bulunamadi', abs);
  }

  /// Dosya/dizin tasi (rename).
  Future<void> rename(String from, String to) async {
    final absFrom = await _resolve(from);
    final absTo = await _resolve(to);
    final fromType = await FileSystemEntity.type(absFrom);
    if (fromType == FileSystemEntityType.notFound) {
      throw FileSystemException('Kaynak bulunamadi', absFrom);
    }
    await File(absFrom).parent.create(recursive: true);
    await Directory(p.dirname(absTo)).create(recursive: true);
    if (fromType == FileSystemEntityType.directory) {
      await Directory(absFrom).rename(absTo);
    } else {
      await File(absFrom).rename(absTo);
    }
  }

  /// Dosya stat.
  Future<FileStat> stat(String path) async {
    final abs = await _resolve(path);
    return FileStat.stat(abs);
  }

  /// Agac yapisi icin recursive dosya listesi (max depth 4, max 500 dosya).
  Future<List<FsEntry>> tree({String path = '.', int maxDepth = 4}) async {
    final result = <FsEntry>[];
    await _treeRec(await _resolve(path), 0, maxDepth, result);
    return result;
  }

  Future<void> _treeRec(String abs, int depth, int maxDepth, List<FsEntry> out) async {
    if (depth > maxDepth) return;
    if (out.length > 500) return;
    final dir = Directory(abs);
    if (!await dir.exists()) return;
    final entities = await dir.list(followLinks: false).toList();
    for (final e in entities) {
      final stat = await e.stat();
      final isDir = stat.type == FileSystemEntityType.directory;
      out.add(FsEntry(
        name: p.basename(e.path),
        absolutePath: e.path,
        relativePath: _toRelative(e.path),
        isDirectory: isDir,
        size: isDir ? null : stat.size,
        modified: stat.modified,
      ));
      if (isDir) {
        await _treeRec(e.path, depth + 1, maxDepth, out);
      }
    }
  }

  /// Workspace'i tamamen temizle (dikkatli kullan).
  Future<void> clearWorkspace() async {
    final root = await SandboxConfig.getWorkspaceRoot();
    final dir = Directory(root);
    if (await dir.exists()) {
      await for (final e in dir.list(followLinks: false)) {
        if (e is Directory) {
          await e.delete(recursive: true);
        } else {
          await e.delete();
        }
      }
    }
  }
}
