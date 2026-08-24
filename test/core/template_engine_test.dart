import 'package:flutter_test/flutter_test.dart';
import 'package:ff_chat/core/engine/template_engine.dart';

void main() {
  test('fills body template with type-preserved conversation history', () {
    final template = {
      'model': '{{MODEL_NAME}}',
      'messages': '{{CONVERSATION_HISTORY}}',
      'temperature': '{{TEMPERATURE}}',
      'system': '{{SYSTEM_PROMPT}}',
    };
    final history = [
      {'role': 'user', 'content': 'hi'},
    ];

    final result = TemplateEngine.fillBody(
      template: template,
      apiKey: 'sk-test',
      modelName: 'gpt-x',
      conversationHistory: history,
      temperature: 0.7,
      systemPrompt: 'be nice',
    );

    expect(result['model'], 'gpt-x');
    expect(result['messages'], history);
    expect(result['temperature'], 0.7);
    expect(result['system'], 'be nice');
  });

  test('fills headers with api key', () {
    final headers = {'Authorization': 'Bearer {{API_KEY}}'};
    final result = TemplateEngine.fillStringMap(
      template: headers,
      apiKey: 'sk-abc',
      modelName: 'ignored',
    );
    expect(result['Authorization'], 'Bearer sk-abc');
  });

  test('recursively fills nested maps and lists', () {
    final template = {
      'nested': {
        'list': ['{{MODEL_NAME}}', 'static'],
      },
    };
    final result = TemplateEngine.fillBody(
      template: template,
      apiKey: null,
      modelName: 'model-1',
      conversationHistory: const [],
      temperature: 0,
    );
    expect(result['nested']['list'], ['model-1', 'static']);
  });
}
