import 'package:flutter/material.dart';

/// Reklam servisi arayüzü. Gerçek bir reklam SDK'sı (ör. google_mobile_ads)
/// ileride entegre edildiğinde bu arayüzü implemente eden yeni bir sınıf
/// yazılıp [NoOpAdService] yerine kullanılabilir.
abstract class AdService {
  Future<void> init();

  Future<void> showInterstitial();

  /// Banner reklamın gösterileceği yerde kullanılacak placeholder widget.
  /// Gerçek SDK entegre edilene kadar boş bir widget döner.
  Widget bannerPlaceholder(BuildContext context);
}

/// Henüz hiçbir reklam SDK'sı entegre edilmediği için tüm metodları
/// no-op olan varsayılan implementasyon.
class NoOpAdService implements AdService {
  @override
  Future<void> init() async {}

  @override
  Future<void> showInterstitial() async {}

  @override
  Widget bannerPlaceholder(BuildContext context) => const SizedBox.shrink();
}
