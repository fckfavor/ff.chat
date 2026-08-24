import 'dart:convert';

import 'package:http/http.dart' as http;

import '../engine/json_path_resolver.dart';
import '../hooks/hook_service.dart';
import '../models/http_tool_plugin.dart';
import '../storage/plugin_repository.dart';
import '../workspace/shell_executor.dart';
import '../workspace/workspace_fs.dart';
import 'permission_gate.dart';

/// Tek bir tool cagrisinin sonucu.
class ToolResult {
  ToolResult({
    required this.toolCallId,
    required this.name,
    required this.content,
    this.isError = false,
  });

  final String toolCallId;
  final String name;
  final String content;
  final bool isError;

  Map<String, dynamic> toOpenAiToolMessage() => {
        'role': 'tool',
        'tool_call_id': toolCallId,
        'content': content,
      };
}

/// LLM'den gelen tool_call'i gercek isleme cevirir.
///
/// Gelen format (OpenAI):
/// { "id": "call_123", "type": "function", "function": { "name": "file_read", "arguments": "{\"path\": \"main.dart\"}" } }
class ToolExecutor {
  ToolExecutor._();
  static final ToolExecutor instance = ToolExecutor._();

  final _fs = WorkspaceFs.instance;
  final _shell = ShellExecutor.instance;

  /// Tek bir tool'u calistir, gerekiyorsa izin iste.
  /// [permissionRequest] -> UI'a sor, PermissionResponse dondurur
  Future<ToolResult> execute(
    Map<String, dynamic> toolCall, {
    Future<PermissionResponse> Function(String toolName, Map<String, dynamic> args)? permissionRequest,
  }) async {
    final id = toolCall['id']?.toString() ?? 'call_${DateTime.now().millisecondsSinceEpoch}';
    final func = toolCall['function'] as Map<String, dynamic>?;
    final name = func?['name']?.toString() ?? toolCall['name']?.toString() ?? 'unknown';
    final argsRaw = func?['arguments'] ?? toolCall['arguments'] ?? '{}';

    Map<String, dynamic> args;
    try {
      if (argsRaw is String) {
        args = jsonDecode(argsRaw) as Map<String, dynamic>;
      } else if (argsRaw is Map) {
        args = Map<String, dynamic>.from(argsRaw);
      } else {
        args = {};
      }
    } catch (e) {
      return ToolResult(toolCallId: id, name: name, content: 'arguments JSON parse hatasi: $e', isError: true);
    }

    // Izin gate — riskli tool'lar icin UI'dan onay bekle
    if (permissionRequest != null && PermissionGate.instance.needsApproval(name)) {
      final response = await permissionRequest(name, args);
      if (!response.approved) {
        return ToolResult(
          toolCallId: id,
          name: name,
          content: PermissionGate.deniedContent(name),
          isError: true,
        );
      }
      if (response.dontAskAgain) {
        PermissionGate.instance.allowForSession(name);
      }
      if (response.editedArgs != null) {
        args = response.editedArgs!;
      }
    }

    try {
      switch (name) {
        case 'file_read':
          return await _fileRead(id, args);
        case 'file_write':
          return await _fileWrite(id, args);
        case 'file_list':
          return await _fileList(id, args);
        case 'file_delete':
          return await _fileDelete(id, args);
        case 'file_edit':
          return await _fileEdit(id, args);
        case 'file_glob':
          return await _fileGlob(id, args);
        case 'file_grep':
          return await _fileGrep(id, args);
        case 'todo_write':
          return await _todoWrite(id, args);
        case 'dispatch_subtask':
          return await _dispatchSubtask(id, args);
        case 'shell_exec':
          return await _shellExec(id, args);
        default:
          // Plugin lookup — JSON HTTP tool
          final plugin = PluginRepository.instance.getByName(name);
          if (plugin != null) {
            return await _pluginHttpExecute(id, plugin, args);
          }
          return ToolResult(toolCallId: id, name: name, content: 'Bilinmeyen tool: $name', isError: true);
      }
    } catch (e) {
      return ToolResult(toolCallId: id, name: name, content: 'Tool hatasi ($name): $e', isError: true);
    }
  }

