import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ff_chat/core/streaming/ndjson_strategy.dart';

Stream<List<int>> _byteStreamFrom(String text) async* {
  yield utf8.encode(text);
}

void main() {
  group('NdjsonStrategy', () {
    test('parses each line as a separate JSON chunk', () async {
      final strategy = NdjsonStrategy();
      final input = '{"a":1}\n'
          '{"a":2}\n'
          '\n'
          '{"a":3}\n';

      final chunks = await strategy.parseChunks(_byteStreamFrom(input)).toList();

      expect(chunks, ['{"a":1}', '{"a":2}', '{"a":3}']);
    });
  });
}
