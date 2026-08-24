import 'dart:convert';

import 'stream_strategy.dart';

/// Anthropic tarzı SSE formatını parse eder:
/// "event: content_block_delta\ndata: {json}\n\n" ... "event: message_stop"
///
/// "event:" satırları atlanır, yalnızca "data:" satırındaki JSON yayınlanır.
class SseAnthropicStrategy implements StreamStrategy {
  @override
  Stream<String> parseChunks(Stream<List<int>> byteStream) async* {
    final lines = byteStream.transform(utf8.decoder).transform(const LineSplitter());

    await for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      if (line.startsWith('event:')) {
        final eventName = line.substring(6).trim();
        if (eventName == 'message_stop') {
          return;
        }
        continue;
      }

      if (!line.startsWith('data:')) continue;

      final payload = line.substring(5).trim();
      if (payload.isEmpty) continue;

      yield payload;
    }
  }
}
