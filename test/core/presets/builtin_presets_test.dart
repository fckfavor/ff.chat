import 'package:flutter_test/flutter_test.dart';

import 'package:ff_chat/core/models/preset.dart';
import 'package:ff_chat/core/presets/builtin_presets.dart';

void main() {
  test('builtin preset listesi 4 preset icerir ve id benzersizdir', () {
    expect(BuiltinPresets.all.length, 4);
    final ids = BuiltinPresets.all.map((p) => p.id).toSet();
    expect(ids.length, BuiltinPresets.all.length);
  });

  test('OpenAI uyumlu preset dogru ayarlanmis', () {
    final p = BuiltinPresets.openAiCompatible;
    expect(p.responseJsonPath, 'choices[0].message.content');
    expect(p.streamStrategy, StreamStrategy.sseOpenAi);
    expect(p.headers['Authorization'], contains('{{API_KEY}}'));
    expect(p.requiredFields, containsAll(['model', 'messages']));
  });

  test('Anthropic preset dogru ayarlanmis', () {
    final p = BuiltinPresets.anthropic;
    expect(p.responseJsonPath, 'content[0].text');
    expect(p.streamStrategy, StreamStrategy.sseAnthropic);
    expect(p.headers['x-api-key'], '{{API_KEY}}');
    expect(p.headers.containsKey('anthropic-version'), isTrue);
    expect(p.requiredFields, contains('max_tokens'));
  });

  test('Gemini preset dogru ayarlanmis', () {
    final p = BuiltinPresets.gemini;
    expect(p.urlQueryParams['key'], '{{API_KEY}}');
    expect(p.headers.containsKey('Authorization'), isFalse);
    expect(p.responseJsonPath, 'candidates[0].content.parts[0].text');
  });

  test('Ollama native preset NDJSON kullanir ve auth header icermez', () {
    final p = BuiltinPresets.ollamaNative;
    expect(p.streamStrategy, StreamStrategy.ndjson);
    expect(p.responseJsonPath, 'message.content');
    expect(p.headers.keys.any((k) => k.toLowerCase().contains('auth')), isFalse);
    expect(p.headers.keys.any((k) => k.toLowerCase().contains('key')), isFalse);
  });
}
