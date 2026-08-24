import 'dart:convert';

import 'stream_strategy.dart';

/// OpenAI tarzı SSE formatını parse eder:
/// "data: {json}\n\n" ... "data: [DONE]\n\n"
class SseOpenAiStrategy implements StreamStrategy {
  @override
  Stream<String> parseChunks(Stream<List<int>> byteStream) async* {
    final lines = byteStream.transform(utf8.decoder).transform(const LineSplitter());

    await for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      if (!line.startsWith('data:')) continue;

      final payload = line.substring(5).trim();
      if (payload == '[DONE]') {
        return;
      }
      if (payload.isEmpty) continue;

      yield payload;
    }
  }
}
