import 'dart:convert';

import 'stream_strategy.dart';

/// Newline-delimited JSON formatını parse eder (Ollama tarzı).
/// Her satır ayrı bir JSON objesidir.
class NdjsonStrategy implements StreamStrategy {
  @override
  Stream<String> parseChunks(Stream<List<int>> byteStream) async* {
    final lines = byteStream.transform(utf8.decoder).transform(const LineSplitter());

    await for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      yield line;
    }
  }
}