  /// Plugin'in tanimladigi HTTP cagrisini yapar.
  /// Guvenlik: https zorunlu (http sadece LAN), args ile {{placeholder}} doldurma,
  /// response responseJsonPath ile ayristirilir, 10k truncate.
  Future<ToolResult> _pluginHttpExecute(String id, HttpToolPlugin plugin, Map<String, dynamic> args) async {
    try {
      String url = plugin.urlTemplate;
      // {{arg}} placeholder'larini URL ve body'de doldur (URL-encode'lu)
      args.forEach((key, value) {
        final encoded = Uri.encodeComponent(value.toString());
        url = url.replaceAll('{{$key}}', encoded).replaceAll('{\$$key}', value.toString());
      });
      // Kalan placeholder varsa temizle
      url = url.replaceAll(RegExp(r'\{\{[a-zA-Z_][a-zA-Z0-9_]*\}\}'), '');
      final uri = Uri.parse(url);

      // http:// sadece localhost/LAN izinli (DynamicHttpClient ile ayni kural)
      if (uri.scheme == 'http') {
        final host = uri.host;
        final isLocal = host == 'localhost' || host == '127.0.0.1' || host == '::1';
        final isPrivate = RegExp(r'^(10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.)').hasMatch(host);
        if (!isLocal && !isPrivate) {
          return ToolResult(
            toolCallId: id,
            name: plugin.name,
            content: 'Guvenlik: http:// sadece localhost/yerel ag icin. https kullan.',
            isError: true,
          );
        }
      }

      // Header template fill
      final headers = <String, String>{};
      plugin.headers.forEach((k, v) {
        var filled = v;
        args.forEach((key, value) => filled = filled.replaceAll('{{$key}}', value.toString()));
        headers[k] = filled;
      });

      final client = http.Client();
      http.Response response;
      try {
        switch (plugin.method) {
          case 'POST':
          case 'PUT':
          case 'PATCH':
            Map<String, dynamic> body = {};
            if (plugin.bodyTemplate != null) {
              body = jsonDecode(jsonEncode(plugin.bodyTemplate!)) as Map<String, dynamic>;
              _fillBodyArgs(body, args);
            } else {
              body = Map<String, dynamic>.from(args);
            }
            headers.putIfAbsent('Content-Type', () => 'application/json');
            final request = http.Request(plugin.method, uri)
              ..headers.addAll(headers)
              ..body = jsonEncode(body);
            final streamed = await client.send(request).timeout(const Duration(seconds: 30));
            response = await http.Response.fromStream(streamed).timeout(const Duration(seconds: 30));
            break;
          case 'DELETE':
            response = await client.delete(uri, headers: headers).timeout(const Duration(seconds: 30));
            break;
          case 'GET':
          default:
            response = await client.get(uri, headers: headers).timeout(const Duration(seconds: 30));
            break;
        }
      } finally {
        client.close();
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        String errMsg = response.body;
        if (plugin.errorJsonPath != null && plugin.errorJsonPath!.isNotEmpty) {
          try {
            final decoded = jsonDecode(response.body);
            final resolved = JsonPathResolver.resolve(decoded, plugin.errorJsonPath!);
            if (resolved != null) errMsg = resolved.toString();
          } catch (_) {}
        }
        return ToolResult(toolCallId: id, name: plugin.name, content: 'HTTP ${response.statusCode}: $errMsg', isError: true);
      }

      // Response parse
      String output = response.body;
      if (plugin.responseJsonPath != null && plugin.responseJsonPath!.isNotEmpty) {
        try {
          final decoded = jsonDecode(response.body);
          final resolved = JsonPathResolver.resolve(decoded, plugin.responseJsonPath!);
          if (resolved != null) output = resolved is String ? resolved : jsonEncode(resolved);
        } catch (_) {}
      }
      if (output.length > 10000) output = '${output.substring(0, 10000)}\n[... truncated]';
      return ToolResult(toolCallId: id, name: plugin.name, content: output.isEmpty ? '(bos yanit)' : output);
    } catch (e) {
      return ToolResult(toolCallId: id, name: plugin.name, content: 'plugin error: $e', isError: true);
    }
  }

  void _fillBodyArgs(Map<String, dynamic> body, Map<String, dynamic> args) {
    body.forEach((key, value) {
      if (value is String && value.startsWith('{{') && value.endsWith('}}')) {
        final argName = value.substring(2, value.length - 2);
        if (args.containsKey(argName)) {
          body[key] = args[argName];
        }
      } else if (value is Map<String, dynamic>) {
        _fillBodyArgs(value, args);
      }
    });
  }

