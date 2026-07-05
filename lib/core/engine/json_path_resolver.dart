/// Basit bir JSONPath alt kümesini çözer: dot notation + array index.
/// Örnek: "choices[0].message.content", "content[0].text"
class JsonPathResolver {
  static dynamic resolve(dynamic data, String path) {
    if (path.isEmpty) return null;

    final segments = _parsePath(path);
    dynamic current = data;

    for (final segment in segments) {
      if (current == null) return null;

      if (segment.key != null) {
        if (current is Map && current.containsKey(segment.key)) {
          current = current[segment.key];
        } else {
          return null;
        }
      }

      if (segment.index != null) {
        if (current is List &&
            segment.index! >= 0 &&
            segment.index! < current.length) {
          current = current[segment.index!];
        } else {
          return null;
        }
      }
    }

    return current;
  }

  static List<_PathSegment> _parsePath(String path) {
    final segments = <_PathSegment>[];
    final parts = path.split('.');

    for (final part in parts) {
      if (part.isEmpty) continue;

      final bracketIndex = part.indexOf('[');
      if (bracketIndex == -1) {
        segments.add(_PathSegment(key: part));
        continue;
      }

      final key = part.substring(0, bracketIndex);
      if (key.isNotEmpty) {
        segments.add(_PathSegment(key: key));
      }

      final matches = RegExp(r'\[(\d+)\]').allMatches(part.substring(bracketIndex));
      for (final match in matches) {
        final index = int.tryParse(match.group(1)!);
        if (index != null) {
          segments.add(_PathSegment(index: index));
        }
      }
    }

    return segments;
  }
}

class _PathSegment {
  final String? key;
  final int? index;

  _PathSegment({this.key, this.index});
}
