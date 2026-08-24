enum StreamStrategy { sseOpenAi, sseAnthropic, ndjson, none }

StreamStrategy streamStrategyFromString(String value) {
  switch (value) {
    case 'sseOpenAi':
      return StreamStrategy.sseOpenAi;
    case 'sseAnthropic':
      return StreamStrategy.sseAnthropic;
    case 'ndjson':
      return StreamStrategy.ndjson;
    default:
      return StreamStrategy.none;
  }
}

String streamStrategyToString(StreamStrategy strategy) {
  switch (strategy) {
    case StreamStrategy.sseOpenAi:
      return 'sseOpenAi';
    case StreamStrategy.sseAnthropic:
      return 'sseAnthropic';
    case StreamStrategy.ndjson:
      return 'ndjson';
    case StreamStrategy.none:
      return 'none';
  }
}

/// Bir AI sağlayıcısına yapılacak isteğin şablonunu tanımlar.
class Preset {
  final String id;
  final String name;
  final String providerName;
  final String baseUrlTemplate;
  final Map<String, dynamic> body;
  final Map<String, String> headers;
  final Map<String, String> urlQueryParams;
  final String responseJsonPath;
  final String? errorJsonPath;
  final StreamStrategy streamStrategy;
  final List<String> requiredFields;

  /// Model listesini otomatik keşfetmek için kullanılacak endpoint şablonu
  /// (örn "{{BASE_URL}}/v1/models"). Sağlayıcının güvenilir bir public model
  /// listesi endpoint'i yoksa (örn Anthropic) null bırakılır.
  final String? modelsListEndpointTemplate;

  /// [modelsListEndpointTemplate]'den dönen JSON gövdesindeki model
  /// isimlerini çıkarmak için kullanılan path (örn "data[].id").
  final String? modelsListJsonPath;

  /// Otomatik keşif mümkün olmayan sağlayıcılar için statik olarak bilinen
  /// model id'leri (örn Anthropic).
  final List<String>? knownModels;

  /// Stream (chunk) yanıtlarından içerik çıkarmak için kullanılan JSONPath.
  /// Birçok sağlayıcıda (OpenAI: "delta" vs "message", Anthropic: "delta"
  /// vs "content[]") stream chunk şeması, tam/non-stream yanıt şemasından
  /// FARKLIDIR. null ise [responseJsonPath] ile aynı kabul edilir (örn
  /// Ollama/Gemini gibi ikisi de aynı şemayı kullanan sağlayıcılar için).
  final String? streamResponseJsonPath;

  /// Reasoning/effort destekliyor mu? (OpenAI reasoning_effort, Anthropic thinking.budget_tokens)
  final bool supportsEffort;

  Preset({
    required this.id,
    required this.name,
    required this.providerName,
    required this.baseUrlTemplate,
    required this.body,
    this.headers = const {},
    this.urlQueryParams = const {},
    required this.responseJsonPath,
    this.errorJsonPath,
    this.streamStrategy = StreamStrategy.none,
    this.requiredFields = const [],
    this.modelsListEndpointTemplate,
    this.modelsListJsonPath,
    this.knownModels,
    this.streamResponseJsonPath,
    this.supportsEffort = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'providerName': providerName,
      'baseUrlTemplate': baseUrlTemplate,
      'body': body,
      'headers': headers,
      'urlQueryParams': urlQueryParams,
      'responseJsonPath': responseJsonPath,
      'errorJsonPath': errorJsonPath,
      'streamStrategy': streamStrategyToString(streamStrategy),
      'requiredFields': requiredFields,
      'modelsListEndpointTemplate': modelsListEndpointTemplate,
      'modelsListJsonPath': modelsListJsonPath,
      'knownModels': knownModels,
      'streamResponseJsonPath': streamResponseJsonPath,
      'supportsEffort': supportsEffort,
    };
  }

  factory Preset.fromJson(Map<String, dynamic> json) {
    return Preset(
      id: json['id'] as String,
      name: json['name'] as String,
      providerName: json['providerName'] as String,
      baseUrlTemplate: json['baseUrlTemplate'] as String,
      body: Map<String, dynamic>.from(json['body'] as Map? ?? {}),
      headers: Map<String, String>.from(json['headers'] as Map? ?? {}),
      urlQueryParams:
          Map<String, String>.from(json['urlQueryParams'] as Map? ?? {}),
      responseJsonPath: json['responseJsonPath'] as String,
      errorJsonPath: json['errorJsonPath'] as String?,
      streamStrategy:
          streamStrategyFromString(json['streamStrategy'] as String? ?? 'none'),
      requiredFields:
          List<String>.from(json['requiredFields'] as List? ?? const []),
      modelsListEndpointTemplate: json['modelsListEndpointTemplate'] as String?,
      modelsListJsonPath: json['modelsListJsonPath'] as String?,
      knownModels: json['knownModels'] == null
          ? null
          : List<String>.from(json['knownModels'] as List),
      streamResponseJsonPath: json['streamResponseJsonPath'] as String?,
      supportsEffort: json['supportsEffort'] as bool? ?? false,
    );
  }
}
