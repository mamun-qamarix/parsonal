import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Client-side end-to-end encryption. The server only ever sees the bytes
/// produced by [encryptBytes] (opaque ciphertext) — see DECISIONS.md §1.
///
/// Wire format of one encrypted payload (all local, never parsed server-side):
///   [ 16 bytes salt | 12 bytes nonce | ciphertext | 16 bytes GCM tag ]
/// A fresh per-item key is derived from the Vault Master Key (VMK) via
/// HKDF-SHA256 using a random salt, so no two items share a key.
class VaultCrypto {
  static final _algorithm = AesGcm.with256bits();
  static final _hkdfAlgo = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  static final _random = Random.secure();

  static Uint8List _randomBytes(int length) {
    final bytes = Uint8List(length);
    for (var i = 0; i < length; i++) {
      bytes[i] = _random.nextInt(256);
    }
    return bytes;
  }

  static Future<SecretKey> _deriveItemKey(Uint8List vmk, Uint8List salt) {
    return _hkdfAlgo.deriveKey(
      secretKey: SecretKey(vmk),
      nonce: salt,
      info: utf8.encode('couple-vault-item'),
    );
  }

  /// Encrypts [plaintext] and returns the raw packed bytes ready to be
  /// base64-encoded for the `enc_payload` field sent to the server.
  static Future<Uint8List> encryptBytes(Uint8List vmk, Uint8List plaintext) async {
    final salt = _randomBytes(16);
    final key = await _deriveItemKey(vmk, salt);
    final nonce = _randomBytes(12);
    final box = await _algorithm.encrypt(plaintext, secretKey: key, nonce: nonce);
    return Uint8List.fromList([...salt, ...nonce, ...box.cipherText, ...box.mac.bytes]);
  }

  static Future<Uint8List> decryptBytes(Uint8List vmk, Uint8List packed) async {
    final salt = packed.sublist(0, 16);
    final nonce = packed.sublist(16, 28);
    final tag = packed.sublist(packed.length - 16);
    final cipherText = packed.sublist(28, packed.length - 16);
    final key = await _deriveItemKey(vmk, salt);
    final box = SecretBox(cipherText, nonce: nonce, mac: Mac(tag));
    final clear = await _algorithm.decrypt(box, secretKey: key);
    return Uint8List.fromList(clear);
  }

  static Future<String> encryptText(Uint8List vmk, String text) async {
    final packed = await encryptBytes(vmk, Uint8List.fromList(utf8.encode(text)));
    return base64Encode(packed);
  }

  static Future<String> decryptText(Uint8List vmk, String encPayloadB64) async {
    final packed = base64Decode(encPayloadB64);
    final clear = await decryptBytes(vmk, packed);
    return utf8.decode(clear);
  }

  static Future<String> encryptToB64(Uint8List vmk, Uint8List plaintext) async {
    final packed = await encryptBytes(vmk, plaintext);
    return base64Encode(packed);
  }

  static Future<Uint8List> decryptFromB64(Uint8List vmk, String b64) async {
    return decryptBytes(vmk, base64Decode(b64));
  }

  static Uint8List vmkFromB64(String b64) => base64Decode(b64);
}
