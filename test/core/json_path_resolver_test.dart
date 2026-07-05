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

  group('resolveList', () {
    test('extracts field from each element with "data[].id" style path', () {
      final data = {
        'data': [
          {'id': 'gpt-4o-mini'},
          {'id': 'gpt-4o'},
        ],
      };
      expect(JsonPathResolver.resolveList(data, 'data[].id'),
          ['gpt-4o-mini', 'gpt-4o']);
    });

    test('extracts field from each element with "models[].name" style path', () {
      final data = {
        'models': [
          {'name': 'llama3'},
          {'name': 'mistral'},
        ],
      };
      expect(JsonPathResolver.resolveList(data, 'models[].name'),
          ['llama3', 'mistral']);
    });

    test('supports nested field after []', () {
      final data = {
        'models': [
          {'name': 'models/gemini-1.5-pro'},
          {'name': 'models/gemini-1.5-flash'},
        ],
      };
      expect(
        JsonPathResolver.resolveList(data, 'models[].name'),
        ['models/gemini-1.5-pro', 'models/gemini-1.5-flash'],
      );
    });

    test('skips null/missing elements instead of throwing', () {
      final data = {
        'data': [
          {'id': 'a'},
          {'other': 'x'},
          {'id': null},
        ],
      };
      expect(JsonPathResolver.resolveList(data, 'data[].id'), ['a']);
    });

    test('returns empty list when root list is missing', () {
      final data = {'foo': 'bar'};
      expect(JsonPathResolver.resolveList(data, 'data[].id'), isEmpty);
    });

    test('handles path without [] by resolving a plain list of scalars', () {
      final data = {
        'names': ['x', 'y', 'z'],
      };
      expect(JsonPathResolver.resolveList(data, 'names'), ['x', 'y', 'z']);
    });

    test('handles bare "[]" as root list', () {
      final data = [
        {'id': 'a'},
        {'id': 'b'},
      ];
      expect(JsonPathResolver.resolveList(data, '[].id'), ['a', 'b']);
    });
  });
}
