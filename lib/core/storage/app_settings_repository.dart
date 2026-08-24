import 'local_database.dart';

/// API key hariç uygulama ayarlarını (base URL, model, preset, sıcaklık)
/// Hive üzerinde saklayan basit repository. API key her zaman
/// [SecureKeyStorage] üzerinden ayrı tutulur.
class AppSettingsRepository {
  static const _baseUrlKey = 'base_url';
  static const _modelNameKey = 'model_name';
  static const _presetIdKey = 'preset_id';
  static const _temperatureKey = 'temperature';
  static const _currentSessionIdKey = 'current_session_id';

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

  /// Aktif sohbet oturumunun kimliği. Uygulama yeniden açıldığında aynı
  /// oturumun mesajlarının geri yüklenebilmesi için kalıcı olarak saklanır.
  String? getCurrentSessionId() =>
      LocalDatabase.settingsBox.get(_currentSessionIdKey) as String?;

  Future<void> setCurrentSessionId(String value) =>
      LocalDatabase.settingsBox.put(_currentSessionIdKey, value);

  static const _permissionModeKey = 'permission_mode';

  String? getPermissionMode() =>
      LocalDatabase.settingsBox.get(_permissionModeKey) as String?;

  Future<void> setPermissionMode(String value) =>
      LocalDatabase.settingsBox.put(_permissionModeKey, value);

  static const _effortLevelKey = 'effort_level'; // low | medium | high

  String getEffortLevel() =>
      LocalDatabase.settingsBox.get(_effortLevelKey) as String? ?? 'medium';

  Future<void> setEffortLevel(String value) =>
      LocalDatabase.settingsBox.put(_effortLevelKey, value);
}
