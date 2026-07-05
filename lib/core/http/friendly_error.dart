import 'dynamic_http_client.dart';

/// API çağrılarından dönen hataları kullanıcıya gösterilecek dostane bir
/// mesaja çevirir. Hem ChatScreen hem SettingsScreen tarafından ortak
/// kullanılır; mesaj metni tek bir yerden güncellenir.
String friendlyErrorMessage(Object error) {
  if (error is ApiException) {
    switch (error.statusCode) {
      case 401:
      case 403:
        return 'API anahtarı geçersiz veya eksik. Lütfen Ayarlar\'ı kontrol edin.';
      case 429:
        return 'İstek limiti aşıldı. Lütfen bir süre sonra tekrar deneyin.';
      default:
        if (error.statusCode >= 500) {
          return 'Sunucu tarafında bir sorun oluştu. Lütfen daha sonra tekrar deneyin.';
        }
        return 'İstek başarısız oldu (${error.statusCode}): ${error.parsedMessage}';
    }
  }
  return 'Bağlantı başarısız oldu. Lütfen ağ bağlantınızı ve ayarlarınızı kontrol edin.';
}
