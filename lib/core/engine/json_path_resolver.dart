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

  /// "data[].id" gibi bir path'te "[]" ile işaretlenen noktada listeyi gezer,
  /// her elemana kalan path'i uygular ve sonuçları [List<String>] olarak
  /// toplar. Parse edilemeyen/null elemanlar atlanır.
  static List<String> resolveList(dynamic data, String path) {
    final results = <String>[];
    if (path.isEmpty) return results;

    final splitIndex = path.indexOf('[]');
    if (splitIndex == -1) {
      // "[]" yoksa doğrudan resolve edip tek elemanlı ya da liste sonucu
      // string listesine çevir.
      final resolved = resolve(data, path);
      if (resolved is List) {
        for (final item in resolved) {
          if (item != null) results.add(item.toString());
        }
      } else if (resolved != null) {
        results.add(resolved.toString());
      }
      return results;
    }

    final beforePath = path.substring(0, splitIndex);
    var afterPath = path.substring(splitIndex + 2);
    if (afterPath.startsWith('.')) {
      afterPath = afterPath.substring(1);
    }

    final listValue = beforePath.isEmpty ? data : resolve(data, beforePath);
    if (listValue is! List) return results;

    for (final element in listValue) {
      dynamic value;
      if (afterPath.isEmpty) {
        value = element;
      } else {
        value = resolve(element, afterPath);
      }
      if (value != null) {
        results.add(value.toString());
      }
    }

    return results;
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

      final bracketPart = part.substring(bracketIndex);
      final matches =
          RegExp(r'\[(\d+)\]').allMatches(bracketPart).toList();
      // "[]" (boş index) veya "[abc]" (sayısal olmayan) gibi geçersiz bir
      // bracket grubu varsa, segment'i sessizce atlamak yerine hemen
      // fark edilebilir bir hata fırlat. Aksi halde path fiilen kırpılır ve
      // resolve() hiçbir hata vermeden yanlışlıkla null döner.
      final validBracketGroups =
          RegExp(r'\[\d+\]').allMatches(bracketPart).length;
      final totalBracketGroups = RegExp(r'\[[^\]]*\]').allMatches(bracketPart).length;
      if (validBracketGroups != totalBracketGroups) {
        throw FormatException(
          'Geçersiz JSON path bracket ifadesi: "$part" (path: "$path")',
        );
      }
      for (final match in matches) {
        final index = int.parse(match.group(1)!);
        segments.add(_PathSegment(index: index));
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
