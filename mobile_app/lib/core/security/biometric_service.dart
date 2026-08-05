import 'package:local_auth/local_auth.dart';

/// On-device biometric (fingerprint/face) unlock -- purely local, never
/// talks to the server. It only gates access to tokens already sitting
/// in secure storage from the last real password login. See
/// DECISIONS.md #27.
class BiometricService {
  static final _auth = LocalAuthentication();

  static Future<bool> isAvailable() async {
    try {
      final supported = await _auth.isDeviceSupported();
      final canCheck = await _auth.canCheckBiometrics;
      return supported || canCheck;
    } catch (_) {
      return false;
    }
  }

  /// Shows the OS biometric prompt. Falls back to device PIN/pattern if
  /// no fingerprint/face is enrolled, so a phone without biometric
  /// hardware set up still has a way in (rather than being stuck until
  /// the hourly password window comes back around).
  static Future<bool> authenticate() async {
    try {
      return await _auth.authenticate(
        localizedReason: 'অ্যাপে প্রবেশ করতে যাচাই করুন',
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );
    } catch (_) {
      return false;
    }
  }
}
