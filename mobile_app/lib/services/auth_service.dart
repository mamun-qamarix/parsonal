import 'dart:convert';
import 'dart:typed_data';

import '../core/network/api_client.dart';
import '../core/storage/device_identity_service.dart';

class AuthService {
  final _dio = ApiClient.instance.dio;

  /// One shared master password for both of you (DECISIONS.md #54).
  /// Returns {status: "approved", access_token, refresh_token, role,
  /// spouse_id, device_id, vmk_b64} for a phone the server already
  /// approved, or {status: "pending", request_id, poll_token, code} for a
  /// phone still waiting on the admin panel.
  Future<Map<String, dynamic>> masterLogin({
    required String password,
    required String deviceName,
  }) async {
    final res = await _dio.post(
      '/auth/master/login',
      data: {
        'password': password,
        'device_name': deviceName,
        'device_uuid': await DeviceIdentityService.getOrCreate(),
      },
    );
    return res.data as Map<String, dynamic>;
  }

  /// Polled by the waiting screen: pending | rejected | approved(+tokens).
  Future<Map<String, dynamic>> masterStatus({
    required String requestId,
    required String pollToken,
  }) async {
    final res = await _dio.post(
      '/auth/master/status',
      data: {'request_id': requestId, 'poll_token': pollToken},
    );
    return res.data as Map<String, dynamic>;
  }

  /// Uploads this phone's vault key if the server has none yet (older
  /// deployments) so newly approved phones can receive it.
  Future<void> escrowVaultKey(String vmkB64) async {
    await _dio.post('/auth/master/vault-key', data: {'vmk_b64': vmkB64});
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
}
