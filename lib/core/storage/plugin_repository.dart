import 'dart:convert';

import 'package:hive/hive.dart';

import '../models/http_tool_plugin.dart';
import 'local_database.dart';

/// Plugin CRUD — Hive pluginsBox uzerinden.
/// Test-safe: box acik degilse bos liste döner (todosBox pattern).
class PluginRepository {
  PluginRepository._();
  static final PluginRepository instance = PluginRepository._();

  Box<HttpToolPlugin>? _safePluginsBox() {
    try {
      if (Hive.isBoxOpen(LocalDatabase.pluginsBoxName)) {
        return Hive.box<HttpToolPlugin>(LocalDatabase.pluginsBoxName);
      }
      try {
        return LocalDatabase.pluginsBox;
      } catch (_) {
        return null;
      }
    } catch (_) {
      return null;
    }
  }

  List<HttpToolPlugin> getAll() {
    final box = _safePluginsBox();
    if (box == null) return [];
    return box.values.toList()..sort((a, b) => a.name.compareTo(b.name));
  }

  List<HttpToolPlugin> getEnabled() {
    return getAll().where((p) => p.enabled).toList();
  }

  HttpToolPlugin? getByName(String name) {
    final box = _safePluginsBox();
    if (box == null) return null;
    for (final p in box.values) {
      if (p.name == name) return p;
    }
    return null;
  }

  Future<void> save(HttpToolPlugin plugin) async {
    final box = _safePluginsBox();
    if (box == null) return;
    await box.put(plugin.id, plugin);
  }

  Future<void> delete(String id) async {
    final box = _safePluginsBox();
    if (box == null) return;
    await box.delete(id);
  }

  /// JSON string'den plugin olustur + dogrula. Hata varsa exception firlatir.
  HttpToolPlugin fromJsonString(String jsonStr) {
    final decoded = jsonDecodeSafe(jsonStr);
    if (decoded == null || decoded is! Map<String, dynamic>) {
      throw FormatException('Gecersiz JSON');
    }
    final name = decoded['name']?.toString() ?? '';
    if (name.isEmpty || !RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(name)) {
      throw FormatException('name gerekli ve kucuk harf/underscore olmali: $name');
    }
    // Built-in tool isimleriyle cakisma kontrolu
    const builtins = ['file_read', 'file_write', 'file_list', 'file_delete', 'file_edit', 'file_glob', 'file_grep', 'shell_exec', 'todo_write', 'dispatch_subtask'];
    if (builtins.contains(name)) {
      throw FormatException('Bu isim built-in tool ile cakisiyor: $name');
    }
    final url = decoded['urlTemplate']?.toString() ?? decoded['url']?.toString() ?? '';
    if (url.isEmpty) throw FormatException('urlTemplate/url gerekli');
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) throw FormatException('Gecersiz URL: $url');
    if (uri.scheme != 'https' && uri.scheme != 'http') throw FormatException('Sadece http/https: $url');
    return HttpToolPlugin(
      id: decoded['id']?.toString() ?? 'plugin_${DateTime.now().millisecondsSinceEpoch}_$name',
      name: name,
      description: decoded['description']?.toString() ?? '',
      urlTemplate: url,
      method: (decoded['method']?.toString() ?? 'GET').toUpperCase(),
      headers: Map<String, String>.from(decoded['headers'] as Map? ?? {}),
      bodyTemplate: decoded['bodyTemplate'] == null ? null : Map<String, dynamic>.from(decoded['bodyTemplate'] as Map),
      responseJsonPath: decoded['responseJsonPath']?.toString(),
      errorJsonPath: decoded['errorJsonPath']?.toString(),
      parameters: Map<String, dynamic>.from(decoded['parameters'] as Map? ?? {}),
      enabled: decoded['enabled'] as bool? ?? true,
    );
  }

  dynamic jsonDecodeSafe(String s) {
    try {
      return jsonDecode(s);
    } catch (_) {
      return null;
    }
  }
}