  Future<ToolResult> _fileRead(String id, Map<String, dynamic> args) async {
    final path = args['path']?.toString() ?? '';
    if (path.isEmpty) return ToolResult(toolCallId: id, name: 'file_read', content: 'path gerekli', isError: true);
    try {
      final content = await _fs.readFile(path);
      // Cikti cok buyukse kisalt (LLM context limiti)
      if (content.length > 20000) {
        return ToolResult(
          toolCallId: id,
          name: 'file_read',
          content: '${content.substring(0, 20000)}\n\n[... truncated, file too large (${content.length} chars)]',
        );
      }
      return ToolResult(toolCallId: id, name: 'file_read', content: content);
    } catch (e) {
      return ToolResult(toolCallId: id, name: 'file_read', content: 'read error: $e', isError: true);
    }
  }

  Future<ToolResult> _fileWrite(String id, Map<String, dynamic> args) async {
    final path = args['path']?.toString() ?? '';
    final content = args['content']?.toString() ?? '';
    if (path.isEmpty) return ToolResult(toolCallId: id, name: 'file_write', content: 'path gerekli', isError: true);
    try {
      await _fs.writeFile(path, content);
      // Post-hook: dart format (fire-and-forget, hata yut)
      // ignore: unawaited_futures
      HookService.instance.onPostTool('file_write', args);
      return ToolResult(toolCallId: id, name: 'file_write', content: 'OK: $path yazildi (${content.length} chars)');
    } catch (e) {
      return ToolResult(toolCallId: id, name: 'file_write', content: 'write error: $e', isError: true);
    }
  }

  Future<ToolResult> _fileList(String id, Map<String, dynamic> args) async {
    final path = args['path']?.toString() ?? '.';
    try {
      final entries = await _fs.list(path);
      if (entries.isEmpty) return ToolResult(toolCallId: id, name: 'file_list', content: '($path) bos');
      final lines = entries.map((e) => '${e.isDirectory ? "d" : "-"} ${e.name}${e.isDirectory ? "/" : " (${e.size ?? 0} bytes)"}').join('\n');
      return ToolResult(toolCallId: id, name: 'file_list', content: lines);
    } catch (e) {
      return ToolResult(toolCallId: id, name: 'file_list', content: 'list error: $e', isError: true);
    }
  }

  Future<ToolResult> _fileDelete(String id, Map<String, dynamic> args) async {
    final path = args['path']?.toString() ?? '';
    if (path.isEmpty) return ToolResult(toolCallId: id, name: 'file_delete', content: 'path gerekli', isError: true);
    try {
      await _fs.delete(path);
      return ToolResult(toolCallId: id, name: 'file_delete', content: 'OK: $path silindi');
    } catch (e) {
      return ToolResult(toolCallId: id, name: 'file_delete', content: 'delete error: $e', isError: true);
    }
  }

  Future<ToolResult> _fileEdit(String id, Map<String, dynamic> args) async {
    final path = args['path']?.toString() ?? '';
    final oldString = args['old_string']?.toString() ?? '';
    final newString = args['new_string']?.toString() ?? '';
    if (path.isEmpty) return ToolResult(toolCallId: id, name: 'file_edit', content: 'path gerekli', isError: true);
    if (oldString.isEmpty) return ToolResult(toolCallId: id, name: 'file_edit', content: 'old_string bos olamaz (unique match gerekli)', isError: true);
    try {
      final diff = await _fs.editFile(path, oldString, newString);
      // Post-hook: dart format
      // ignore: unawaited_futures
      HookService.instance.onPostTool('file_edit', args);
      return ToolResult(toolCallId: id, name: 'file_edit', content: 'OK: $path duzenlendi\n$diff');
    } catch (e) {
      return ToolResult(toolCallId: id, name: 'file_edit', content: 'edit error: $e', isError: true);
    }
  }

