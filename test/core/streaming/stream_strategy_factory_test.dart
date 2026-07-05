import 'package:flutter_test/flutter_test.dart';
import 'package:ff_chat/core/models/preset.dart';
import 'package:ff_chat/core/streaming/ndjson_strategy.dart';
import 'package:ff_chat/core/streaming/sse_anthropic_strategy.dart';
import 'package:ff_chat/core/streaming/sse_openai_strategy.dart';
import 'package:ff_chat/core/streaming/stream_strategy_factory.dart';

void main() {
  group('StreamStrategyFactory', () {
    test('returns correct strategy for each enum value', () {
      expect(StreamStrategyFactory.create(StreamStrategy.sseOpenAi),
          isA<SseOpenAiStrategy>());
      expect(StreamStrategyFactory.create(StreamStrategy.sseAnthropic),
          isA<SseAnthropicStrategy>());
      expect(StreamStrategyFactory.create(StreamStrategy.ndjson),
          isA<NdjsonStrategy>());
      expect(StreamStrategyFactory.create(StreamStrategy.none), isNull);
    });
  });
}
