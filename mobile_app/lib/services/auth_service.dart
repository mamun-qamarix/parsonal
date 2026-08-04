import 'dart:convert';
import 'dart:typed_data';

import '../core/network/api_client.dart';
import '../core/storage/device_identity_service.dart';

class AuthService {
  final _dio = ApiClient.instance.dio;

  Future<Map<String, dynamic>> claimRole({
    required String server,
    required String token,
    required String role,
    required String password,
    required String deviceName,
  }) async {
    await ApiClient.instance.configureBaseUrl(server);
    final res = await _dio.post('/auth/setup/claim', data: {
      'token': token,
      'role': role,
      'password': password,
      'device_name': deviceName,
      'device_uuid': await DeviceIdentityService.getOrCreate(),
    });
    return res.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getMe() async {
    final res = await _dio.get('/auth/me');
    return res.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getTotpSetupInfo() async {
    final res = await _dio.get('/auth/totp/setup-info');
    return res.data as Map<String, dynamic>;
  }

  Future<void> totpSetupConfirm(String code) async {
    await _dio.post('/auth/totp/setup-confirm', data: {'code': code});
  }

  Future<void> enrollFace(Uint8List jpegBytes) async {
    await _dio.post('/auth/face/enroll', data: {
      'face_image_b64': base64Encode(jpegBytes),
    });
  }

  Future<void> enableFace() async {
    await _dio.post('/auth/face/enable');
  }

  Future<void> disableFace() async {
    await _dio.post('/auth/face/disable');
  }

  /// Returns the raw response: {mode: "verify", challenge_token} when this
  /// device already has a confirmed authenticator entry, or
  /// {mode: "setup", setup_challenge_token, totp_secret,
  /// totp_provisioning_uri} when it needs to set up its own first (new
  /// install, or a device newly paired onto an already-claimed role). See
  /// DECISIONS.md #21.
  Future<Map<String, dynamic>> loginPassword({required String role, required String password, required String deviceName}) async {
    final res = await _dio.post('/auth/login/password', data: {
      'role': role,
      'password': password,
      'device_name': deviceName,
      'device_uuid': await DeviceIdentityService.getOrCreate(),
    });
    return res.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> loginTotp({required String challengeToken, required String code}) async {
    final res = await _dio.post('/auth/login/totp', data: {'challenge_token': challengeToken, 'code': code});
    return res.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> loginTotpSetupConfirm({required String challengeToken, required String code}) async {
    final res = await _dio.post('/auth/login/totp-setup-confirm', data: {'challenge_token': challengeToken, 'code': code});
    return res.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> loginFace({required String challengeToken, required Uint8List jpegBytes}) async {
    final res = await _dio.post('/auth/login/face', data: {
      'challenge_token': challengeToken,
      'face_image_b64': base64Encode(jpegBytes),
    });
    return res.data as Map<String, dynamic>;
  }

  Future<void> setDuressPin(String pin) async {
    await _dio.post('/auth/duress/set', data: {'pin': pin});
  }

  Future<Map<String, dynamic>> passwordResetInitiate(String role) async {
    final res = await _dio.post('/auth/password-reset/initiate', data: {'role': role});
    return res.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> passwordResetVerify({required String resetToken, required String role, required String code}) async {
    final res = await _dio.post('/auth/password-reset/verify', data: {
      'reset_token': resetToken,
      'role': role,
      'code': code,
    });
    return res.data as Map<String, dynamic>;
  }

  Future<void> passwordResetComplete({required String resetToken, required String newPassword}) async {
    await _dio.post('/auth/password-reset/complete', data: {'reset_token': resetToken, 'new_password': newPassword});
  }
}
