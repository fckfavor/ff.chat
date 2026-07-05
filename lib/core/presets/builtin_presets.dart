import '../models/preset.dart';

/// Uygulamayla birlikte gelen hazır (built-in) preset tanımları.
///
/// Bu presetler kullanıcı tarafından düzenlenemez; kullanıcı sadece Base URL,
/// Model Adı ve API Key gibi alanları kendi ayarlarında doldurur. Şablonlarda
/// geçen {{API_KEY}} / {{MODEL}} / {{SYSTEM_PROMPT}} gibi yer tutucular istek
/// gönderilirken gerçek değerlerle değiştirilir.
class BuiltinPresets {
  BuiltinPresets._();

  /// OpenAI ve OpenAI uyumlu (DeepSeek, LM Studio, Ollama /v1/chat/completions)
  /// sağlayıcılar için ortak preset.
  static final Preset openAiCompatible = Preset(
    id: 'builtin_openai_compatible',
    name: 'OpenAI uyumlu (OpenAI / DeepSeek / LM Studio / Ollama v1)',
    providerName: 'openai_compatible',
    baseUrlTemplate: 'https://api.openai.com/v1/chat/completions',
    headers: const {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer {{API_KEY}}',
    },
    body: const {
      'model': '{{MODEL}}',
      'messages': '{{MESSAGES}}',
      'temperature': '{{TEMPERATURE}}',
    },
    responseJsonPath: 'choices[0].message.content',
    errorJsonPath: 'error.message',
    streamStrategy: StreamStrategy.sseOpenAi,
    requiredFields: const ['model', 'messages'],
    modelsListEndpointTemplate: '{{BASE_URL}}/v1/models',
    modelsListJsonPath: 'data[].id',
  );

  /// Anthropic (Claude) preset.
  static final Preset anthropic = Preset(
    id: 'builtin_anthropic',
    name: 'Anthropic (Claude)',
    providerName: 'anthropic',
    baseUrlTemplate: 'https://api.anthropic.com/v1/messages',
    headers: const {
      'Content-Type': 'application/json',
      'x-api-key': '{{API_KEY}}',
      'anthropic-version': '2023-06-01',
    },
    body: const {
      'model': '{{MODEL}}',
      'messages': '{{MESSAGES}}',
      'system': '{{SYSTEM_PROMPT}}',
      'max_tokens': '{{MAX_TOKENS}}',
      'temperature': '{{TEMPERATURE}}',
    },
    responseJsonPath: 'content[0].text',
    errorJsonPath: 'error.message',
    streamStrategy: StreamStrategy.sseAnthropic,
    requiredFields: const ['model', 'messages', 'max_tokens'],
    // Anthropic'in güvenilir bir public model-listesi endpoint'i olmadığı
    // için otomatik keşif yerine statik olarak bilinen model id'leri.
    knownModels: const [
      'claude-opus-4-20250514',
      'claude-sonnet-4-20250514',
      'claude-3-7-sonnet-20250219',
      'claude-3-5-haiku-20241022',
    ],
  );

  /// Google Gemini preset. API anahtarı header yerine URL query param olarak
  /// gönderilir.
  static final Preset gemini = Preset(
    id: 'builtin_gemini',
    name: 'Google Gemini',
    providerName: 'gemini',
    baseUrlTemplate:
        'https://generativelanguage.googleapis.com/v1beta/models/{{MODEL}}:generateContent',
    headers: const {
      'Content-Type': 'application/json',
    },
    urlQueryParams: const {
      'key': '{{API_KEY}}',
    },
    body: const {
      'contents': '{{GEMINI_CONTENTS}}',
      'generationConfig': {
        'temperature': '{{TEMPERATURE}}',
      },
    },
    responseJsonPath: 'candidates[0].content.parts[0].text',
    errorJsonPath: 'error.message',
    streamStrategy: StreamStrategy.none,
    requiredFields: const ['contents'],
    // Gemini modelleri "models/gemini-..." formatında döner; UI tarafında
    // "models/" prefix'i temizlenmelidir.
    modelsListEndpointTemplate: '{{BASE_URL}}/v1beta/models?key={{API_KEY}}',
    modelsListJsonPath: 'models[].name',
  );

  /// Ollama'nın kendi native /api/chat uç noktası. Yerel sunucu olduğu için
  /// herhangi bir auth header'ı gerekmez ve akış NDJSON (satır satır JSON)
  /// olarak gelir.
  static final Preset ollamaNative = Preset(
    id: 'builtin_ollama_native',
    name: 'Ollama (native /api/chat)',
    providerName: 'ollama',
    baseUrlTemplate: 'http://localhost:11434/api/chat',
    headers: const {
      'Content-Type': 'application/json',
    },
    body: const {
      'model': '{{MODEL}}',
      'messages': '{{MESSAGES}}',
      'stream': true,
      'options': {
        'temperature': '{{TEMPERATURE}}',
      },
    },
    responseJsonPath: 'message.content',
    errorJsonPath: 'error',
    streamStrategy: StreamStrategy.ndjson,
    requiredFields: const ['model', 'messages'],
    modelsListEndpointTemplate: '{{BASE_URL}}/api/tags',
    modelsListJsonPath: 'models[].name',
  );

  /// Ayarlar ekranındaki preset seçim listesinde gösterilecek hazır presetler.
  static final List<Preset> all = [
    openAiCompatible,
    anthropic,
    gemini,
    ollamaNative,
  ];
}
