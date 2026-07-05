/// Preset içindeki {{PLACEHOLDER}} yer tutucularını gerçek değerlerle doldurur.
class TemplateEngine {
  /// Değeri tüm placeholder değeriyle değiştirir (tip korunur: List/Map/num/vs).
  /// Placeholder bir string içinde başka metinle birlikteyse string olarak enjekte edilir.
  static final RegExp _placeholderPattern = RegExp(r'^\{\{(\w+)\}\}$');

  static Map<String, dynamic> fillBody({
    required Map<String, dynamic> template,
    required String? apiKey,
    required String modelName,
    required List<Map<String, dynamic>> conversationHistory,
    required double temperature,
    String? systemPrompt,
  }) {
    final values = _buildValueMap(
      apiKey: apiKey,
      modelName: modelName,
      conversationHistory: conversationHistory,
      temperature: temperature,
      systemPrompt: systemPrompt,
    );
    return _fillMap(template, values);
  }

  static Map<String, String> fillStringMap({
    required Map<String, String> template,
    required String? apiKey,
    required String modelName,
    String? systemPrompt,
  }) {
    final values = _buildValueMap(
      apiKey: apiKey,
      modelName: modelName,
      conversationHistory: const [],
      temperature: 0,
      systemPrompt: systemPrompt,
    );
    final result = <String, String>{};
    template.forEach((key, value) {
      final filled = _fillValue(value, values);
      result[key] = filled?.toString() ?? '';
    });
    return result;
  }

  static Map<String, dynamic> _buildValueMap({
    required String? apiKey,
    required String modelName,
    required List<Map<String, dynamic>> conversationHistory,
    required double temperature,
    String? systemPrompt,
  }) {
    return {
      'API_KEY': apiKey ?? '',
      'MODEL_NAME': modelName,
      'CONVERSATION_HISTORY': conversationHistory,
      'TEMPERATURE': temperature,
      'SYSTEM_PROMPT': systemPrompt ?? '',
    };
  }

  static Map<String, dynamic> _fillMap(
    Map<String, dynamic> map,
    Map<String, dynamic> values,
  ) {
    final result = <String, dynamic>{};
    map.forEach((key, value) {
      result[key] = _fillValue(value, values);
    });
    return result;
  }

  static List<dynamic> _fillList(
    List<dynamic> list,
    Map<String, dynamic> values,
  ) {
    return list.map((item) => _fillValue(item, values)).toList();
  }

  static dynamic _fillValue(dynamic value, Map<String, dynamic> values) {
    if (value is Map<String, dynamic>) {
      return _fillMap(value, values);
    }
    if (value is Map) {
      return _fillMap(Map<String, dynamic>.from(value), values);
    }
    if (value is List) {
      return _fillList(value, values);
    }
    if (value is String) {
      return _fillString(value, values);
    }
    return value;
  }

  static dynamic _fillString(String value, Map<String, dynamic> values) {
    final exactMatch = _placeholderPattern.firstMatch(value);
    if (exactMatch != null) {
      final key = exactMatch.group(1)!;
      if (values.containsKey(key)) {
        return values[key];
      }
      return value;
    }

    // Karışık string içinde birden fazla placeholder olabilir; string olarak değiştir.
    var result = value;
    values.forEach((key, val) {
      final pattern = '{{$key}}';
      if (result.contains(pattern)) {
        result = result.replaceAll(pattern, val?.toString() ?? '');
      }
    });
    return result;
  }
}
