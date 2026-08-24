/// Ham byte stream'ini, tamamlanmış JSON chunk string'lerine dönüştüren sözleşme.
///
/// Her strateji kendi framing formatını (SSE, ndjson, vb.) parse eder ve
/// yalnızca geçerli bir JSON objesi olarak decode edilebilecek string'leri
/// yayınlar. JSON path ile içerik çıkarma işi çağıran tarafın sorumluluğundadır.
abstract class StreamStrategy {
  Stream<String> parseChunks(Stream<List<int>> byteStream);
}
