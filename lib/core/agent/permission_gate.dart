import '../storage/app_settings_repository.dart';

/// Claude Code tarzı izin modları.
///
/// - planAsk: varsayılan, en güvenli. shell_exec + file_write + file_delete her seferinde sorar.
///            file_read/file_list düşük risk, otomatik geçer.
/// - acceptEdits: dosya okuma/yazma otomatik, sadece shell sorar (Claude Code'daki "accept edits" ile aynı).
/// - bypass: hiç sorma, tam otomatik (kullanıcı bilinçli açmalı, uyarı göster).
enum PermissionMode {
  planAsk,
  acceptEdits,
  bypass,
}

String permissionModeToString(PermissionMode mode) {
  switch (mode) {
    case PermissionMode.planAsk:
      return 'planAsk';
    case PermissionMode.acceptEdits:
      return 'acceptEdits';
    case PermissionMode.bypass:
      return 'bypass';
  }
}

PermissionMode permissionModeFromString(String? value) {
  switch (value) {
    case 'planAsk':
      return PermissionMode.planAsk;
    case 'acceptEdits':
      return PermissionMode.acceptEdits;
    case 'bypass':
      return PermissionMode.bypass;
    default:
      return PermissionMode.planAsk; // default en güvenli
  }
}

extension PermissionModeX on PermissionMode {
  String get displayName {
    switch (this) {
      case PermissionMode.planAsk:
        return 'Plan / Ask (Önerilen)';
      case PermissionMode.acceptEdits:
        return 'Accept Edits (Auto)';
      case PermissionMode.bypass:
        return 'Bypass (Riskli)';
    }
  }

  String get description {
    switch (this) {
      case PermissionMode.planAsk:
        return 'Her shell ve dosya yazma/silme öncesi onay ister. En güvenli.';
      case PermissionMode.acceptEdits:
        return 'Dosya okuma/yazma otomatik, sadece shell komutlarında sorar.';
      case PermissionMode.bypass:
        return 'Hiç sormadan çalışır. Dosya silebilir, komut çalıştırabilir!';
    }
  }

  /// Bu tool bu modda otomatik onay alır mı? false ise gate'ten geçmeli.
  bool requiresApproval(String toolName) {
    switch (this) {
      case PermissionMode.bypass:
        return false;
      case PermissionMode.acceptEdits:
        // Sadece shell yüksek risk — file_write/edit auto
        return toolName == 'shell_exec';
      case PermissionMode.planAsk:
        return toolName == 'shell_exec' || toolName == 'file_write' || toolName == 'file_edit' || toolName == 'file_delete';
    }
  }
}

/// Oturum bazlı izin gate'i — LLM tool çağırmadan önce buradan geçer.
///
/// Kullanım:
/// ```dart
/// final gate = PermissionGate.instance;
/// final approved = await gate.requestApproval('shell_exec', args, () => showDialog(...));
/// ```
class PermissionGate {
  PermissionGate._();
  static final PermissionGate instance = PermissionGate._();

  final _settingsRepo = AppSettingsRepository();

  // Oturum içinde "bu tool tipine bir daha sorma" için
  final Set<String> _sessionAllowed = {};

  /// Aktif mod (Hive'dan okunur, default planAsk)
  PermissionMode get mode => permissionModeFromString(_settingsRepo.getPermissionMode());

  Future<void> setMode(PermissionMode mode) async {
    await _settingsRepo.setPermissionMode(permissionModeToString(mode));
  }

  /// Bu tool için izin gerekiyor mu? (mode + session cache'e göre)
  bool needsApproval(String toolName) {
    if (_sessionAllowed.contains(toolName)) return false;
    return mode.requiresApproval(toolName);
  }

  /// Oturum için "bir daha sorma" işaretle
  void allowForSession(String toolName) {
    _sessionAllowed.add(toolName);
  }

  /// Oturumu sıfırla (yeni sohbet, uygulama restart)
  void clearSession() {
    _sessionAllowed.clear();
  }

  /// Tool'u çalıştırıp çalıştıramayacağını döndürür.
  /// [uiRequest] -> kullanıcıya dialog gösterip true/false döndüren callback.
  /// needsApproval false ise direkt true döner, uiRequest çağrılmaz.
  Future<bool> requestApproval(
    String toolName,
    Map<String, dynamic> args,
    Future<bool> Function() uiRequest,
  ) async {
    if (!needsApproval(toolName)) return true;
    return uiRequest();
  }

  /// Gelişmiş versiyon: editedArgs destekler.
  Future<PermissionResponse> requestApprovalWithEdit(
    String toolName,
    Map<String, dynamic> args,
    Future<PermissionResponse> Function() uiRequest,
  ) async {
    if (!needsApproval(toolName)) {
      return PermissionResponse(approved: true, editedArgs: args);
    }
    return uiRequest();
  }

  /// Reddedilen tool için LLM'e döndürülecek hata içeriği
  static String deniedContent(String toolName) =>
      'Kullanıcı reddetti (permission denied) — tool: $toolName. Lütfen alternatif öner veya açıklama yap.';
}

/// İzin dialog sonucu — Onayla / Reddet / Düzenle
class PermissionResponse {
  PermissionResponse({
    required this.approved,
    this.editedArgs,
    this.dontAskAgain = false,
  });

  final bool approved;
  final Map<String, dynamic>? editedArgs;
  final bool dontAskAgain;

  factory PermissionResponse.allow({Map<String, dynamic>? editedArgs, bool dontAskAgain = false}) =>
      PermissionResponse(approved: true, editedArgs: editedArgs, dontAskAgain: dontAskAgain);

  factory PermissionResponse.deny() => PermissionResponse(approved: false);
}
