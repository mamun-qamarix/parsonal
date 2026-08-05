import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/network/api_client.dart';
import '../core/network/ws_client.dart';
import '../core/notifications/push_notification_service.dart';
import '../core/storage/secure_storage_service.dart';
import '../services/profile_service.dart';

enum SessionState {
  unknown,
  needsSetup,
  locked, // needs the PASSWORD (>1hr since last password entry, or never entered on this device yet)
  needsBiometric, // needs just a fingerprint/face/device-PIN tap (<1hr since last password entry)
  needsFaceVerify, // optional extra CompreFace step, only if the spouse turned it on
  authenticated,
  decoy,
}

class SessionProvider extends ChangeNotifier {
  static const _kAutoLockMinutesPref = 'auto_lock_minutes';

  // Password is required again once this long has passed since the last
  // successful password entry; a biometric tap covers every re-entry in
  // between (cold start, background resume, or idle auto-lock). See
  // DECISIONS.md #27.
  static const passwordWindow = Duration(hours: 1);

  SessionState state = SessionState.unknown;
  String? role;
  String? spouseId;
  String? deviceId;
  Uint8List? vmk;
  Timer? _autoLockTimer;
  int autoLockMinutes = 5;

  String? _pendingFaceChallengeToken;

  // "Intimate mode" -- a shared, whole-app green->blue accent swap either
  // spouse can flip from the chat screen, purely as an at-a-glance private
  // signal for the two of them. Backed by the generic AppSetting key/value
  // store server-side and kept in sync live over the same WS connection
  // chat already uses -- listened for here (not per-screen) since it's a
  // single global flag that affects the whole app's theme. See
  // DECISIONS.md.
  static const _kIntimateModeKey = 'intimate_mode_enabled';
  bool intimateMode = false;
  StreamSubscription? _globalWsSub;

  SessionProvider() {
    _globalWsSub = WsClient.instance.events.listen(_onGlobalWsEvent);
  }

  void _onGlobalWsEvent(Map<String, dynamic> data) {
    if (data['type'] == 'app_setting' && data['key'] == _kIntimateModeKey) {
      final on = data['value'] == 'true';
      if (on != intimateMode) {
        intimateMode = on;
        notifyListeners();
      }
    }
  }

  Future<void> loadIntimateMode() async {
    try {
      final value = await ProfileService().getSetting(
        _kIntimateModeKey,
        fallback: 'false',
      );
      intimateMode = value == 'true';
      notifyListeners();
    } catch (_) {
      // Best-effort -- worst case the app just starts in the green theme
      // until the next toggle or reconnect corrects it.
    }
  }

  Future<void> toggleIntimateMode() async {
    final next = !intimateMode;
    intimateMode = next; // optimistic; the WS echo-back will just confirm it
    notifyListeners();
    try {
      await ProfileService().setSetting(_kIntimateModeKey, next.toString());
    } catch (_) {
      intimateMode = !next; // revert on failure
      notifyListeners();
    }
  }

  set autoLockMinutesAndPersist(int value) {
    autoLockMinutes = value;
    SharedPreferences.getInstance().then(
      (prefs) => prefs.setInt(_kAutoLockMinutesPref, value),
    );
    notifyListeners();
  }

  Future<SessionState> _decideReentryState() async {
    final lastAuth = await SecureStorageService.instance.lastPasswordAuthAt;
    if (lastAuth != null &&
        DateTime.now().difference(lastAuth) < passwordWindow) {
      return SessionState.needsBiometric;
    }
    return SessionState.locked;
  }

  Future<void> _recordPasswordAuth() =>
      SecureStorageService.instance.setLastPasswordAuthAt(DateTime.now());

  Future<void> bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    autoLockMinutes = prefs.getInt(_kAutoLockMinutesPref) ?? 5;

    await ApiClient.instance.ensureConfigured();
    final hasSession = await SecureStorageService.instance.hasSession;
    if (!hasSession) {
      state = SessionState.needsSetup;
      notifyListeners();
      return;
    }
    role = await SecureStorageService.instance.role;
    spouseId = await SecureStorageService.instance.spouseId;
    deviceId = await SecureStorageService.instance.deviceId;
    final vmkB64 = await SecureStorageService.instance.vmkB64;
    if (vmkB64 != null) vmk = base64Decode(vmkB64);

