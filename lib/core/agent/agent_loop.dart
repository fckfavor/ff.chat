import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../engine/json_path_resolver.dart';
import '../storage/app_settings_repository.dart';
import '../engine/template_engine.dart';
import '../http/dynamic_http_client.dart';
import '../models/preset.dart';
import 'context_compaction.dart';
import 'permission_gate.dart';
import 'tool_definitions.dart';
import 'tool_executor.dart';

/// Agent'in UI'a gonderdigi olay tipi.
enum AgentEventType { textDelta, toolCall, toolResult, permissionRequest, done, error }

class AgentEvent {
  AgentEvent({required this.type, required this.content, this.toolName});

  final AgentEventType type;
  final String content;
  final String? toolName;
}

/// Agentic loop — LLM'in tool cagrilarini otomatik calistirir.
///
/// Kullanim: `AgentLoop.instance.run(...).listen((event) => ui.update(event))`
/// Desteklenmeyen preset'lerde (Gemini/Anthropic) direkt normal stream'e duser.
class AgentLoop {
  AgentLoop._();
  static final AgentLoop instance = AgentLoop._();

  final http.Client _client = http.Client();

  static const int maxIterations = 8;

  final AppSettingsRepository _settingsRepo = AppSettingsRepository();

  String get effortLevel => _settingsRepo.getEffortLevel();

  static const int maxSubagentDepth = 2;
  static const int maxSubagentsPerTurn = 3;

