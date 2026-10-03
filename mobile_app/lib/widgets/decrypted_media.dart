import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../core/media/video_thumbnail_helper.dart';
import '../providers/session_provider.dart';
import '../services/media_service.dart';
import 'shimmer_loading.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

/// Blurs [child] whenever the app-wide privacy mask (see DECISIONS.md) is
/// on -- baked into the shared media widgets below so EVERY image/video
/// anywhere in the app picks this up automatically, with nothing to
/// remember to wire in per screen. [forceShow] lets a screen with its own,
/// more specific privacy control (chat's local eye toggle) opt out of the
/// global one entirely for its own media -- chat's toggle is meant to have
/// full, independent authority over what chat shows, with no relation to
/// the home screen's toggle either way. See DECISIONS.md.
Widget _applyPrivacyBlur(BuildContext context, Widget child, {bool forceShow = false}) {
  if (forceShow) return child;
  final masked = context.watch<SessionProvider>().privacyMask;
  if (!masked) return child;
  return ImageFiltered(
    imageFilter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
    child: child,
  );
}

/// In-memory cache of decrypted media with a byte budget (least-recently-
/// used entries are evicted -- previously this grew without limit, which
/// could exhaust memory after browsing a lot of big photos/videos) and
/// in-flight de-duplication (the same asset requested twice at once --
/// e.g. a thumbnail and a full view -- is only fetched/decrypted once).
/// Cache hits are returned as a [SynchronousFuture] so a widget can paint
/// real content on its very first frame with no loading flash. See
/// DECISIONS.md.
class _DecryptedMediaCache {
  static const _maxBytes = 120 * 1024 * 1024;
  static final LinkedHashMap<String, Uint8List> _cache = LinkedHashMap();
  static final Map<String, Future<Uint8List>> _inflight = {};
  static int _size = 0;

  static Uint8List? peek(String key) {
    final v = _cache.remove(key);
    if (v != null) _cache[key] = v; // mark as most recently used
    return v;
  }

  static void _put(String key, Uint8List data) {
    if (data.length > _maxBytes) return; // too big to keep around
    final old = _cache.remove(key);
    if (old != null) _size -= old.length;
    _cache[key] = data;
    _size += data.length;
    while (_size > _maxBytes && _cache.length > 1) {
      final oldest = _cache.keys.first;
      _size -= _cache.remove(oldest)!.length;
    }
  }

  static Future<Uint8List> get(
    String key,
    Future<Uint8List> Function() loader,
  ) {
    final hit = peek(key);
    if (hit != null) return SynchronousFuture(hit);
    return _inflight[key] ??= loader()
        .then((data) {
          _put(key, data);
          return data;
        })
        .whenComplete(() {
          // Statement body on purpose: returning remove()'s value (this very
          // Future) would make whenComplete wait on itself forever.
          _inflight.remove(key);
        });
  }
}

/// Loading placeholder for any media area: a shimmering block that fills
/// the available box, or a sensible fixed aspect ratio when the parent
/// gives no bounded height (so it can never blow up a scrolling list).
Widget _mediaShimmer({double fallbackRatio = 4 / 3}) {
  return LayoutBuilder(
    builder: (context, c) {
      if (c.hasBoundedWidth && c.hasBoundedHeight) return const ShimmerFill();
      if (c.hasBoundedWidth) {
        return AspectRatio(
          aspectRatio: fallbackRatio,
          child: const ShimmerFill(),
        );
      }
      return const SizedBox(width: 120, height: 120, child: ShimmerFill());
    },
  );
}

/// Downloads + decrypts a media asset thumbnail (or full image if no
/// thumbnail exists) and displays it. Results are cached in-memory for the
/// life of the app session.
///
/// For a video with [isVideo] set and no thumbnail yet -- an entry from
/// before client-side thumbnail generation existed, or one where
/// generation silently failed on upload -- this self-heals the first time
/// it's displayed: downloads the video once, generates a thumbnail
/// locally, uploads it (so every future view is instant server-side too),
/// and shows it immediately. Previously such videos showed as an
/// identical blank placeholder with no way to tell them apart. See
/// DECISIONS.md.
class DecryptedThumbnail extends StatefulWidget {
  final String assetId;
  final bool hasThumbnail;
  final bool isVideo;
  final BoxFit fit;
  /// Fires once with the image's real width/height aspect ratio, for
  /// callers that want to size their layout to match instead of forcing
  /// a fixed crop. See DECISIONS.md.
  final void Function(double aspectRatio)? onAspectRatio;
  /// See `_applyPrivacyBlur` -- opts this instance out of the global
  /// privacy mask (used by chat, whose own local toggle takes full
  /// priority instead). See DECISIONS.md.
  final bool forceShow;
  const DecryptedThumbnail({
    super.key,
    required this.assetId,
    required this.hasThumbnail,
    this.isVideo = false,
    this.fit = BoxFit.cover,
    this.onAspectRatio,
    this.forceShow = false,
  });

