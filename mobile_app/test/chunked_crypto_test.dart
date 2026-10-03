import 'dart:math';
import 'dart:typed_data';

import 'package:couple_vault/core/crypto/chunked_crypto.dart';
import 'package:couple_vault/core/crypto/vault_crypto.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _bytes(int n, int seed) {
  final r = Random(seed);
  return Uint8List.fromList(List.generate(n, (_) => r.nextInt(256)));
}

void main() {
  final vmk = _bytes(32, 1);

  test('round trip, several sizes, via VaultCrypto.decryptBytes', () async {
    for (final size in [0, 1, 1000, 4096, 4097, 3 * 4096 + 5]) {
      final plain = _bytes(size, size);
      final enc = await ChunkedCrypto.encrypt(vmk, plain, chunkSize: 4096);
      expect(ChunkedCrypto.isChunked(enc), isTrue);
      expect(await VaultCrypto.decryptBytes(vmk, enc), plain);
    }
  });

  test('per-chunk decrypt at header-computed offsets', () async {
    final plain = _bytes(3 * 4096 + 5, 7);
    final enc = await ChunkedCrypto.encrypt(vmk, plain, chunkSize: 4096);
    final h = ChunkedHeader.parse(enc);
    expect(h.chunkCount, 4);
    expect(enc.length, h.encOffset(3) + h.encLength(3));
    final key = await ChunkedCrypto.deriveKeyBytes(vmk, h.salt);
    for (var i = 0; i < h.chunkCount; i++) {
      final off = h.encOffset(i);
      final clear = await ChunkedCrypto.decryptChunk(
        key,
        Uint8List.sublistView(enc, off, off + h.encLength(i)),
        i,
        i == h.chunkCount - 1,
      );
      expect(clear, plain.sublist(i * 4096, i * 4096 + h.plainLength(i)));
    }
  });

  test('tampering, wrong index or truncation is rejected', () async {
    final plain = _bytes(2 * 4096, 9);
    final enc = await ChunkedCrypto.encrypt(vmk, plain, chunkSize: 4096);
    final h = ChunkedHeader.parse(enc);
    final key = await ChunkedCrypto.deriveKeyBytes(vmk, h.salt);
    final chunk0 = Uint8List.fromList(
      enc.sublist(h.encOffset(0), h.encOffset(0) + h.encLength(0)),
    );
    // Wrong position.
    expect(
      () => ChunkedCrypto.decryptChunk(key, chunk0, 1, true),
      throwsA(anything),
    );
    // Claiming chunk 0 is the last one (truncation).
    expect(
      () => ChunkedCrypto.decryptChunk(key, chunk0, 0, true),
      throwsA(anything),
    );
    // Flipped bit.
    final bad = Uint8List.fromList(chunk0)..[20] ^= 1;
    expect(
      () => ChunkedCrypto.decryptChunk(key, bad, 0, false),
      throwsA(anything),
    );
  });

  test('old single-blob format still decrypts', () async {
    final plain = _bytes(5000, 3);
    final enc = await VaultCrypto.encryptBytes(vmk, plain);
    expect(ChunkedCrypto.isChunked(enc), isFalse);
    expect(await VaultCrypto.decryptBytes(vmk, enc), plain);
  });
}
