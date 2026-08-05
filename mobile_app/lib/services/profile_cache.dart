import 'dart:typed_data';

import '../models/models.dart';
import 'profile_service.dart';

/// Caches the husband's and wife's decrypted profile (name + photo asset
/// id) for the life of the app session -- there are only ever two
/// profiles, so this avoids re-fetching+re-decrypting them on every
/// comment/reaction/post row that wants to show "who did this" with a
/// real name and photo instead of a generic role label. See DECISIONS.md.
class ProfileCache {
  ProfileCache._();
  static final instance = ProfileCache._();

  final Map<String, ProfileModel> _cache = {};
  final _service = ProfileService();

  /// Returns the cached profile for [role] if we have it; triggers a
  /// background fetch (and notifies [onLoaded] once done) if we don't.
  /// Callers that can't await (e.g. a list itemBuilder) should call this
  /// for an immediate best-effort value and pass onLoaded to rebuild once
  /// the real profile arrives.
  ProfileModel? peek(String role) => _cache[role];

  Future<ProfileModel?> get(Uint8List vmk, String role) async {
    final cached = _cache[role];
    if (cached != null) return cached;
    try {
      final profile = await _service.get(vmk, role);
      _cache[role] = profile;
      return profile;
    } catch (_) {
      return null;
    }
  }

  /// Warms the cache for both roles at once -- call this once when the
  /// home shell loads so individual cards/comments/reactions can use
  /// [peek] synchronously right away in the common case.
  Future<void> warmUp(Uint8List vmk) async {
    await Future.wait([get(vmk, 'husband'), get(vmk, 'wife')]);
  }

  /// Call after saving a profile edit so the new name/photo shows up
  /// immediately instead of waiting for the next cold app start.
  void invalidate(String role) => _cache.remove(role);
}
