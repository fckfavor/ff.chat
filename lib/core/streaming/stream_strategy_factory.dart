import '../models/preset.dart' as preset_model;
import 'ndjson_strategy.dart';
import 'sse_anthropic_strategy.dart';
import 'sse_openai_strategy.dart';
import 'stream_strategy.dart';

/// Preset.streamStrategy enum değerine göre doğru StreamStrategy
/// implementasyonunu döndürür.
class StreamStrategyFactory {
  static StreamStrategy? create(preset_model.StreamStrategy strategy) {
    switch (strategy) {
      case preset_model.StreamStrategy.sseOpenAi:
        return SseOpenAiStrategy();
      case preset_model.StreamStrategy.sseAnthropic:
        return SseAnthropicStrategy();
      case preset_model.StreamStrategy.ndjson:
        return NdjsonStrategy();
      case preset_model.StreamStrategy.none:
        return null;
    }
  }
}
