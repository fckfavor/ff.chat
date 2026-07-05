import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ff_chat/core/streaming/sse_openai_strategy.dart';

Stream<List<int>> _byteStreamFrom(String text) async* {
  yield utf8.encode(text);
}

void main() {
  group('SseOpenAiStrategy', () {
    test('parses data lines and stops at [DONE]', () async {
      final strategy = SseOpenAiStrategy();
      final input = 'data: {"a":1}\n\n'
          'data: {"a":2}\n\n'
          'data: [DONE]\n\n'
          'data: {"a":3}\n\n';

      final chunks = await strategy.parseChunks(_byteStreamFrom(input)).toList();

      expect(chunks, ['{"a":1}', '{"a":2}']);
    });

    test('ignores empty lines and non-data lines', () async {
      final strategy = SseOpenAiStrategy();
      final input = '\n'
          'data: {"x":true}\n'
          '\n'
          'data: [DONE]\n';

      final chunks = await strategy.parseChunks(_byteStreamFrom(input)).toList();

      expect(chunks, ['{"x":true}']);
    });
  });
}
