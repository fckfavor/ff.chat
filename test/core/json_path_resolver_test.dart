import 'package:flutter_test/flutter_test.dart';
import 'package:ff_chat/core/engine/json_path_resolver.dart';

void main() {
  test('resolves nested map + array index path', () {
    final data = {
      'choices': [
        {
          'message': {'content': 'hello'},
        },
      ],
    };
    expect(JsonPathResolver.resolve(data, 'choices[0].message.content'),
        'hello');
  });

  test('resolves anthropic-style content array path', () {
    final data = {
      'content': [
        {'text': 'world'},
      ],
    };
    expect(JsonPathResolver.resolve(data, 'content[0].text'), 'world');
  });

  test('returns null for missing path instead of throwing', () {
    final data = {'a': 1};
    expect(JsonPathResolver.resolve(data, 'b.c[0].d'), isNull);
    expect(JsonPathResolver.resolve(data, 'a[0]'), isNull);
  });
}