  @override
  State<DecryptedThumbnail> createState() => _DecryptedThumbnailState();
}

class _DecryptedThumbnailState extends State<DecryptedThumbnail> {
  bool _aspectReported = false;
  late Future<Uint8List> _future;

  @override
  void initState() {
    super.initState();
    _future = _start();
  }

  @override
  void didUpdateWidget(covariant DecryptedThumbnail old) {
    super.didUpdateWidget(old);
    if (old.assetId != widget.assetId) {
      _aspectReported = false;
      _future = _start();
    }
  }

  // Created once per asset (NOT in build) -- a fresh Future on every
  // rebuild made FutureBuilder flash back to its loading state each time
  // anything above it rebuilt.
  Future<Uint8List> _start() {
    final vmk = context.read<SessionProvider>().vmk!;
    final service = MediaService();
    return _DecryptedMediaCache.get(
      'thumb:${widget.assetId}',
      () => _load(vmk, service),
    );
  }

  void _maybeReportAspect(Uint8List bytes) {
    if (_aspectReported || widget.onAspectRatio == null) return;
    _aspectReported = true;
    decodeImageFromList(bytes)
        .then((img) {
          if (mounted && img.height > 0) {
            widget.onAspectRatio!(img.width / img.height);
          }
        })
        .catchError((_) {});
  }

  Future<Uint8List> _load(Uint8List vmk, MediaService service) async {
    if (widget.hasThumbnail) {
      return service.downloadThumbnail(vmk, widget.assetId);
    }
    if (!widget.isVideo) {
      // A photo without a pre-generated thumbnail: just show the original.
      return service.downloadRaw(vmk, widget.assetId);
    }
    final videoBytes = await service.downloadRaw(vmk, widget.assetId);
    final dir = await getTemporaryDirectory();
    final tempFile = File('${dir.path}/thumb_src_${widget.assetId}.mp4');
    await tempFile.writeAsBytes(videoBytes, flush: true);
    final thumb = await generateVideoThumbnail(tempFile.path);
    await tempFile.delete().catchError((_) => tempFile);
    if (thumb == null) throw Exception('thumbnail generation failed');
    // Best-effort -- if this upload fails, the same backfill just runs
    // again next time this asset is displayed.
    unawaited(service.attachThumbnail(vmk, widget.assetId, thumb).catchError((_) {}));
    return thumb;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return _mediaShimmer();
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return Container(
            color: Colors.grey.withValues(alpha: 0.15),
            child: Icon(widget.isVideo ? Iconsax.video : Iconsax.gallery_slash),
          );
        }
        _maybeReportAspect(snapshot.data!);
        return _applyPrivacyBlur(
          context,
          Image.memory(
            snapshot.data!,
            fit: widget.fit,
            gaplessPlayback: true,
          ),
          forceShow: widget.forceShow,
        );
      },
    );
  }
}

/// [fit] paints correctly within WHATEVER box this is given, tight or not
/// (BoxFit works at paint time, unlike AspectRatio which needs layout
/// freedom) -- BoxFit.cover for small fixed preview boxes (chat bubbles),
/// BoxFit.contain (default) for a full-screen zoom viewer, BoxFit.fitWidth
/// for Reel's "width fixed, height follows the real aspect ratio" style.
/// See DECISIONS.md.
class DecryptedFullImage extends StatefulWidget {
  final String assetId;
  final BoxFit fit;
  final bool zoomable;
  /// See `DecryptedThumbnail.forceShow`.
  final bool forceShow;
  const DecryptedFullImage({
    super.key,
    required this.assetId,
    this.fit = BoxFit.contain,
    this.zoomable = true,
    this.forceShow = false,
  });

  @override
  State<DecryptedFullImage> createState() => _DecryptedFullImageState();
}

