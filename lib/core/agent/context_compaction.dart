import 'dart:convert';

/// Context compaction — conversation history'i token penceresine sigdirir.
///
/// MVP: LLM ozeti yerine sliding window + placeholder (hizli, API maliyeti yok).
/// Ileride: eski segmenti ozetletip ChatSession.summary'e yazma eklenebilir.
class ContextCompactor {
  ContextCompactor._();
  static final ContextCompactor instance = ContextCompactor._();

  // Varsayilan limitler — preset'e gore ayarlanabilir (Ollama 4k vs OpenAI 128k)
  static const int defaultMaxTokens = 120000;
  static const double compactionThresholdRatio = 0.8; // %80'de compact
  static const int keepRecentMessages = 20;
  static const int keepRecentTokens = 30000;

  int estimateTokens(String text) {
    if (text.isEmpty) return 0;
    // ~4 char = 1 token (kaba ama yeterli), + overhead
    return (text.length / 4).ceil() + 2;
  }

  int estimateMessagesTokens(List<Map<String, dynamic>> messages) {
    int total = 0;
    for (final m in messages) {
      final content = m['content']?.toString() ?? '';
      total += estimateTokens(content);
      // tool_calls ve tool_call_id de token harcar
      final toolCalls = m['tool_calls'];
      if (toolCalls != null) {
        total += estimateTokens(jsonEncode(toolCalls));
      }
      final toolCallId = m['tool_call_id']?.toString() ?? '';
      if (toolCallId.isNotEmpty) total += estimateTokens(toolCallId);
      total += 4; // role overhead
    }
    return total;
  }

  /// Gecmis compact gerekiyor mu?
  bool needsCompaction(List<Map<String, dynamic>> messages, {int maxTokens = defaultMaxTokens}) {
    return estimateMessagesTokens(messages) > (maxTokens * compactionThresholdRatio);
  }

  /// Sliding window compaction — eski kisimlari at, ortaya placeholder koy.
  /// Tool pair butunlugunu korumak icin keepRecent'in basladigi index'i
  /// user mesajina hizalar (tool mesajinin ortasindan kesme).
  List<Map<String, dynamic>> compactHistory(
    List<Map<String, dynamic>> history, {
    String? systemPrompt,
    int maxTokens = defaultMaxTokens,
    int keepRecent = keepRecentMessages,
  }) {
    if (history.isEmpty) return history;
    final totalTokens = estimateMessagesTokens(history);
    if (totalTokens <= maxTokens * compactionThresholdRatio) return history;

    // System prompt token'i ayri hesapla (history'de degil, ama budget'e dahil)
    final systemTokens = systemPrompt != null ? estimateTokens(systemPrompt) : 0;
    final budgetForHistory = (maxTokens * compactionThresholdRatio).toInt() - systemTokens;

    // Sondan baslayarak keepRecent kadar veya token budget kadar al
    final recent = <Map<String, dynamic>>[];
    int recentTokens = 0;
    int idx = history.length - 1;
    int keptCount = 0;

    while (idx >= 0 && keptCount < keepRecent && recentTokens < keepRecentTokens && recentTokens < budgetForHistory) {
      final msg = history[idx];
      final tokens = estimateTokens(msg['content']?.toString() ?? '') + 8;
      if (recentTokens + tokens > budgetForHistory && recent.isNotEmpty) break;
      // Tool butunlugunu koru: eger bu mesaj 'tool' ise, ondan onceki 'assistant' tool_calls'i de al
      // Simplistic: user mesajinda dur, tool ortasinda kesme
      if (msg['role'] == 'tool' && keptCount == 0) {
        // tool mesajiyla baslama, bir onceki assistant'i da almaya calis
        // ama simdilik al, loop bir sonraki iterasyonda assistant'i da ekleyecek
      }
      recent.insert(0, msg);
      recentTokens += tokens;
      keptCount++;
      idx--;
    }

    // Tool pair butunlugu: pencere assistant/tool ortasinda kesilmemeli
    // OpenAI kural: her tool_call_id'nin karsilik gelen tool mesaji olmali
    // Cozum: pencereyi user/system'da baslat, tool/assistant ortasinda kesme
    // Eger recent tool veya tool_calls'li assistant ile basliyorsa, user'a kadar geri git
    while (recent.isNotEmpty && idx >= 0) {
      final firstRole = recent.first['role']?.toString() ?? '';
      final firstHasToolCalls = recent.first['tool_calls'] != null;
      final startsInMiddle = firstRole == 'tool' || firstHasToolCalls;
      if (!startsInMiddle) break;
      // Guvenlik: cok fazla geri gitmeyi sinirla (keepRecent + 5)
      if (recent.length >= keepRecent + 5) break;
      final prev = history[idx];
      recent.insert(0, prev);
      idx--;
      // Eger eklenen de tool/assistant ise devam et (tum blogu alana kadar)
      // Dongu basi tekrar kontrol edecek
    }
    // Ek guvenlik: eger hala tool ile basliyorsa ve history'de cok geride kaldik, o mesaji at (yarim blogu sil)
    // Boylece 400 hatasi yerine biraz daha fazla kirpma yapmis oluruz
    if (recent.isNotEmpty && recent.first['role'] == 'tool') {
      // Ilk tool blogunu tamamen at, user'dan baslat
      while (recent.isNotEmpty && recent.first['role'] == 'tool') {
        recent.removeAt(0);
      }
      if (recent.isNotEmpty && recent.first['role'] == 'assistant' && recent.first['tool_calls'] != null) {
        recent.removeAt(0);
      }
    }

    final droppedCount = history.length - recent.length;
    if (droppedCount <= 0) return recent;

    final placeholder = {
      'role': 'system',
      'content': '[Conversation compacted: $droppedCount eski mesaj atildi, ${recent.length} son mesaj korundu. '
          'Toplam ${history.length} mesajdan ${totalTokens} token -> ~${recentTokens} token. '
          'Eski baglam ozetlenmedi, sadece kirpildi.]',
    };

    return [placeholder, ...recent];
  }

  /// Oturum icin compact — session summary'yi de hesaba katabilir (ileride).
  List<Map<String, dynamic>> compactForSession(
    List<Map<String, dynamic>> history, {
    String? systemPrompt,
    int maxTokens = defaultMaxTokens,
  }) {
    return compactHistory(history, systemPrompt: systemPrompt, maxTokens: maxTokens);
  }
}
