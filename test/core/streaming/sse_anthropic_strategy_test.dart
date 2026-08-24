import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ff_chat/core/streaming/sse_anthropic_strategy.dart';

Stream<List<int>> _byteStreamFrom(String text) async* {
  yield utf8.encode(text);
}

void main() {
  group('SseAnthropicStrategy', () {
    test('skips event lines and yields data JSON, stops at message_stop', () async {
      final strategy = SseAnthropicStrategy();
      final input = 'event: content_block_delta\n'
          'data: {"delta":"hi"}\n\n'
          'event: content_block_delta\n'
          'data: {"delta":"there"}\n\n'
          'event: message_stop\n'
          'data: {"delta":"ignored"}\n\n';

      final chunks = await strategy.parseChunks(_byteStreamFrom(input)).toList();

      expect(chunks, ['{"delta":"hi"}', '{"delta":"there"}']);
    });

    test('handles empty stream gracefully', () async {
      final strategy = SseAnthropicStrategy();
      final chunks = await strategy.parseChunks(_byteStreamFrom('')).toList();
      expect(chunks, isEmpty);
    });
  });
}
