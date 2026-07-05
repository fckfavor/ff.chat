import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Preset başına API key'lerini güvenli şekilde saklar.
///
/// Android'de EncryptedSharedPreferences / Keystore, iOS'ta Keychain
/// otomatik olarak kullanılır (paketin varsayılan davranışı).
///
/// NOT: API key değerleri hiçbir zaman log/print edilmemelidir.
class SecureKeyStorage {
  SecureKeyStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  String _keyFor(String presetId) => 'api_key_$presetId';

  Future<void> saveApiKey(String presetId, String apiKey) async {
    await _storage.write(key: _keyFor(presetId), value: apiKey);
  }

  Future<String?> getApiKey(String presetId) {
    return _storage.read(key: _keyFor(presetId));
  }

  Future<void> deleteApiKey(String presetId) async {
    await _storage.delete(key: _keyFor(presetId));
  }
}
