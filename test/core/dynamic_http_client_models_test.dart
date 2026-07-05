import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ff_chat/core/http/dynamic_http_client.dart';
import 'package:ff_chat/core/models/preset.dart';

Preset _openAiCompatiblePreset() {
  return Preset(
    id: 'openai-compatible',
    name: 'OpenAI uyumlu',
    providerName: 'openai_compatible',
    baseUrlTemplate: 'https://api.example.com/v1/chat/completions',
    headers: const {'Authorization': 'Bearer {{API_KEY}}'},
    body: const {},
    responseJsonPath: 'choices[0].message.content',
    errorJsonPath: 'error.message',
    modelsListEndpointTemplate: '{{BASE_URL}}/v1/models',
    modelsListJsonPath: 'data[].id',
  );
}

Preset _presetWithoutModelsEndpoint() {
  return Preset(
    id: 'anthropic',
    name: 'Anthropic',
    providerName: 'anthropic',
    baseUrlTemplate: 'https://api.anthropic.com/v1/messages',
    body: const {},
    responseJsonPath: 'content[0].text',
  );
}

void main() {
  group('DynamicHttpClient.fetchModelList', () {
    test('returns empty list when preset has no modelsListEndpointTemplate',
        () async {
      final client = DynamicHttpClient(
        client: MockClient((request) async {
          fail('İstek atılmamalıydı');
        }),
      );
      final models = await client.fetchModelList(
        preset: _presetWithoutModelsEndpoint(),
        apiKey: 'sk-test',
        baseUrl: 'https://api.anthropic.com',
      );
      expect(models, isEmpty);
    });

    test('fills BASE_URL/API_KEY placeholders and parses model ids', () async {
      Uri? capturedUri;
      Map<String, String>? capturedHeaders;
      final client = DynamicHttpClient(
        client: MockClient((request) async {
          capturedUri = request.url;
          capturedHeaders = request.headers;
          return http.Response(
            jsonEncode({
              'data': [
                {'id': 'gpt-4o-mini'},
                {'id': 'gpt-4o'},
              ],
            }),
            200,
          );
        }),
      );

      final models = await client.fetchModelList(
        preset: _openAiCompatiblePreset(),
        apiKey: 'sk-test',
        baseUrl: 'https://api.example.com',
      );

      expect(models, ['gpt-4o-mini', 'gpt-4o']);
      expect(capturedUri.toString(), 'https://api.example.com/v1/models');
      expect(capturedHeaders?['Authorization'], 'Bearer sk-test');
    });

    test('throws ApiException with 401 status on unauthorized', () async {
      final client = DynamicHttpClient(
        client: MockClient((request) async {
          return http.Response(
            jsonEncode({
              'error': {'message': 'Invalid API key'},
            }),
            401,
          );
        }),
      );

      expect(
        () => client.fetchModelList(
          preset: _openAiCompatiblePreset(),
          apiKey: 'bad-key',
          baseUrl: 'https://api.example.com',
        ),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 401),
        ),
      );
    });

    test('throws ApiException on 429 rate limit', () async {
      final client = DynamicHttpClient(
        client: MockClient((request) async {
          return http.Response('rate limited', 429);
        }),
      );

      expect(
        () => client.fetchModelList(
          preset: _openAiCompatiblePreset(),
          apiKey: 'sk-test',
          baseUrl: 'https://api.example.com',
        ),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 429),
        ),
      );
    });
  });
}