  /// Ana giris — text delta stream dondurur (UI icin basit).
  /// Tool aktifse otomatik loop yapar, degilse normal DynamicHttpClient stream gibi davranir.
  /// [onPermissionRequest] -> UI'dan izin isteyen callback. null ise auto-approve (testler icin).
  /// [onTodosUpdated] -> todo_write cagrildiginda UI checklist'i guncellemek icin.
  /// [depth] -> subagent recursion derinligi (0 = ana agent)
  /// [planMode] -> true ise henuz plan onaylanmadan yazma/calistirma yasak
  Stream<String> runTextStream({
    required Preset preset,
    required String? apiKey,
    required String modelName,
    required List<Map<String, dynamic>> conversationHistory,
    required double temperature,
    String? systemPrompt,
    String? baseUrl,
    Future<PermissionResponse> Function(String toolName, Map<String, dynamic> args)? onPermissionRequest,
    void Function(List<Map<String, dynamic>> todos)? onTodosUpdated,
    int depth = 0,
    bool planMode = false,
    bool planApproved = false,
  }) async* {
    final supportsTools = ToolDefinitions.presetSupportsTools(preset.id);

    if (!supportsTools) {
      // Tool destegi yok — direkt normal stream
      final client = DynamicHttpClient(client: _client);
      yield* client.sendStream(
        preset: preset,
        apiKey: apiKey,
        modelName: modelName,
        conversationHistory: conversationHistory,
        temperature: temperature,
        systemPrompt: systemPrompt,
        baseUrl: baseUrl,
      );
      return;
    }

    // Tool destekli loop — once systemPrompt'a tool talimati ekle
    final effectiveSystemPrompt = [
      if (systemPrompt != null && systemPrompt.trim().isNotEmpty) systemPrompt,
      ToolDefinitions.toolSystemPromptAddendum,
      if (planMode && !planApproved)
        'PLAN MODU AKTIF: Sadece todo_write ve readonly tool\'lar (file_read, file_list, file_glob, file_grep) kullan. '
            'file_write/file_edit/file_delete/shell_exec ve dispatch_subtask YASAK — once plan yaz (todo_write) ve kullanicinin "Uygula" onayini bekle.',
    ].join('\n\n');

    // Mesaj gecmisini kopyala (mutasyona ugrayacak) + ilk compaction
    var messages = ContextCompactor.instance.compactForSession(
      List<Map<String, dynamic>>.from(conversationHistory),
      systemPrompt: effectiveSystemPrompt,
    );

    int iterations = 0;
    while (iterations < maxIterations) {
      iterations++;

      // Her iterasyonda mesajlar sismis olabilir (tool sonuclari 10k), tekrar compact
      messages = ContextCompactor.instance.compactForSession(messages, systemPrompt: effectiveSystemPrompt);

      // Her iterasyonda LLM'e istek at (non-stream, tool_calls'i almak icin)
      final rawResponse = await _callWithTools(
        preset: preset,
        apiKey: apiKey,
        modelName: modelName,
        messages: messages,
        temperature: temperature,
        systemPrompt: effectiveSystemPrompt,
        baseUrl: baseUrl,
      );

      // Response parse
      final choices = rawResponse['choices'] as List?;
      if (choices == null || choices.isEmpty) {
        final content = JsonPathResolver.resolve(rawResponse, preset.responseJsonPath)?.toString() ?? '';
        if (content.isNotEmpty) yield content;
        break;
      }
      final firstChoice = choices.first as Map<String, dynamic>;
      final message = firstChoice['message'] as Map<String, dynamic>? ?? {};

      final content = message['content']?.toString() ?? '';
      final toolCallsRaw = message['tool_calls'] as List?;

      final hasTools = toolCallsRaw != null && toolCallsRaw.isNotEmpty;

      if (!hasTools) {
        // Tool yok — bu final cevaptir, stream gibi yield et
        if (content.isNotEmpty) {
          // Icerik buyukse parca parca yield et (typing efekti icin)
          yield content;
        } else {
          // Bazen content bos ama delta'da var (streamed tool degil) — fallback
          final fallback = JsonPathResolver.resolve(rawResponse, preset.responseJsonPath)?.toString() ?? '';
          if (fallback.isNotEmpty) yield fallback;
        }
        break;
      }

      // Tool var — once varsa content'i goster
      if (content.isNotEmpty) {
        yield content;
        yield '\n';
      }

      // Tool call'lari normalize et
      final toolCalls = toolCallsRaw.cast<Map<String, dynamic>>();
      // UI'a trace ver
      for (final tc in toolCalls) {
        final fname = (tc['function']?['name'] ?? 'unknown').toString();
        final args = (tc['function']?['arguments'] ?? '').toString();
        yield '\n> tool: `$fname` `$args`\n';
      }

      // TodoWrite intercept — UI checklist guncelle
      if (onTodosUpdated != null) {
        for (final tc in toolCalls) {
          final fname = (tc['function']?['name'] ?? '').toString();
          if (fname == 'todo_write') {
            try {
              final argsRaw = tc['function']?['arguments'];
              Map<String, dynamic> args;
              if (argsRaw is String) {
                args = jsonDecode(argsRaw) as Map<String, dynamic>;
              } else if (argsRaw is Map) {
                args = Map<String, dynamic>.from(argsRaw);
              } else {
                args = {};
              }
              final todos = (args['todos'] as List?)?.cast<Map<String, dynamic>>() ?? [];
              onTodosUpdated(todos);
            } catch (_) {}
          }
        }
      }

      // Dispatch_subtask intercept — subagent derin dusunme ile calistir (incele->dusun->plan->uygula)
      // Normal tool'lardan ayri, kendi context'inde calisir, ana context sismeden ozet dondurur
      final normalCalls = <Map<String, dynamic>>[];
      final subagentCalls = <Map<String, dynamic>>[];
      for (final tc in toolCalls) {
        final fname = (tc['function']?['name'] ?? '').toString();
        if (fname == 'dispatch_subtask') {
          subagentCalls.add(tc);
        } else {
          normalCalls.add(tc);
        }
      }

      // Subagent'lari sirayla calistir (max 3 per turn, depth limit 2)
      final subagentResults = <ToolResult>[];
      for (int i = 0; i < subagentCalls.length && i < maxSubagentsPerTurn; i++) {
        final tc = subagentCalls[i];
        final id = tc['id']?.toString() ?? 'call_${DateTime.now().millisecondsSinceEpoch}_sub';
        if (depth >= maxSubagentDepth) {
          subagentResults.add(ToolResult(
            toolCallId: id,
            name: 'dispatch_subtask',
            content: 'Subagent depth limit ($maxSubagentDepth) asildi — daha fazla subagent olusturulamaz.',
            isError: true,
          ));
          continue;
        }
        final func = tc['function'] as Map<String, dynamic>?;
        final argsRaw = func?['arguments'] ?? tc['arguments'] ?? '{}';
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
          subagentResults.add(ToolResult(
            toolCallId: id,
            name: 'dispatch_subtask',
            content: 'arguments parse hatasi: $e',
            isError: true,
          ));
          continue;
        }
        final task = args['task']?.toString() ?? '';
        final context = args['context']?.toString() ?? '';
        if (task.isEmpty) {
          subagentResults.add(ToolResult(
            toolCallId: id,
            name: 'dispatch_subtask',
            content: 'task bos olamaz',
            isError: true,
          ));
          continue;
        }
        yield '\n[subagent baslatiliyor: $task]\n';
        try {
          final subResult = await _runSubagent(
            preset: preset,
            apiKey: apiKey,
            modelName: modelName,
            task: task,
            context: context,
            temperature: temperature,
            baseUrl: baseUrl,
            onPermissionRequest: onPermissionRequest,
            onTodosUpdated: onTodosUpdated,
            depth: depth + 1,
          );
          subagentResults.add(ToolResult(
            toolCallId: id,
            name: 'dispatch_subtask',
            content: subResult,
            isError: false,
          ));
          yield '\n[subagent bitti, ozet: ${subResult.length > 400 ? '${subResult.substring(0, 400)}...' : subResult}]\n';
        } catch (e) {
          subagentResults.add(ToolResult(
            toolCallId: id,
            name: 'dispatch_subtask',
            content: 'Subagent hatasi: $e',
            isError: true,
          ));
        }
      }

      // Plan Modu: onay yoksa sadece plan+readonly izinli
      List<ToolResult> normalResults = [];
      if (normalCalls.isNotEmpty) {
        if (planMode && !planApproved) {
          const allowedInPlan = {'todo_write', 'file_read', 'file_list', 'file_glob', 'file_grep', 'dispatch_subtask'};
          final allowed = <Map<String, dynamic>>[];
          final blocked = <Map<String, dynamic>>[];
          for (final tc in normalCalls) {
            final fname = (tc['function']?['name'] ?? '').toString();
            if (allowedInPlan.contains(fname)) {
              allowed.add(tc);
            } else {
              blocked.add(tc);
            }
          }
          // Blocked olanlara denied dondur
          for (final tc in blocked) {
            final id = tc['id']?.toString() ?? 'call_${DateTime.now().millisecondsSinceEpoch}';
            final fname = (tc['function']?['name'] ?? 'unknown').toString();
            normalResults.add(ToolResult(
              toolCallId: id,
              name: fname,
              content: 'Plan modunda once plan onaylanmali — $fname su an yasak. Once todo_write ile plan yaz ve "Uygula" bekle.',
              isError: true,
            ));
            yield '\n[!] Plan modu: $fname engellendi (onay bekleniyor)\n';
          }
          if (allowed.isNotEmpty) {
            final allowedResults = await ToolExecutor.instance.executeAll(
              allowed,
              permissionRequest: onPermissionRequest,
            );
            normalResults.addAll(allowedResults);
          }
        } else {
          normalResults = await ToolExecutor.instance.executeAll(
            normalCalls,
            permissionRequest: onPermissionRequest,
          );
        }
      }

      // Sonuclari birlestir (subagent + normal, sira korunur)
      final results = <ToolResult>[];
      int subIdx = 0, normIdx = 0;
      for (final tc in toolCalls) {
        final fname = (tc['function']?['name'] ?? '').toString();
        if (fname == 'dispatch_subtask') {
          if (subIdx < subagentResults.length) {
            results.add(subagentResults[subIdx++]);
          }
        } else {
          if (normIdx < normalResults.length) {
            results.add(normalResults[normIdx++]);
          }
        }
      }
      for (final r in results) {
        // Kisa ozet UI'a
        final preview = r.content.length > 400 ? '${r.content.substring(0, 400)}...' : r.content;
        yield '\n< ${r.name}: $preview\n';
        if (r.isError && r.content.contains('Kullanıcı reddetti')) {
          yield '\n[!] Kullanici reddetti — ajan alternatif dusunecek\n';
        }
      }

      // Gecmisi guncelle — LLM'in gonderdigi assistant tool_calls mesaji + tool sonuclari
      messages.add({
        'role': 'assistant',
        'content': content,
        'tool_calls': toolCalls,
      });

      for (final r in results) {
        messages.add({
          'role': 'tool',
          'tool_call_id': r.toolCallId,
          'content': r.content,
        });
      }

      // Dongu devam — bir sonraki iterasyonda LLM tool sonuclarini gorup devam edecek
    }

