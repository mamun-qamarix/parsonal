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
    final res = await _dio.post(
      '/auth/setup/claim',
      data: {
        'token': token,
        'role': role,
        'password': password,
        'device_name': deviceName,
        'device_uuid': await DeviceIdentityService.getOrCreate(),
      },
    );
    return res.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getMe() async {
    final res = await _dio.get('/auth/me');
    return res.data as Map<String, dynamic>;
  }

  Future<void> enrollFace(Uint8List jpegBytes) async {
    await _dio.post(
      '/auth/face/enroll',
      data: {'face_image_b64': base64Encode(jpegBytes)},
    );
  }

  Future<void> enableFace() async {
    await _dio.post('/auth/face/enable');
  }

  Future<void> disableFace() async {
    await _dio.post('/auth/face/disable');
  }

  /// Password is now the only server-verified factor -- returns either
  /// {requires_face: false, access_token, refresh_token, role, spouse_id,
  /// device_id} directly, or {requires_face: true, face_challenge_token}
  /// for spouses who opted into the extra face-verification step. See
  /// DECISIONS.md #27.
  Future<Map<String, dynamic>> loginPassword({
    required String role,
    required String password,
    required String deviceName,
  }) async {
    final res = await _dio.post(
      '/auth/login/password',
      data: {
        'role': role,
        'password': password,
        'device_name': deviceName,
        'device_uuid': await DeviceIdentityService.getOrCreate(),
      },
    );
    return res.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> loginFace({
    required String challengeToken,
    required Uint8List jpegBytes,
  }) async {
    final res = await _dio.post(
      '/auth/login/face',
      data: {
        'challenge_token': challengeToken,
        'face_image_b64': base64Encode(jpegBytes),
      },
    );
    return res.data as Map<String, dynamic>;
  }

  Future<void> setDuressPin(String pin) async {
    await _dio.post('/auth/duress/set', data: {'pin': pin});
  }

  Future<Map<String, dynamic>> passwordResetInitiate(String role) async {
    final res = await _dio.post(
      '/auth/password-reset/initiate',
      data: {'role': role},
    );
    return res.data as Map<String, dynamic>;
  }

  Future<void> passwordResetApprove(String resetToken) async {
    await _dio.post(
      '/auth/password-reset/approve',
      data: {'reset_token': resetToken},
    );
  }

  Future<bool> passwordResetStatus(String resetToken) async {
    final res = await _dio.post(
      '/auth/password-reset/status',
      data: {'reset_token': resetToken},
    );
    return res.data['approved'] as bool;
  }

  Future<void> passwordResetComplete({
    required String resetToken,
    required String newPassword,
  }) async {
    await _dio.post(
      '/auth/password-reset/complete',
      data: {'reset_token': resetToken, 'new_password': newPassword},
    );
  }
}
