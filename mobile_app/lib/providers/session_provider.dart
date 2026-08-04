import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/network/api_client.dart';
import '../core/network/ws_client.dart';
import '../core/storage/secure_storage_service.dart';

enum SessionState { unknown, needsSetup, needsFaceEnroll, locked, needsFaceVerify, authenticated, decoy }

class SessionProvider extends ChangeNotifier {
  static const _kAutoLockMinutesPref = 'auto_lock_minutes';

  SessionState state = SessionState.unknown;
  String? role;
  String? spouseId;
  Uint8List? vmk;
  bool faceEnrolled = false;
  String? _pendingChallengeToken;
  Timer? _autoLockTimer;
  int autoLockMinutes = 5;

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
    faceEnrolled = await SecureStorageService.instance.faceEnrolled;
    final vmkB64 = await SecureStorageService.instance.vmkB64;
    if (vmkB64 != null) vmk = base64Decode(vmkB64);
    state = SessionState.locked;
    notifyListeners();
  }

  Future<void> completeClaim({
    required String server,
    required String role,
    required String spouseId,
    required String accessToken,
    required String refreshToken,
    required String vmkB64,
  }) async {
    await ApiClient.instance.configureBaseUrl(server);
    await SecureStorageService.instance.saveSession(
      server: server, accessToken: accessToken, refreshToken: refreshToken, vmkB64: vmkB64, role: role, spouseId: spouseId,
    );
    this.role = role;
    this.spouseId = spouseId;
    vmk = base64Decode(vmkB64);
    faceEnrolled = false;
    state = SessionState.needsFaceEnroll;
    notifyListeners();
  }

  void markFaceEnrolled() {
    faceEnrolled = true;
    SecureStorageService.instance.setFaceEnrolled(true);
    state = SessionState.authenticated;
    WsClient.instance.connect();
    resetAutoLockTimer();
    notifyListeners();
  }

  void setPendingChallenge(String token) {
    _pendingChallengeToken = token;
    state = SessionState.needsFaceVerify;
    notifyListeners();
  }

  void cancelFaceVerify() {
    _pendingChallengeToken = null;
    state = SessionState.locked;
    notifyListeners();
  }

  String? get pendingChallengeToken => _pendingChallengeToken;

  Future<void> completeLogin({required String accessToken, required String refreshToken, required String role, required String spouseId}) async {
    final server = await SecureStorageService.instance.server;
    final vmkB64 = await SecureStorageService.instance.vmkB64;
    await SecureStorageService.instance.saveSession(
      server: server ?? '', accessToken: accessToken, refreshToken: refreshToken, vmkB64: vmkB64 ?? '', role: role, spouseId: spouseId,
    );
    this.role = role;
    this.spouseId = spouseId;
    faceEnrolled = true;
    state = SessionState.authenticated;
    WsClient.instance.connect();
    resetAutoLockTimer();
    notifyListeners();
  }

  void enterDecoyMode() {
    state = SessionState.decoy;
    notifyListeners();
  }

  void lock() {
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
    vmk = null;
    faceEnrolled = false;
    state = SessionState.needsSetup;
    notifyListeners();
  }

  String get otherRole => role == 'husband' ? 'wife' : 'husband';
}