    if (iterations >= maxIterations) {
      yield '\n[agent: max iterations ($maxIterations) reached]\n';
    }
  }

  /// Subagent'i derin dusunme prensibiyle calistir (incele->dusun->plan->uygula)
  Future<String> _runSubagent({
    required Preset preset,
    required String? apiKey,
    required String modelName,
    required String task,
    required String context,
    required double temperature,
    String? baseUrl,
    Future<PermissionResponse> Function(String toolName, Map<String, dynamic> args)? onPermissionRequest,
    void Function(List<Map<String, dynamic>> todos)? onTodosUpdated,
    required int depth,
    bool planMode = false,
    bool planApproved = false,
  }) async {
    // Subagent icin derin dusunme system prompt'u
    final subSystemPrompt = '${ToolDefinitions.subagentSystemPromptAddendum}\n\nAna gorev baglami: $context';

    final subHistory = [
      {
        'role': 'user',
        'content': 'GOREV: $task\n\nBAGLAm: $context\n\n'
            'Lutfen su prensiple calis: ONCE INCELE (file_glob/grep ile kesfet) -> DUSUN (<thinking> kisa, 10 kelime) -> PLAN YAP (todo_write) -> UYGULA. '
            'Sonucta neyi inceledin, ne buldun, ne yaptin ozetle.',
      },
    ];

    final buffer = StringBuffer();
    // Subagent'i ayni AgentLoop uzerinden ama depth artmis sekilde calistir
    // Not: ayni instance uzerinden depth parametresi ile recursion kontrolu saglanir
    await for (final chunk in runTextStream(
      preset: preset,
      apiKey: apiKey,
      modelName: modelName,
      conversationHistory: subHistory,
      temperature: temperature,
      systemPrompt: subSystemPrompt,
      baseUrl: baseUrl,
      onPermissionRequest: onPermissionRequest,
      onTodosUpdated: onTodosUpdated,
      depth: depth,
      planMode: planMode,
      planApproved: planApproved,
    )) {
      buffer.write(chunk);
    }
    final result = buffer.toString();
    if (result.trim().isEmpty) return '[subagent bos dondu]';
    // Ozet icin truncate (ana context'e cok buyuk donmesin)
    if (result.length > 8000) return '${result.substring(0, 8000)}\n[... subagent output truncated]';
    return result;
  }

  /// Event bazli stream (daha ayrintili UI icin).
  Stream<AgentEvent> runEventStream({
    required Preset preset,
    required String? apiKey,
    required String modelName,
    required List<Map<String, dynamic>> conversationHistory,
    required double temperature,
    String? systemPrompt,
    String? baseUrl,
    Future<PermissionResponse> Function(String toolName, Map<String, dynamic> args)? onPermissionRequest,
    void Function(List<Map<String, dynamic>> todos)? onTodosUpdated,
  }) async* {
    await for (final chunk in runTextStream(
      preset: preset,
      apiKey: apiKey,
      modelName: modelName,
      conversationHistory: conversationHistory,
      temperature: temperature,
      systemPrompt: systemPrompt,
      baseUrl: baseUrl,
      onPermissionRequest: onPermissionRequest,
      onTodosUpdated: onTodosUpdated,
    )) {
      // Basit heuristic: tool trace mi text mi?
      if (chunk.contains('tool:') || chunk.startsWith('< ')) {
        yield AgentEvent(type: AgentEventType.toolCall, content: chunk);
      } else {
        yield AgentEvent(type: AgentEventType.textDelta, content: chunk);
      }
    }
    yield AgentEvent(type: AgentEventType.done, content: '');
  }

  /// LLM'e tool'larla birlikte tek bir istek atar, raw JSON dondurur.
  Future<Map<String, dynamic>> _callWithTools({
    required Preset preset,
    required String? apiKey,
    required String modelName,
    required List<Map<String, dynamic>> messages,
    required double temperature,
    required String systemPrompt,
    String? baseUrl,
  }) async {
    // URI ve header'lari DynamicHttpClient ile ayni mantikta olustur
    final filledQueryParams = TemplateEngine.fillStringMap(
      template: preset.urlQueryParams,
      apiKey: apiKey,
      modelName: modelName,
      systemPrompt: systemPrompt,
    );

    final effectiveTemplate = (baseUrl != null && baseUrl.trim().isNotEmpty)
        ? baseUrl.trim()
        : preset.baseUrlTemplate;
    final filledUrl = effectiveTemplate.replaceAll('{{MODEL}}', modelName);
    var uri = Uri.parse(filledUrl);
    _assertSafeScheme(uri);
    if (filledQueryParams.isNotEmpty) {
      final merged = Map<String, String>.from(uri.queryParameters)..addAll(filledQueryParams);
      uri = uri.replace(queryParameters: merged);
    }

    final headers = TemplateEngine.fillStringMap(
      template: preset.headers,
      apiKey: apiKey,
      modelName: modelName,
      systemPrompt: systemPrompt,
    );
    headers.putIfAbsent('Content-Type', () => 'application/json');

    // Body'yi preset.body sablonundan doldur, sonra tool'lari ekle
    final filledBody = TemplateEngine.fillBody(
      template: preset.body,
      apiKey: apiKey,
      modelName: modelName,
      conversationHistory: messages,
      temperature: temperature,
      systemPrompt: systemPrompt,
    );

    // Tool'lari enjekte et — built-in + enabled plugin'ler birlesik
    final bodyWithTools = Map<String, dynamic>.from(filledBody);
    bodyWithTools['tools'] = await ToolDefinitions.getMergedTools();
    bodyWithTools['tool_choice'] = 'auto';
    // Tool calling'de stream desteklemek karmasik, non-stream kullan
    bodyWithTools['stream'] = false;

    // Effort/reasoning enjeksiyonu — preset destekliyorsa saglayiciya gore dogru key
    if (preset.supportsEffort) {
      final effort = effortLevel;
      if (preset.providerName == 'anthropic') {
        // Anthropic: thinking.budget_tokens (low=2048, medium=8192, high=16384)
        final budget = effort == 'low' ? 2048 : (effort == 'high' ? 16384 : 8192);
        bodyWithTools['thinking'] = {'type': 'enabled', 'budget_tokens': budget};
        // Anthropic thinking modunda temperature 1 olmali
        bodyWithTools['temperature'] = 1;
      } else {
        // OpenAI/DeepSeek tarzi: reasoning_effort (low/medium/high)
        bodyWithTools['reasoning_effort'] = effort;
      }
    }

    // Gerekirse messages'i bodyWithTools['messages'] ile senkronize et
    // (TemplateEngine zaten {{MESSAGES}}'i doldurdu ama messages listesi guncelse)
    if (bodyWithTools.containsKey('messages')) {
      bodyWithTools['messages'] = messages;
    }

    final response = await _client.post(
      uri,
      headers: headers,
      body: jsonEncode(bodyWithTools),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      String msg = response.body;
      if (preset.errorJsonPath != null && preset.errorJsonPath!.isNotEmpty) {
        try {
          final decoded = jsonDecode(response.body);
          final resolved = JsonPathResolver.resolve(decoded, preset.errorJsonPath!);
          if (resolved != null) msg = resolved.toString();
        } catch (_) {}
      }
      throw ApiException(statusCode: response.statusCode, parsedMessage: msg);
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    return decoded;
  }

  void _assertSafeScheme(Uri uri) {
    if (uri.scheme != 'http') return;
    if (_isLocalOrPrivateHost(uri.host)) return;
    throw ApiException(
      statusCode: 0,
      parsedMessage:
          'Guvenli olmayan (http://) baglantilara yalnizca localhost/yerel ag (LAN) icin izin verilir.',
    );
  }

  bool _isLocalOrPrivateHost(String host) {
    if (host == 'localhost' || host == '127.0.0.1' || host == '::1') return true;
    final parts = host.split('.');
    if (parts.length != 4) return false;
    final octets = parts.map(int.tryParse).toList();
    if (octets.any((o) => o == null || o < 0 || o > 255)) return false;
    final a = octets[0]!, b = octets[1]!;
    if (a == 10) return true;
    if (a == 192 && b == 168) return true;
    if (a == 172 && b >= 16 && b <= 31) return true;
    return false;
  }
}