class _DecryptedFullImageState extends State<DecryptedFullImage> {
  late Future<Uint8List> _future;

  @override
  void initState() {
    super.initState();
    _future = _start();
  }

  @override
  void didUpdateWidget(covariant DecryptedFullImage old) {
    super.didUpdateWidget(old);
    if (old.assetId != widget.assetId) _future = _start();
  }

  Future<Uint8List> _start() {
    final vmk = context.read<SessionProvider>().vmk!;
    return _DecryptedMediaCache.get(
      'full:${widget.assetId}',
      () => MediaService().downloadRaw(vmk, widget.assetId),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return _mediaShimmer();
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return const Center(child: Icon(Iconsax.gallery_slash, size: 48));
        }
        // Decode no wider than the screen can usefully show (a 12MP photo
        // decoded at full size is slow and memory-hungry); the zoom viewer
        // gets extra headroom.
        final image = _applyPrivacyBlur(
          context,
          Image.memory(
            snapshot.data!,
            fit: widget.fit,
            cacheWidth: widget.zoomable ? 2400 : 1440,
            gaplessPlayback: true,
          ),
          forceShow: widget.forceShow,
        );
        return widget.zoomable ? InteractiveViewer(child: image) : image;
      },
    );
  }
}

/// Decrypts a video into a temp buffer and plays it via VideoPlayer's
/// bytes-backed data source. Its AspectRatio wrapper needs actual layout
/// freedom (a tight/expand parent forces it to ignore the real ratio and
/// stretch) -- give it a Center or similarly unconstraining parent. See
/// DECISIONS.md.
///
/// Shows standard playback controls -- play/pause, a scrub bar with
/// position/duration, and ±10s skip buttons -- previously this was just a
/// bare play/pause toggle with no way to scrub through a longer video. See
/// DECISIONS.md.
class DecryptedVideoPlayer extends StatefulWidget {
  final String assetId;
  /// See `DecryptedThumbnail.forceShow`.
  final bool forceShow;
  const DecryptedVideoPlayer({super.key, required this.assetId, this.forceShow = false});

  @override
  State<DecryptedVideoPlayer> createState() => _DecryptedVideoPlayerState();
}

class _DecryptedVideoPlayerState extends State<DecryptedVideoPlayer> {
  VideoPlayerController? _controller;
  File? _tempFile;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final vmk = context.read<SessionProvider>().vmk!;
      final bytes = await _DecryptedMediaCache.get(
        'full:${widget.assetId}',
        () => MediaService().downloadRaw(vmk, widget.assetId),
      );
      if (!mounted) return;
      final file = await _writeTempFile(widget.assetId, bytes);
      final controller = VideoPlayerController.file(file);
      try {
        await controller.initialize();
      } catch (_) {
        await file.delete().catchError((_) => file);
        rethrow;
      }
      if (!mounted) {
        // Left the screen while the video was still preparing -- clean up
        // instead of leaking the player and the decrypted temp file.
        await controller.dispose();
        await file.delete().catchError((_) => file);
        return;
      }
      controller.addListener(_onTick);
      setState(() {
        _controller = controller;
        _tempFile = file;
      });
    } catch (_) {
      if (mounted) setState(() => _error = true);
    }
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  Future<File> _writeTempFile(String assetId, Uint8List bytes) async {
    final dir = await getTemporaryDirectory();
    // Unique per player instance: the same video can be open in two places
    // at once (e.g. Reel and the full-screen viewer) and closing one used
    // to delete the file the other was still playing from, which errored
    // out playback on "back". See DECISIONS.md.
    final file = File('${dir.path}/vault_video_${assetId}_$hashCode.mp4');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  void _seekBy(Duration offset) {
    final controller = _controller;
    if (controller == null) return;
    final target = controller.value.position + offset;
    final clamped = target < Duration.zero
        ? Duration.zero
        : (target > controller.value.duration ? controller.value.duration : target);
    controller.seekTo(clamped);
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    if (_error) return const Center(child: Icon(Iconsax.danger));
    final controller = _controller;
    if (controller == null) {
      return const AspectRatio(aspectRatio: 16 / 9, child: ShimmerFill());
    }
    final position = controller.value.position;
    final duration = controller.value.duration;
    return AspectRatio(
      aspectRatio: controller.value.aspectRatio,
      child: Stack(
        alignment: Alignment.center,
        children: [
          _applyPrivacyBlur(context, VideoPlayer(controller), forceShow: widget.forceShow),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                iconSize: 32,
                color: Colors.white,
                icon: const Icon(Iconsax.backward_10_seconds),
                onPressed: () => _seekBy(const Duration(seconds: -10)),
              ),
              IconButton(
                iconSize: 56,
                color: Colors.white,
                icon: Icon(
                  controller.value.isPlaying ? Iconsax.pause_circle : Iconsax.play_circle,
                ),
                onPressed: () => setState(
                  () => controller.value.isPlaying ? controller.pause() : controller.play(),
                ),
              ),
              IconButton(
                iconSize: 32,
                color: Colors.white,
                icon: const Icon(Iconsax.forward_10_seconds),
                onPressed: () => _seekBy(const Duration(seconds: 10)),
              ),
            ],
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black.withValues(alpha: 0.55)],
                ),
              ),
              child: Row(
                children: [
                  Text(_fmt(position), style: const TextStyle(color: Colors.white, fontSize: 11)),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 2,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                      ),
                      child: Slider(
                        value: position.inMilliseconds.clamp(0, duration.inMilliseconds).toDouble(),
                        max: duration.inMilliseconds > 0 ? duration.inMilliseconds.toDouble() : 1,
                        activeColor: Colors.white,
                        inactiveColor: Colors.white30,
                        onChanged: (v) => controller.seekTo(Duration(milliseconds: v.toInt())),
                      ),
                    ),
                  ),
                  Text(_fmt(duration), style: const TextStyle(color: Colors.white, fontSize: 11)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller?.removeListener(_onTick);
    _controller?.dispose();
    _tempFile?.delete().catchError((_) => _tempFile!);
    super.dispose();
  }
}

