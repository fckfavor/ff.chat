import 'dart:convert';

import 'package:http/http.dart' as http;

import '../engine/json_path_resolver.dart';
import '../engine/template_engine.dart';
import '../models/preset.dart';
import '../streaming/stream_strategy_factory.dart';

/// Bir API çağrısı 401/429/5xx gibi bir hata döndürdüğünde fırlatılır.
class ApiException implements Exception {
  final int statusCode;
  final String parsedMessage;

  ApiException({required this.statusCode, required this.parsedMessage});

  @override
  String toString() => 'ApiException($statusCode): $parsedMessage';
}

/// Preset + TemplateEngine + StreamStrategy'yi birleştirip gerçek bir HTTP
/// isteği yapan sınıf. Hem stream hem non-stream modları destekler.
class DynamicHttpClient {
  final http.Client _client;

  DynamicHttpClient({http.Client? client}) : _client = client ?? http.Client();

  Uri _buildUri(Preset preset, Map<String, String> filledQueryParams) {
    final uri = Uri.parse(preset.baseUrlTemplate);
    if (filledQueryParams.isEmpty) return uri;
    final mergedParams = Map<String, String>.from(uri.queryParameters)
      ..addAll(filledQueryParams);
    return uri.replace(queryParameters: mergedParams);
  }

  Map<String, dynamic> _buildFilledBody({
    required Preset preset,
    required String? apiKey,
    required String modelName,
    required List<Map<String, dynamic>> conversationHistory,
    required double temperature,
    String? systemPrompt,
  }) {
    return TemplateEngine.fillBody(
      template: preset.body,
      apiKey: apiKey,
      modelName: modelName,
      conversationHistory: conversationHistory,
      temperature: temperature,
      systemPrompt: systemPrompt,
    );
  }

  Map<String, String> _buildFilledHeaders({
    required Preset preset,
    required String? apiKey,
    required String modelName,
    String? systemPrompt,
  }) {
    final headers = TemplateEngine.fillStringMap(
      template: preset.headers,
      apiKey: apiKey,
      modelName: modelName,
      systemPrompt: systemPrompt,
    );
    headers.putIfAbsent('Content-Type', () => 'application/json');
    return headers;
  }

  /// Hata gövdesini errorJsonPath (varsa) ile parse edip [ApiException] fırlatır.
  Never _throwApiException(Preset preset, int statusCode, String rawBody) {
    String message = rawBody;
    if (preset.errorJsonPath != null && preset.errorJsonPath!.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawBody);
        final resolved = JsonPathResolver.resolve(decoded, preset.errorJsonPath!);
        if (resolved != null) {
          message = resolved.toString();
        }
      } catch (_) {
        // rawBody JSON değilse ya da path çözülemiyorsa ham body kullanılır.
      }
    }
    throw ApiException(statusCode: statusCode, parsedMessage: message);
  }

  /// Non-stream (tek seferlik) istek gönderir ve responseJsonPath ile
  /// içeriği çıkarır.
  Future<String> sendSingle({
    required Preset preset,
    required String? apiKey,
    required String modelName,
    required List<Map<String, dynamic>> conversationHistory,
    required double temperature,
    String? systemPrompt,
  }) async {
    final uri = _buildUri(
      preset,
      TemplateEngine.fillStringMap(
        template: preset.urlQueryParams,
        apiKey: apiKey,
        modelName: modelName,
        systemPrompt: systemPrompt,
      ),
    );
    final headers = _buildFilledHeaders(
      preset: preset,
      apiKey: apiKey,
      modelName: modelName,
      systemPrompt: systemPrompt,
    );
    final body = _buildFilledBody(
      preset: preset,
      apiKey: apiKey,
      modelName: modelName,
      conversationHistory: conversationHistory,
      temperature: temperature,
      systemPrompt: systemPrompt,
    );

    final response = await _client.post(
      uri,
      headers: headers,
      body: jsonEncode(body),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      _throwApiException(preset, response.statusCode, response.body);
    }

    final decoded = jsonDecode(response.body);
    final resolved = JsonPathResolver.resolve(decoded, preset.responseJsonPath);
    return resolved?.toString() ?? '';
  }

  /// Stream modunda istek gönderir; her chunk için responseJsonPath ile
  /// çıkarılmış metin parçalarını yayınlar.
  Stream<String> sendStream({
    required Preset preset,
    required String? apiKey,
    required String modelName,
    required List<Map<String, dynamic>> conversationHistory,
    required double temperature,
    String? systemPrompt,
  }) async* {
    final strategy = StreamStrategyFactory.create(preset.streamStrategy);
    if (strategy == null) {
      // Stream stratejisi tanımlı değilse tek seferlik cevabı tek chunk
      // olarak yayınla.
      final result = await sendSingle(
        preset: preset,
        apiKey: apiKey,
        modelName: modelName,
        conversationHistory: conversationHistory,
        temperature: temperature,
        systemPrompt: systemPrompt,
      );
      yield result;
      return;
    }

    final uri = _buildUri(
      preset,
      TemplateEngine.fillStringMap(
        template: preset.urlQueryParams,
        apiKey: apiKey,
        modelName: modelName,
        systemPrompt: systemPrompt,
      ),
    );
    final headers = _buildFilledHeaders(
      preset: preset,
      apiKey: apiKey,
      modelName: modelName,
      systemPrompt: systemPrompt,
    );
    final body = _buildFilledBody(
      preset: preset,
      apiKey: apiKey,
      modelName: modelName,
      conversationHistory: conversationHistory,
      temperature: temperature,
      systemPrompt: systemPrompt,
    );

    final request = http.Request('POST', uri)
      ..headers.addAll(headers)
      ..body = jsonEncode(body);

    final streamedResponse = await _client.send(request);

    if (streamedResponse.statusCode < 200 || streamedResponse.statusCode >= 300) {
      final rawBody = await streamedResponse.stream.bytesToString();
      _throwApiException(preset, streamedResponse.statusCode, rawBody);
    }

    await for (final chunk in strategy.parseChunks(streamedResponse.stream)) {
      try {
        final decoded = jsonDecode(chunk);
        final resolved = JsonPathResolver.resolve(decoded, preset.responseJsonPath);
        if (resolved != null) {
          yield resolved.toString();
        }
      } catch (_) {
        // Bozuk/eksik JSON chunk'ları sessizce atla.
      }
    }
  }

  /// [preset.modelsListEndpointTemplate] doluysa Base URL + API Key ile model
  /// listesini keşfeder. Endpoint tanımlı değilse boş liste döner (çağıran
  /// taraf manuel model adı girişine düşmeli).
  Future<List<String>> fetchModelList({
    required Preset preset,
    required String apiKey,
    required String baseUrl,
  }) async {
    final template = preset.modelsListEndpointTemplate;
    if (template == null || template.isEmpty) return [];

    final urlString = template
        .replaceAll('{{BASE_URL}}', baseUrl)
        .replaceAll('{{API_KEY}}', apiKey);
    final uri = Uri.parse(urlString);

    final headers = TemplateEngine.fillStringMap(
      template: preset.headers,
      apiKey: apiKey,
      modelName: '',
    );

    final response = await _client.get(uri, headers: headers);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      _throwApiException(preset, response.statusCode, response.body);
    }

    final decoded = jsonDecode(response.body);
    final path = preset.modelsListJsonPath;
    if (path == null || path.isEmpty) return [];
    return JsonPathResolver.resolveList(decoded, path);
  }

  void close() {
    _client.close();
  }
}
