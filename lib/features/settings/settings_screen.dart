import 'package:flutter/material.dart';

import '../../core/http/dynamic_http_client.dart';
import '../../core/models/preset.dart';
import '../../core/presets/builtin_presets.dart';
import '../../core/storage/app_settings_repository.dart';
import '../../core/storage/chat_repository.dart';
import '../../core/storage/secure_key_storage.dart';

/// Model seçim dropdown'ında "manuel gir" seçeneğini temsil eder.
const String _manualModelOption = '__manual__';

/// Ayarlar ekranı: API key, base URL, preset seçimi, model adı ve sıcaklık.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _secureStorage = SecureKeyStorage();
  final _settingsRepo = AppSettingsRepository();
  final _chatRepository = ChatRepository();
  final _httpClient = DynamicHttpClient();

  final _baseUrlController = TextEditingController();
  final _modelNameController = TextEditingController();
  final _apiKeyController = TextEditingController();

  List<Preset> _presets = [];
  String? _selectedPresetId;
  double _temperature = 0.7;
  bool _hasSavedApiKey = false;
  bool _apiKeyVisible = false;
  bool _loading = true;
  bool _testingConnection = false;

  // Bağlantı testinden (ya da knownModels'dan) gelen model listesi.
  List<String> _discoveredModels = [];
  // Kullanıcı dropdown'da "Diğer/Manuel gir" seçtiyse manuel metin alanı
  // gösterilir.
  bool _manualModelEntry = true;

  // Ayarlar tek bir "aktif" preset üzerinden tutuluyor; henüz preset
  // kaydedilmemişse bu id ile geçici olarak yönetilir.
  static const _defaultPresetId = 'default';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final customPresets = _chatRepository.getAllPresets();
    final customIds = customPresets.map((p) => p.id).toSet();
    _presets = [
      ...BuiltinPresets.all.where((p) => !customIds.contains(p.id)),
      ...customPresets,
    ];

    // Kayıtlı presetId artık _presets listesinde yoksa (silinmiş/uyumsuz id)
    // DropdownButtonFormField'ın "value listede yok" assert/hata ile
    // donmasını önlemek için ilk geçerli presete düş.
    final savedPresetId = _settingsRepo.getPresetId();
    final isSavedPresetValid =
        savedPresetId != null && _presets.any((p) => p.id == savedPresetId);
    _selectedPresetId = isSavedPresetValid
        ? savedPresetId
        : (_presets.isNotEmpty ? _presets.first.id : null);

    _baseUrlController.text = _settingsRepo.getBaseUrl() ?? '';
    _modelNameController.text = _settingsRepo.getModelName() ?? '';
    _temperature = _settingsRepo.getTemperature();

    if (_selectedPresetId != null) {
      final savedKey = await _secureStorage.getApiKey(_selectedPresetId!);
      _hasSavedApiKey = savedKey != null && savedKey.isNotEmpty;
    }

    _syncKnownModelsForSelectedPreset();

    setState(() => _loading = false);
  }

  Preset? get _selectedPreset {
    if (_selectedPresetId == null) return null;
    for (final p in _presets) {
      if (p.id == _selectedPresetId) return p;
    }
    return null;
  }

  /// Seçili preset otomatik keşif desteklemiyorsa ama statik knownModels
  /// listesi varsa (örn Anthropic), onu dropdown'a doldurur.
  void _syncKnownModelsForSelectedPreset() {
    final preset = _selectedPreset;
    if (preset != null &&
        (preset.modelsListEndpointTemplate == null ||
            preset.modelsListEndpointTemplate!.isEmpty) &&
        preset.knownModels != null &&
        preset.knownModels!.isNotEmpty) {
      _discoveredModels = preset.knownModels!;
      _manualModelEntry = !_discoveredModels.contains(_modelNameController.text) &&
          _modelNameController.text.isNotEmpty;
    } else {
      _discoveredModels = [];
      _manualModelEntry = true;
    }
  }

  String _friendlyErrorMessage(Object error) {
    if (error is ApiException) {
      switch (error.statusCode) {
        case 401:
        case 403:
          return 'API anahtarı geçersiz.';
        case 429:
          return 'Kota/rate limit aşıldı.';
        default:
          if (error.statusCode >= 500) {
            return 'Sunucu hatası (${error.statusCode}). Daha sonra tekrar deneyin.';
          }
          return 'Bağlantı hatası (${error.statusCode}): ${error.parsedMessage}';
      }
    }
    return 'Bağlantı başarısız: $error';
  }

  Future<void> _testConnection() async {
    final preset = _selectedPreset;
    if (preset == null) return;
    if (preset.modelsListEndpointTemplate == null ||
        preset.modelsListEndpointTemplate!.isEmpty) {
      return;
    }

    final baseUrl = _baseUrlController.text.trim();
    if (baseUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Önce Base URL girin.')),
      );
      return;
    }

    final apiKey = _apiKeyController.text.trim().isNotEmpty
        ? _apiKeyController.text.trim()
        : await _secureStorage.getApiKey(preset.id) ?? '';

    setState(() => _testingConnection = true);
    try {
      final rawModels = await _httpClient.fetchModelList(
        preset: preset,
        apiKey: apiKey,
        baseUrl: baseUrl,
      );
      // Gemini gibi bazı sağlayıcılar "models/gemini-..." formatında döner.
      final models =
          rawModels.map((m) => m.replaceFirst('models/', '')).toList();
      if (!mounted) return;
      setState(() {
        _discoveredModels = models;
        _manualModelEntry = models.isEmpty;
        _testingConnection = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.green,
          content: Text('Bağlantı başarılı, ${models.length} model bulundu.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _testingConnection = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text(_friendlyErrorMessage(e)),
        ),
      );
    }
  }

  Future<void> _saveApiKey() async {
    final presetId = _selectedPresetId ?? _defaultPresetId;
    final value = _apiKeyController.text.trim();
    if (value.isEmpty) return;
    await _secureStorage.saveApiKey(presetId, value);
    _apiKeyController.clear();
    setState(() {
      _hasSavedApiKey = true;
      _apiKeyVisible = false;
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('API anahtarı güvenli şekilde kaydedildi.')),
    );
  }

  Future<void> _deleteApiKey() async {
    final presetId = _selectedPresetId ?? _defaultPresetId;
    await _secureStorage.deleteApiKey(presetId);
    setState(() => _hasSavedApiKey = false);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('API anahtarı silindi.')),
    );
  }

  Future<void> _saveBaseUrl(String value) async {
    await _settingsRepo.setBaseUrl(value);
  }

  Future<void> _saveModelName(String value) async {
    await _settingsRepo.setModelName(value);
  }

  Future<void> _saveTemperature(double value) async {
    setState(() => _temperature = value);
    await _settingsRepo.setTemperature(value);
  }

  Future<void> _onPresetChanged(String? presetId) async {
    if (presetId == null) return;
    setState(() {
      _selectedPresetId = presetId;
      _syncKnownModelsForSelectedPreset();
    });
    await _settingsRepo.setPresetId(presetId);
    final savedKey = await _secureStorage.getApiKey(presetId);
    setState(() => _hasSavedApiKey = savedKey != null && savedKey.isNotEmpty);
  }

  void _onModelDropdownChanged(String? value) {
    if (value == null) return;
    if (value == _manualModelOption) {
      setState(() => _manualModelEntry = true);
      return;
    }
    setState(() {
      _manualModelEntry = false;
      _modelNameController.text = value;
    });
    _saveModelName(value);
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _modelNameController.dispose();
    _apiKeyController.dispose();
    _httpClient.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Ayarlar')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Preset',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          _presets.isEmpty
              ? const Text(
                  'Henüz hazır preset yok. Faz 5\'te OpenAI/DeepSeek/Ollama '
                  'gibi hazır şablonlar burada listelenecek.',
                  style: TextStyle(color: Colors.grey),
                )
              : DropdownButtonFormField<String>(
                  // Not: `_selectedPresetId`'nin her zaman `_presets` içinde
                  // geçerli bir id olduğu `_loadSettings`/`_onPresetChanged`
                  // tarafından garanti edilir; aksi halde bu widget "value
                  // listede yok" hatasıyla donar.
                  initialValue: _presets.any((p) => p.id == _selectedPresetId)
                      ? _selectedPresetId
                      : null,
                  decoration: const InputDecoration(border: OutlineInputBorder()),
                  items: _presets
                      .map(
                        (p) => DropdownMenuItem(value: p.id, child: Text(p.name)),
                      )
                      .toList(),
                  onChanged: _onPresetChanged,
                ),
          const SizedBox(height: 24),

          const Text('Base URL', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(
            controller: _baseUrlController,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'https://api.example.com/v1/chat/completions',
            ),
            onChanged: _saveBaseUrl,
          ),
          const SizedBox(height: 6),
          const Text(
            'Yerel sunucuya (Ollama/LM Studio) bağlanmak için bilgisayarınızın '
            'LAN IP\'sini kullanın (127.0.0.1 çalışmaz), aynı Wi-Fi ağında '
            'olmalısınız.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          if (_selectedPreset?.modelsListEndpointTemplate != null)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _testingConnection ? null : _testConnection,
                icon: _testingConnection
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.wifi_tethering),
                label: Text(
                  _testingConnection ? 'Test ediliyor...' : 'Bağlantıyı Test Et',
                ),
              ),
            ),
          const SizedBox(height: 24),

          const Text('Model Adı', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (_discoveredModels.isNotEmpty) ...[
            DropdownButtonFormField<String>(
              initialValue: _manualModelEntry
                  ? _manualModelOption
                  : (_discoveredModels.contains(_modelNameController.text)
                      ? _modelNameController.text
                      : _manualModelOption),
              decoration: const InputDecoration(border: OutlineInputBorder()),
              items: [
                ..._discoveredModels.map(
                  (m) => DropdownMenuItem(value: m, child: Text(m)),
                ),
                const DropdownMenuItem(
                  value: _manualModelOption,
                  child: Text('Diğer / Manuel gir'),
                ),
              ],
              onChanged: _onModelDropdownChanged,
            ),
            const SizedBox(height: 8),
          ],
          if (_manualModelEntry || _discoveredModels.isEmpty)
            TextField(
              controller: _modelNameController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'gpt-4o-mini / deepseek-chat / llama3',
              ),
              onChanged: _saveModelName,
            ),
          const SizedBox(height: 24),

          const Text('API Key', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (_hasSavedApiKey)
            Row(
              children: [
                const Icon(Icons.lock, size: 18, color: Colors.grey),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    '•••••••••••••••••• (kayıtlı)',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
                TextButton(onPressed: _deleteApiKey, child: const Text('Sil')),
              ],
            )
          else
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _apiKeyController,
                    obscureText: !_apiKeyVisible,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      hintText: 'sk-...',
                      suffixIcon: IconButton(
                        icon: Icon(
                          _apiKeyVisible ? Icons.visibility_off : Icons.visibility,
                        ),
                        onPressed: () =>
                            setState(() => _apiKeyVisible = !_apiKeyVisible),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(onPressed: _saveApiKey, child: const Text('Kaydet')),
              ],
            ),
          const SizedBox(height: 24),

          Text(
            'Temperature: ${_temperature.toStringAsFixed(2)}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Slider(
            value: _temperature,
            min: 0,
            max: 2,
            divisions: 20,
            label: _temperature.toStringAsFixed(2),
            onChanged: (value) => setState(() => _temperature = value),
            onChangeEnd: _saveTemperature,
          ),
        ],
      ),
    );
  }
}
