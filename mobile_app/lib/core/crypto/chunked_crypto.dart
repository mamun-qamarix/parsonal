import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';

/// Streamable encryption format for videos (see DECISIONS.md).
///
/// The original format encrypts a whole file as ONE AES-GCM blob, whose
/// authentication tag sits at the very end -- so nothing can be safely
/// decrypted until the entire file has downloaded. This format instead
/// splits the plaintext into fixed-size chunks, each encrypted and
/// authenticated on its own, so playback can start as soon as the first
/// chunk arrives without ever showing unverified data:
///
///   header: "CVSTRM02" (8) | chunkSize u32 BE (4) | plainSize u64 BE (8) |
///           salt (16)                                     = 36 bytes
///   chunk i: nonce (12) | ciphertext (<= chunkSize) | GCM tag (16)
///
/// Key = HKDF-SHA256(VMK, salt) -- same derivation as the single-blob
/// format. Each chunk's AAD is its index (u64 BE) plus a "last chunk" flag,
/// so chunks can't be reordered, swapped between positions, or have the
/// end of the file silently cut off without decryption failing.
class ChunkedCrypto {
  static const magic = [0x43, 0x56, 0x53, 0x54, 0x52, 0x4D, 0x30, 0x32];
  static const headerLength = 36;
  static const defaultChunkSize = 1024 * 1024;
  static const _overhead = 12 + 16;
  static final _info = utf8.encode('couple-vault-item');

  static bool isChunked(Uint8List bytes) {
    if (bytes.length < magic.length) return false;
    for (var i = 0; i < magic.length; i++) {
      if (bytes[i] != magic[i]) return false;
    }
    return true;
  }

  static Future<Uint8List> deriveKeyBytes(Uint8List vmk, Uint8List salt) async {
    final key = await DartHkdf(
      hmac: DartHmac.sha256(),
      outputLength: 32,
    ).deriveKey(secretKey: SecretKey(vmk), nonce: salt, info: _info);
    return Uint8List.fromList(await key.extractBytes());
  }

  static Uint8List _aad(int index, bool last) {
    final b = ByteData(9)
      ..setUint64(0, index)
      ..setUint8(8, last ? 1 : 0);
    return b.buffer.asUint8List();
  }

  /// Encrypts [plaintext] into the chunked format. Pure Dart and
  /// self-contained, so callers run it via `Isolate.run`.
  static Future<Uint8List> encrypt(
    Uint8List vmk,
    Uint8List plaintext, {
    int chunkSize = defaultChunkSize,
  }) async {
    final rnd = Random.secure();
    Uint8List randomBytes(int n) =>
        Uint8List.fromList(List.generate(n, (_) => rnd.nextInt(256)));
    final salt = randomBytes(16);
    final keyBytes = await deriveKeyBytes(vmk, salt);
    final key = SecretKey(keyBytes);
    final aes = DartAesGcm.with256bits();

    final header = ByteData(headerLength);
    for (var i = 0; i < magic.length; i++) {
      header.setUint8(i, magic[i]);
    }
    header
      ..setUint32(8, chunkSize)
      ..setUint64(12, plaintext.length);
    final out = BytesBuilder(copy: false)
      ..add(header.buffer.asUint8List(0, 20))
      ..add(salt);

    final count = chunkCountFor(plaintext.length, chunkSize);
    for (var i = 0; i < count; i++) {
      final start = i * chunkSize;
      final end = min(start + chunkSize, plaintext.length);
      final nonce = randomBytes(12);
      final box = await aes.encrypt(
        Uint8List.sublistView(plaintext, start, end),
        secretKey: key,
        nonce: nonce,
        aad: _aad(i, i == count - 1),
      );
      out
        ..add(nonce)
        ..add(box.cipherText)
        ..add(box.mac.bytes);
    }
    return out.toBytes();
  }

  static int chunkCountFor(int plainSize, int chunkSize) =>
      plainSize == 0 ? 1 : (plainSize + chunkSize - 1) ~/ chunkSize;

  /// Decrypts ONE encrypted chunk (nonce | ciphertext | tag). Throws if it
  /// was tampered with, is at the wrong index, or the "last" flag is wrong.
  static Future<Uint8List> decryptChunk(
    Uint8List keyBytes,
    Uint8List encChunk,
    int index,
    bool last,
  ) async {
    final box = SecretBox(
      Uint8List.sublistView(encChunk, 12, encChunk.length - 16),
      nonce: Uint8List.sublistView(encChunk, 0, 12),
      mac: Mac(Uint8List.sublistView(encChunk, encChunk.length - 16)),
    );
    final clear = await DartAesGcm.with256bits().decrypt(
      box,
      secretKey: SecretKey(keyBytes),
      aad: _aad(index, last),
    );
    return clear is Uint8List ? clear : Uint8List.fromList(clear);
  }

  /// Decrypts a whole chunked file (for downloads / gallery saves).
  static Future<Uint8List> decryptAll(Uint8List vmk, Uint8List data) async {
    final h = ChunkedHeader.parse(data);
    final keyBytes = await deriveKeyBytes(vmk, h.salt);
    final out = BytesBuilder(copy: false);
    for (var i = 0; i < h.chunkCount; i++) {
      final off = h.encOffset(i);
      out.add(
        await decryptChunk(
          keyBytes,
          Uint8List.sublistView(data, off, off + h.encLength(i)),
          i,
          i == h.chunkCount - 1,
        ),
      );
    }
    final result = out.toBytes();
    if (result.length != h.plainSize) {
      throw StateError('chunked payload size mismatch');
    }
    return result;
  }
}

class ChunkedHeader {
  final int chunkSize;
  final int plainSize;
  final Uint8List salt;
  ChunkedHeader(this.chunkSize, this.plainSize, this.salt);

  factory ChunkedHeader.parse(Uint8List bytes) {
    if (bytes.length < ChunkedCrypto.headerLength ||
        !ChunkedCrypto.isChunked(bytes)) {
      throw const FormatException('not a chunked payload');
    }
    final b = ByteData.sublistView(bytes, 0, ChunkedCrypto.headerLength);
    final chunkSize = b.getUint32(8);
    if (chunkSize <= 0 || chunkSize > 64 * 1024 * 1024) {
      throw const FormatException('bad chunk size');
    }
    return ChunkedHeader(
      chunkSize,
      b.getUint64(12),
      Uint8List.fromList(bytes.sublist(20, 36)),
    );
  }

  int get chunkCount => ChunkedCrypto.chunkCountFor(plainSize, chunkSize);

  /// Plaintext length of chunk [i].
  int plainLength(int i) =>
      i < chunkCount - 1 ? chunkSize : plainSize - chunkSize * (chunkCount - 1);

  int encLength(int i) => plainLength(i) + ChunkedCrypto._overhead;

  int encOffset(int i) =>
      ChunkedCrypto.headerLength + i * (chunkSize + ChunkedCrypto._overhead);
}