    state = await _decideReentryState();
    notifyListeners();
  }

  Future<void> completeClaim({
    required String server,
    required String role,
    required String spouseId,
    required String deviceId,
    required String accessToken,
    required String refreshToken,
    required String vmkB64,
  }) async {
    await ApiClient.instance.configureBaseUrl(server);
    await SecureStorageService.instance.saveSession(
      server: server,
      accessToken: accessToken,
      refreshToken: refreshToken,
      vmkB64: vmkB64,
      role: role,
      spouseId: spouseId,
      deviceId: deviceId,
    );
    await _recordPasswordAuth();
    this.role = role;
    this.spouseId = spouseId;
    this.deviceId = deviceId;
    vmk = base64Decode(vmkB64);
    state = SessionState.authenticated;
    WsClient.instance.connect();
    PushNotificationService.instance.registerToken();
    loadIntimateMode();
    resetAutoLockTimer();
    notifyListeners();
  }

  void setPendingFaceChallenge(String token) {
    _pendingFaceChallengeToken = token;
    state = SessionState.needsFaceVerify;
    notifyListeners();
  }

  String? get pendingChallengeToken => _pendingFaceChallengeToken;

  void cancelFaceVerify() {
    _pendingFaceChallengeToken = null;
    state = SessionState.locked;
    notifyListeners();
  }

  /// Manual escape hatch from the biometric-unlock screen (fingerprint
  /// not working, not enrolled, etc.) -- falls back to typing the
  /// password even though the hourly window would otherwise have allowed
  /// just a biometric tap.
  void useFallbackPassword() {
    state = SessionState.locked;
    notifyListeners();
  }

  Future<void> completeLogin({
    required String accessToken,
    required String refreshToken,
    required String role,
    required String spouseId,
    String? deviceId,
  }) async {
    final server = await SecureStorageService.instance.server;
    final vmkB64 = await SecureStorageService.instance.vmkB64;
    await SecureStorageService.instance.saveSession(
      server: server ?? '',
      accessToken: accessToken,
      refreshToken: refreshToken,
      vmkB64: vmkB64 ?? '',
      role: role,
      spouseId: spouseId,
      deviceId: deviceId,
    );
    await _recordPasswordAuth();
    this.role = role;
    this.spouseId = spouseId;
    if (deviceId != null) this.deviceId = deviceId;
    _pendingFaceChallengeToken = null;
    state = SessionState.authenticated;
    WsClient.instance.connect();
    PushNotificationService.instance.registerToken();
    loadIntimateMode();
    resetAutoLockTimer();
    notifyListeners();
  }

  /// A successful biometric tap authenticates purely locally -- the tokens
  /// are already valid in secure storage from the last real password
  /// login (or the normal Dio refresh-token flow will silently renew the
  /// access token on the next API call if it's since expired). This never
  /// touches the server and does NOT reset the hourly password clock.
  void completeBiometricUnlock() {
    state = SessionState.authenticated;
    WsClient.instance.connect();
    resetAutoLockTimer();
    notifyListeners();
  }

  /// Starts a device-pairing login: another already-authenticated device
  /// handed us its role+VMK peer-to-peer (QR/paste, never through the
  /// server). We stash them locally right away so that by the time the
  /// normal password->(face) flow finishes and calls completeLogin,
  /// server/vmkB64 are already on disk for it to read. See DECISIONS.md.
  Future<void> beginPairing({
    required String server,
    required String role,
    required String spouseId,
    required String vmkB64,
  }) async {
    await ApiClient.instance.configureBaseUrl(server);
    await SecureStorageService.instance.saveSession(
      server: server,
      accessToken: '',
      refreshToken: '',
      vmkB64: vmkB64,
      role: role,
      spouseId: spouseId,
    );
    this.role = role;
    this.spouseId = spouseId;
    vmk = base64Decode(vmkB64);
    state = SessionState.locked;
    notifyListeners();
  }

  void enterDecoyMode() {
    state = SessionState.decoy;
    notifyListeners();
  }

  /// Only actually locks an already-authenticated session. Backgrounding
  /// the app mid-onboarding or mid-login must NOT force a jump to the
  /// locked screen -- there'd be no way back into the in-progress login
  /// step. See DECISIONS.md #14.
  Future<void> lock() async {
    if (state != SessionState.authenticated) return;
    _autoLockTimer?.cancel();
    WsClient.instance.disconnect();
    state = await _decideReentryState();
    notifyListeners();
  }

  void resetAutoLockTimer() {
    _autoLockTimer?.cancel();
    _autoLockTimer = Timer(Duration(minutes: autoLockMinutes), lock);
  }

  void registerActivity() {
    if (state == SessionState.authenticated) resetAutoLockTimer();
  }

  Future<void> logoutAndForget() async {
    _autoLockTimer?.cancel();
    WsClient.instance.disconnect();
    await SecureStorageService.instance.clearAll();
    role = null;
    spouseId = null;
    deviceId = null;
    vmk = null;
    intimateMode = false;
    state = SessionState.needsSetup;
    notifyListeners();
  }

  String get otherRole => role == 'husband' ? 'wife' : 'husband';

  @override
  void dispose() {
    _globalWsSub?.cancel();
    _autoLockTimer?.cancel();
    super.dispose();
  }
}
