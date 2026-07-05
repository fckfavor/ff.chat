import 'local_database.dart';

/// API key hariç uygulama ayarlarını (base URL, model, preset, sıcaklık)
/// Hive üzerinde saklayan basit repository. API key her zaman
/// [SecureKeyStorage] üzerinden ayrı tutulur.
class AppSettingsRepository {
  static const _baseUrlKey = 'base_url';
  static const _modelNameKey = 'model_name';
  static const _presetIdKey = 'preset_id';
  static const _temperatureKey = 'temperature';

  String? getBaseUrl() => LocalDatabase.settingsBox.get(_baseUrlKey) as String?;

  Future<void> setBaseUrl(String value) =>
      LocalDatabase.settingsBox.put(_baseUrlKey, value);

  String? getModelName() =>
      LocalDatabase.settingsBox.get(_modelNameKey) as String?;

  Future<void> setModelName(String value) =>
      LocalDatabase.settingsBox.put(_modelNameKey, value);

  String? getPresetId() => LocalDatabase.settingsBox.get(_presetIdKey) as String?;

  Future<void> setPresetId(String value) =>
      LocalDatabase.settingsBox.put(_presetIdKey, value);

  double getTemperature() =>
      (LocalDatabase.settingsBox.get(_temperatureKey) as num?)?.toDouble() ??
      0.7;

  Future<void> setTemperature(double value) =>
      LocalDatabase.settingsBox.put(_temperatureKey, value);
}
