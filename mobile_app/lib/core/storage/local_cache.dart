import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// A tiny on-disk cache so the app keeps working (read-only) without a
/// network connection.
///
/// SECURITY: every value stored here is EXACTLY what the API already
/// returned over the wire -- for anything encrypted (vault entries, chat
/// text, profile names/bios, media bytes) that means ciphertext, the same
/// ciphertext the server itself holds. Nothing is ever decrypted before
/// being cached, and the VMK is never written here -- it lives only in
/// memory (SessionProvider) for the life of the unlocked session, exactly
/// as it does today. Reading from this cache and decrypting the result
/// afterwards is therefore exactly as secure as reading a fresh response
/// from the server; the only difference is possible staleness, never
/// confidentiality. See DECISIONS.md.
///
/// Lives in the app's own private sandboxed storage -- the same
/// protection level as everything else the app already writes to disk
/// (e.g. temp media files for playback) -- not readable by other apps
/// without root.
class LocalCache {
  LocalCache._();
  static final instance = LocalCache._();

  Directory? _jsonDir;
  Directory? _blobDir;

  Future<Directory> _ensureJsonDir() async {
    if (_jsonDir != null) return _jsonDir!;
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/offline_cache');
    if (!await dir.exists()) await dir.create(recursive: true);
    return _jsonDir = dir;
  }

  Future<Directory> _ensureBlobDir() async {
    if (_blobDir != null) return _blobDir!;
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/offline_media_cache');
    if (!await dir.exists()) await dir.create(recursive: true);
    return _blobDir = dir;
  }

  String _safeName(String key) =>
      key.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');

  /// Caches a JSON-encodable value (a decoded `response.data`) under [key].
  /// Best-effort -- a caching failure must never block the already-
  /// succeeded network response from reaching the caller.
  Future<void> putJson(String key, dynamic value) async {
    try {
      final dir = await _ensureJsonDir();
      final file = File('${dir.path}/${_safeName(key)}.json');
      await file.writeAsString(jsonEncode(value), flush: true);
    } catch (_) {}
  }

  Future<dynamic> getJson(String key) async {
    try {
      final dir = await _ensureJsonDir();
      final file = File('${dir.path}/${_safeName(key)}.json');
      if (!await file.exists()) return null;
      return jsonDecode(await file.readAsString());
    } catch (_) {
      return null;
    }
  }

  /// Caches raw (still-encrypted) media bytes for [assetId]/[variant]
  /// ("raw" | "thumb") so previously-viewed photos/videos/voice notes open
  /// instantly and keep working offline.
  Future<void> putBlob(String assetId, String variant, Uint8List bytes) async {
    try {
      final dir = await _ensureBlobDir();
      final file = File('${dir.path}/${_safeName(assetId)}_$variant.bin');
      await file.writeAsBytes(bytes, flush: true);
    } catch (_) {}
  }

  Future<Uint8List?> getBlob(String assetId, String variant) async {
    try {
      final dir = await _ensureBlobDir();
      final file = File('${dir.path}/${_safeName(assetId)}_$variant.bin');
      if (!await file.exists()) return null;
      return await file.readAsBytes();
    } catch (_) {
      return null;
    }
  }
}