/// Decrypts a voice note and plays it in place (play/pause + a progress
/// bar showing position/duration) -- previously voice messages in chat
/// just showed a "[voice]" text placeholder with no way to actually hear
/// them. See DECISIONS.md.
class DecryptedVoicePlayer extends StatefulWidget {
  final String assetId;
  final Color? color;
  const DecryptedVoicePlayer({super.key, required this.assetId, this.color});

  @override
  State<DecryptedVoicePlayer> createState() => _DecryptedVoicePlayerState();
}

class _DecryptedVoicePlayerState extends State<DecryptedVoicePlayer> {
  final _player = AudioPlayer();
  Uint8List? _bytes;
  bool _loading = true;
  bool _error = false;
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _player.onPlayerStateChanged.listen((s) {
      if (mounted) setState(() => _playing = s == PlayerState.playing);
    });
    _player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _player.onDurationChanged.listen((d) {
      if (mounted) setState(() => _duration = d);
    });
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _position = Duration.zero);
    });
    _load();
  }

  Future<void> _load() async {
    try {
      final vmk = context.read<SessionProvider>().vmk!;
      final bytes = await _DecryptedMediaCache.get(
        'full:${widget.assetId}',
        () => MediaService().downloadRaw(vmk, widget.assetId),
      );
      if (mounted)
        setState(() {
          _bytes = bytes;
          _loading = false;
        });
    } catch (_) {
      if (mounted)
        setState(() {
          _error = true;
          _loading = false;
        });
    }
  }

  Future<void> _toggle() async {
    if (_bytes == null) return;
    if (_playing) {
      await _player.pause();
    } else {
      await _player.play(BytesSource(_bytes!));
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  String _fmt(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.primary;
    if (_loading)
      return const SizedBox(
        height: 36,
        width: 36,
        child: Center(child: ShimmerSpinner(size: 24)),
      );
    if (_error) return Icon(Iconsax.danger, color: color);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          icon: Icon(
            _playing ? Iconsax.pause_circle_copy : Iconsax.play_circle_copy,
            color: color,
            size: 32,
          ),
          onPressed: _toggle,
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 110,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(
                value: _duration.inMilliseconds > 0
                    ? _position.inMilliseconds / _duration.inMilliseconds
                    : 0,
                color: color,
                backgroundColor: color.withValues(alpha: 0.2),
                minHeight: 3,
              ),
              const SizedBox(height: 3),
              Text(
                _duration.inMilliseconds > 0
                    ? '${_fmt(_position)} / ${_fmt(_duration)}'
                    : 'ভয়েস মেসেজ',
                style: TextStyle(fontSize: 10, color: color),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
