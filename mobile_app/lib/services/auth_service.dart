import 'dart:convert';
import 'dart:typed_data';

import '../core/network/api_client.dart';

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
    });
    return res.data as Map<String, dynamic>;
  }

  Future<void> enrollFace(Uint8List jpegBytes) async {
    await _dio.post('/auth/face/enroll', data: {
      'face_image_b64': base64Encode(jpegBytes),
    });
  }

  Future<String> loginPassword({required String role, required String password, required String deviceName}) async {
    final res = await _dio.post('/auth/login/password', data: {'role': role, 'password': password, 'device_name': deviceName});
    return res.data['challenge_token'] as String;
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

  Future<Map<String, dynamic>> passwordResetVerifyFace({required String resetToken, required String role, required Uint8List jpegBytes}) async {
    final res = await _dio.post('/auth/password-reset/verify-face', data: {
      'reset_token': resetToken,
      'role': role,
      'face_image_b64': base64Encode(jpegBytes),
    });
    return res.data as Map<String, dynamic>;
  }

  Future<void> passwordResetComplete({required String resetToken, required String newPassword}) async {
    await _dio.post('/auth/password-reset/complete', data: {'reset_token': resetToken, 'new_password': newPassword});
  }
}
