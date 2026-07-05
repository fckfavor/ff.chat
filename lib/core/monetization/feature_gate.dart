/// Feature flag kontrolü için basit servis.
///
/// Şu an tüm feature'lar için local bir varsayılan Map kullanılıyor.
/// İleride Firebase Remote Config buraya bağlanacak: [refresh] Remote
/// Config'den güncel değerleri çekip [updateOverrides] ile uygulayacak.
class FeatureGateService {
  FeatureGateService._();

  static final FeatureGateService instance = FeatureGateService._();

  /// Varsayılan feature durumları. Burada tanımlı olmayan bir key
  /// sorulursa [isEnabled] true döner (MVP'de her şey açık).
  final Map<String, bool> _defaults = {};

  Map<String, bool> _overrides = {};

  bool isEnabled(String featureKey) {
    return _overrides[featureKey] ?? _defaults[featureKey] ?? true;
  }

  /// İleride Firebase Remote Config buraya bağlanacak.
  /// Şimdilik no-op; gerçek entegrasyonda Remote Config'den
  /// değerler çekilip [updateOverrides] çağrılacak.
  Future<void> refresh() async {
    // TODO: Firebase Remote Config entegrasyonu.
  }

  void updateOverrides(Map<String, bool> overrides) {
    _overrides = {..._overrides, ...overrides};
  }
}
