/// Güncelleme kontrolü sonucu.
enum UpdateStatus {
  /// Güncelleme yok / gerekmiyor.
  none,

  /// Öneri niteliğinde, kullanıcı kapatabilir.
  soft,

  /// Zorunlu güncelleme, kullanıcı uygulamayı kullanamaz.
  force,
}

/// Uygulama sürüm kontrolü servisi.
///
/// Şimdilik sabit/mock minimumVersion ve latestVersion değerleriyle
/// çalışıyor. İleride Firebase Remote Config buraya bağlanacak:
/// minimumVersion ve latestVersion Remote Config parametrelerinden
/// okunacak.
class UpdateCheckService {
  UpdateCheckService({
    this.minimumVersion = '1.0.0',
    this.latestVersion = '1.0.0',
  });

  /// Bu sürümün altındaki her şey zorunlu güncellemeye zorlanır.
  final String minimumVersion;

  /// Kullanıcıya önerilecek en güncel sürüm.
  final String latestVersion;

  Future<UpdateStatus> checkForUpdate(String currentVersion) async {
    // TODO: Firebase Remote Config'den minimumVersion/latestVersion çek.
    final current = _parseVersion(currentVersion);
    final minimum = _parseVersion(minimumVersion);
    final latest = _parseVersion(latestVersion);

    if (_compare(current, minimum) < 0) {
      return UpdateStatus.force;
    }
    if (_compare(current, latest) < 0) {
      return UpdateStatus.soft;
    }
    return UpdateStatus.none;
  }

  List<int> _parseVersion(String version) {
    return version
        .split('.')
        .map((part) => int.tryParse(part) ?? 0)
        .toList();
  }

  /// a < b ise negatif, a == b ise 0, a > b ise pozitif döner.
  int _compare(List<int> a, List<int> b) {
    final length = a.length > b.length ? a.length : b.length;
    for (var i = 0; i < length; i++) {
      final aPart = i < a.length ? a[i] : 0;
      final bPart = i < b.length ? b[i] : 0;
      if (aPart != bPart) return aPart - bPart;
    }
    return 0;
  }
}
