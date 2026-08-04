import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/network/api_client.dart';
import '../core/network/ws_client.dart';
import '../core/storage/secure_storage_service.dart';
import '../services/auth_service.dart';

enum SessionState {
  unknown,
  needsSetup,
  needsTotpSetup,
  locked,
  needsTotpVerify,
  needsLoginTotpSetup,
  needsFaceVerify,
  authenticated,
  decoy,
}

class SessionProvider extends ChangeNotifier {
  static const _kAutoLockMinutesPref = 'auto_lock_minutes';

  SessionState state = SessionState.unknown;
  String? role;
  String? spouseId;
  String? deviceId;
  Uint8List? vmk;
  Timer? _autoLockTimer;
  int autoLockMinutes = 5;

  // Set right after claim, consumed by TotpSetupScreen, then cleared.
  String? pendingTotpSecret;
  String? pendingTotpProvisioningUri;

  String? _pendingTotpChallengeToken;
  String? _pendingFaceChallengeToken;

  // Set when /auth/login/password comes back in "setup" mode -- this
  // device has never confirmed its own authenticator entry yet (new
  // install, or newly paired onto an already-claimed role). See
  // DECISIONS.md #21.
  String? _pendingLoginTotpSetupChallengeToken;
  String? pendingLoginTotpSetupSecret;
  String? pendingLoginTotpSetupUri;

  set autoLockMinutesAndPersist(int value) {
    autoLockMinutes = value;
    SharedPreferences.getInstance().then((prefs) => prefs.setInt(_kAutoLockMinutesPref, value));
    notifyListeners();
  }

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

    // Recover an onboarding that was interrupted (e.g. backgrounded to
    // install/open an authenticator app) before TOTP was confirmed --
    // otherwise this would land on a login screen that can never succeed.
    // See DECISIONS.md #14.
    try {
      final me = await AuthService().getMe();
      if (me['totp_confirmed'] != true) {
        final info = await AuthService().getTotpSetupInfo();
        pendingTotpSecret = info['totp_secret'];
        pendingTotpProvisioningUri = info['totp_provisioning_uri'];
        state = SessionState.needsTotpSetup;
        notifyListeners();
        return;
      }
    } catch (_) {
      // Server unreachable or token issue -- fall through to the normal
      // locked screen; login will surface any real problem specifically.
    }

    state = SessionState.locked;
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
    required String totpSecret,
    required String totpProvisioningUri,
  }) async {
    await ApiClient.instance.configureBaseUrl(server);
    await SecureStorageService.instance.saveSession(
      server: server, accessToken: accessToken, refreshToken: refreshToken, vmkB64: vmkB64, role: role, spouseId: spouseId, deviceId: deviceId,
    );
    this.role = role;
    this.spouseId = spouseId;
    this.deviceId = deviceId;
    vmk = base64Decode(vmkB64);
    pendingTotpSecret = totpSecret;
    pendingTotpProvisioningUri = totpProvisioningUri;
    state = SessionState.needsTotpSetup;
    notifyListeners();
  }

  /// Called once /auth/totp/setup-confirm succeeds during onboarding --
  /// the access/refresh tokens from claim are already valid, so this goes
  /// straight to the home screen (matches the old face-enroll-then-home
  /// behavior, just with TOTP as the confirmed factor).
  void completeTotpSetup() {
    pendingTotpSecret = null;
    pendingTotpProvisioningUri = null;
    state = SessionState.authenticated;
    WsClient.instance.connect();
    resetAutoLockTimer();
    notifyListeners();
  }

  void setPendingTotpChallenge(String token) {
    _pendingTotpChallengeToken = token;
    state = SessionState.needsTotpVerify;
    notifyListeners();
  }

  String? get pendingTotpChallengeToken => _pendingTotpChallengeToken;

  void cancelTotpVerify() {
    _pendingTotpChallengeToken = null;
    state = SessionState.locked;
    notifyListeners();
  }

  void setPendingLoginTotpSetup({required String challengeToken, required String secret, required String uri}) {
    _pendingLoginTotpSetupChallengeToken = challengeToken;
    pendingLoginTotpSetupSecret = secret;
    pendingLoginTotpSetupUri = uri;
    state = SessionState.needsLoginTotpSetup;
    notifyListeners();
  }

  String? get pendingLoginTotpSetupChallengeToken => _pendingLoginTotpSetupChallengeToken;

  void cancelLoginTotpSetup() {
    _pendingLoginTotpSetupChallengeToken = null;
    pendingLoginTotpSetupSecret = null;
    pendingLoginTotpSetupUri = null;
    state = SessionState.locked;
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
      server: server ?? '', accessToken: accessToken, refreshToken: refreshToken, vmkB64: vmkB64 ?? '', role: role, spouseId: spouseId, deviceId: deviceId,
    );
    this.role = role;
    this.spouseId = spouseId;
    if (deviceId != null) this.deviceId = deviceId;
    _pendingTotpChallengeToken = null;
    _pendingFaceChallengeToken = null;
    _pendingLoginTotpSetupChallengeToken = null;
    pendingLoginTotpSetupSecret = null;
    pendingLoginTotpSetupUri = null;
    state = SessionState.authenticated;
    WsClient.instance.connect();
    resetAutoLockTimer();
    notifyListeners();
  }

  /// Starts a device-pairing login: another already-authenticated device
  /// handed us its role+VMK peer-to-peer (QR/paste, never through the
  /// server). We stash them locally right away so that by the time the
  /// normal password->TOTP->(face) flow finishes and calls completeLogin,
  /// server/vmkB64 are already on disk for it to read. See DECISIONS.md.
  Future<void> beginPairing({
    required String server,
    required String role,
    required String spouseId,
    required String vmkB64,
  }) async {
    await ApiClient.instance.configureBaseUrl(server);
    await SecureStorageService.instance.saveSession(
      server: server, accessToken: '', refreshToken: '', vmkB64: vmkB64, role: role, spouseId: spouseId,
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
  /// locked screen -- there'd be no way back into TOTP setup / the
  /// in-progress login step. See DECISIONS.md #14.
  void lock() {
    if (state != SessionState.authenticated) return;
    _autoLockTimer?.cancel();
    WsClient.instance.disconnect();
    state = SessionState.locked;
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
    state = SessionState.needsSetup;
    notifyListeners();
  }

  String get otherRole => role == 'husband' ? 'wife' : 'husband';
}
