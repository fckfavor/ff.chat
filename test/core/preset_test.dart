import 'package:flutter_test/flutter_test.dart';
import 'package:ff_chat/core/models/preset.dart';

void main() {
  test('round-trips through toJson/fromJson', () {
    final preset = Preset(
      id: 'openai-chat',
      name: 'OpenAI Chat',
      providerName: 'OpenAI',
      baseUrlTemplate: 'https://api.openai.com/v1/chat/completions',
      body: {
        'model': '{{MODEL_NAME}}',
        'messages': '{{CONVERSATION_HISTORY}}',
      },
      headers: {'Authorization': 'Bearer {{API_KEY}}'},
      urlQueryParams: {},
      responseJsonPath: 'choices[0].message.content',
      errorJsonPath: 'error.message',
      streamStrategy: StreamStrategy.sseOpenAi,
      requiredFields: ['max_tokens'],
    );

    final json = preset.toJson();
    final restored = Preset.fromJson(json);

    expect(restored.id, preset.id);
    expect(restored.streamStrategy, StreamStrategy.sseOpenAi);
    expect(restored.requiredFields, ['max_tokens']);
    expect(restored.headers['Authorization'], 'Bearer {{API_KEY}}');
  });
}