  Future<ToolResult> _fileGlob(String id, Map<String, dynamic> args) async {
    final pattern = args['pattern']?.toString() ?? '';
    final path = args['path']?.toString() ?? '.';
    if (pattern.isEmpty) return ToolResult(toolCallId: id, name: 'file_glob', content: 'pattern gerekli', isError: true);
    try {
      final entries = await _fs.glob(pattern, rootPath: path);
      if (entries.isEmpty) return ToolResult(toolCallId: id, name: 'file_glob', content: '($pattern) eslesme yok');
      final lines = entries.map((e) => '${e.isDirectory ? "d" : "-"} ${e.relativePath}').join('\n');
      final truncated = lines.length > 10000 ? '${lines.substring(0, 10000)}\n[... truncated, ${entries.length} dosya]' : lines;
      return ToolResult(toolCallId: id, name: 'file_glob', content: truncated);
    } catch (e) {
      return ToolResult(toolCallId: id, name: 'file_glob', content: 'glob error: $e', isError: true);
    }
  }

  Future<ToolResult> _fileGrep(String id, Map<String, dynamic> args) async {
    final pattern = args['pattern']?.toString() ?? '';
    final path = args['path']?.toString() ?? '.';
    final glob = args['glob']?.toString();
    if (pattern.isEmpty) return ToolResult(toolCallId: id, name: 'file_grep', content: 'pattern gerekli', isError: true);
    try {
      final matches = await _fs.grep(pattern, path: path, glob: glob);
      if (matches.isEmpty) return ToolResult(toolCallId: id, name: 'file_grep', content: '($pattern) eslesme yok');
      final lines = matches.map((m) => '${m.file}:${m.line}:${m.column}: ${m.preview}').join('\n');
      final truncated = lines.length > 10000 ? '${lines.substring(0, 10000)}\n[... truncated, ${matches.length} eslesme]' : lines;
      return ToolResult(toolCallId: id, name: 'file_grep', content: truncated);
    } catch (e) {
      return ToolResult(toolCallId: id, name: 'file_grep', content: 'grep error: $e', isError: true);
    }
  }

  Future<ToolResult> _todoWrite(String id, Map<String, dynamic> args) async {
    final todosRaw = args['todos'];
    if (todosRaw == null) return ToolResult(toolCallId: id, name: 'todo_write', content: 'todos gerekli', isError: true);
    try {
      final todos = (todosRaw as List).cast<Map<String, dynamic>>();
      if (todos.isEmpty) return ToolResult(toolCallId: id, name: 'todo_write', content: 'OK: todo listesi temizlendi');
      final summary = todos.map((t) => '[${t['status'] ?? 'pending'}] ${t['content']}').join('\n');
      return ToolResult(toolCallId: id, name: 'todo_write', content: 'OK: ${todos.length} todo guncellendi\n$summary');
    } catch (e) {
      return ToolResult(toolCallId: id, name: 'todo_write', content: 'todo_write error: $e', isError: true);
    }
  }

  Future<ToolResult> _dispatchSubtask(String id, Map<String, dynamic> args) async {
    // Bu tool sadece AgentLoop uzerinden calisir (subagent derin dusunme)
    // Direkt ToolExecutor uzerinden cagrilirsa hata dondur, AgentLoop intercept etmeli
    return ToolResult(
      toolCallId: id,
      name: 'dispatch_subtask',
      content: 'dispatch_subtask sadece AgentLoop uzerinden calisir — lutfen AgentLoop.runTextStream kullan',
      isError: true,
    );
  }

  Future<ToolResult> _shellExec(String id, Map<String, dynamic> args) async {
    final command = args['command']?.toString() ?? '';
    final workdir = args['workdir']?.toString() ?? '.';
    if (command.isEmpty) return ToolResult(toolCallId: id, name: 'shell_exec', content: 'command gerekli', isError: true);
    final result = await _shell.run(command, workingDir: workdir);
    final output = result.combined.isEmpty ? '(no output, exit ${result.exitCode})' : result.combined;
    // Cikti limit
    final truncated = output.length > 10000 ? '${output.substring(0, 10000)}\n[... truncated]' : output;
    return ToolResult(
      toolCallId: id,
      name: 'shell_exec',
      content: 'exit:${result.exitCode} duration:${result.duration.inMilliseconds}ms\n$truncated',
      isError: !result.success,
    );
  }

  /// Birden fazla tool_call'i sirayla calistir.
  Future<List<ToolResult>> executeAll(
    List<Map<String, dynamic>> toolCalls, {
    Future<PermissionResponse> Function(String toolName, Map<String, dynamic> args)? permissionRequest,
  }) async {
    final results = <ToolResult>[];
    for (final tc in toolCalls) {
      results.add(await execute(tc, permissionRequest: permissionRequest));
    }
    return results;
  }
}
