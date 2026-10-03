import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';

import 'chunked_crypto.dart';

/// Payloads above this size (photos, videos) are encrypted/decrypted inside
/// a background isolate so the pure-Dart AES-GCM -- slow for big files --
/// never blocks the UI thread (it used to freeze the app while a photo or
/// video was being opened). Small payloads (text, thumbnails) stay inline,
/// where spinning up an isolate would cost more than the work itself. Same
/// algorithm and wire format either way. See DECISIONS.md.
const _kBackgroundThreshold = 512 * 1024;

final _kHkdfInfo = utf8.encode('couple-vault-item');

/// Top-level (not a closure over `this`) so it can run via `Isolate.run`.
Future<Uint8List> _decryptPacked(Uint8List vmk, Uint8List packed) async {
  final key = await DartHkdf(
    hmac: DartHmac.sha256(),
    outputLength: 32,
  ).deriveKey(
    secretKey: SecretKey(vmk),
    nonce: packed.sublist(0, 16),
    info: _kHkdfInfo,
  );
  final box = SecretBox(
    packed.sublist(28, packed.length - 16),
    nonce: packed.sublist(16, 28),
    mac: Mac(packed.sublist(packed.length - 16)),
  );
  final clear = await DartAesGcm.with256bits().decrypt(box, secretKey: key);
  return clear is Uint8List ? clear : Uint8List.fromList(clear);
}

Future<Uint8List> _encryptPacked(
  Uint8List vmk,
  Uint8List plaintext,
  Uint8List salt,
  Uint8List nonce,
) async {
  final key = await DartHkdf(
    hmac: DartHmac.sha256(),
    outputLength: 32,
  ).deriveKey(secretKey: SecretKey(vmk), nonce: salt, info: _kHkdfInfo);
  final box = await DartAesGcm.with256bits().encrypt(
    plaintext,
    secretKey: key,
    nonce: nonce,
  );
  return (BytesBuilder(copy: false)
        ..add(salt)
        ..add(nonce)
        ..add(box.cipherText)
        ..add(box.mac.bytes))
      .toBytes();
}

/// Client-side end-to-end encryption. The server only ever sees the bytes
/// produced by [encryptBytes] (opaque ciphertext) — see DECISIONS.md §1.
///
/// Wire format of one encrypted payload (all local, never parsed server-side):
///   [ 16 bytes salt | 12 bytes nonce | ciphertext | 16 bytes GCM tag ]
/// A fresh per-item key is derived from the Vault Master Key (VMK) via
/// HKDF-SHA256 using a random salt, so no two items share a key.
class VaultCrypto {
  static final _random = Random.secure();

  static Uint8List _randomBytes(int length) {
    final bytes = Uint8List(length);
    for (var i = 0; i < length; i++) {
      bytes[i] = _random.nextInt(256);
    }
    return bytes;
  }

  /// Encrypts [plaintext] and returns the raw packed bytes ready to be
  /// base64-encoded for the `enc_payload` field sent to the server.
  static Future<Uint8List> encryptBytes(
    Uint8List vmk,
    Uint8List plaintext,
  ) {
    final salt = _randomBytes(16);
    final nonce = _randomBytes(12);
    if (plaintext.length > _kBackgroundThreshold) {
      return Isolate.run(() => _encryptPacked(vmk, plaintext, salt, nonce));
    }
    return _encryptPacked(vmk, plaintext, salt, nonce);
  }

  static Future<Uint8List> decryptBytes(Uint8List vmk, Uint8List packed) {
    // Streamable videos use their own chunked format (see ChunkedCrypto);
    // every caller that wants the whole file still just calls this.
    if (ChunkedCrypto.isChunked(packed)) {
      return Isolate.run(() => ChunkedCrypto.decryptAll(vmk, packed));
    }
    if (packed.length > _kBackgroundThreshold) {
      return Isolate.run(() => _decryptPacked(vmk, packed));
    }
    return _decryptPacked(vmk, packed);
  }

  static Future<String> encryptText(Uint8List vmk, String text) async {
    final packed = await encryptBytes(
      vmk,
      Uint8List.fromList(utf8.encode(text)),
    );
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
