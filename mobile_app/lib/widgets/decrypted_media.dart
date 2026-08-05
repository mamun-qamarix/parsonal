import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../core/media/video_thumbnail_helper.dart';
import '../core/theme/app_theme.dart';
import '../providers/session_provider.dart';
import '../services/media_service.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

class _DecryptedMediaCache {
  static final Map<String, Uint8List> _cache = {};

  static Future<Uint8List> get(
    String key,
    Future<Uint8List> Function() loader,
  ) async {
    final cached = _cache[key];
    if (cached != null) return cached;
    final data = await loader();
    _cache[key] = data;
    return data;
  }
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
  const DecryptedThumbnail({
    super.key,
    required this.assetId,
    required this.hasThumbnail,
    this.isVideo = false,
    this.fit = BoxFit.cover,
  });

  @override
  State<DecryptedThumbnail> createState() => _DecryptedThumbnailState();
}

class _DecryptedThumbnailState extends State<DecryptedThumbnail> {
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
    final vmk = context.read<SessionProvider>().vmk!;
    final service = MediaService();
    return FutureBuilder<Uint8List>(
      future: _DecryptedMediaCache.get(
        'thumb:${widget.assetId}',
        () => _load(vmk, service),
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Container(
            color: Colors.grey.withValues(alpha: 0.15),
            child: const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return Container(
            color: Colors.grey.withValues(alpha: 0.15),
            child: Icon(widget.isVideo ? Iconsax.video : Iconsax.gallery_slash),
          );
        }
        return Image.memory(snapshot.data!, fit: widget.fit);
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
class DecryptedFullImage extends StatelessWidget {
  final String assetId;
  final BoxFit fit;
  final bool zoomable;
  const DecryptedFullImage({
    super.key,
    required this.assetId,
    this.fit = BoxFit.contain,
    this.zoomable = true,
  });

  @override
  Widget build(BuildContext context) {
    final vmk = context.read<SessionProvider>().vmk!;
    final service = MediaService();
    return FutureBuilder<Uint8List>(
      future: _DecryptedMediaCache.get(
        'full:$assetId',
        () => service.downloadRaw(vmk, assetId),
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return const Center(child: Icon(Iconsax.gallery_slash, size: 48));
        }
        final image = Image.memory(snapshot.data!, fit: fit);
        return zoomable ? InteractiveViewer(child: image) : image;
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
/// bare play/pause toggle with no way to scrub through a longer video. If
/// [onTrimRequested] is given, a scissor button also appears that hands the
/// caller the local decrypted file path so it can open a trim UI (kept out
/// of this widget since what happens with the trimmed result -- save as a
/// new vault entry vs. a new chat message -- is caller-specific). See
/// DECISIONS.md.
class DecryptedVideoPlayer extends StatefulWidget {
  final String assetId;
  final void Function(String localVideoPath)? onTrimRequested;
  const DecryptedVideoPlayer({
    super.key,
    required this.assetId,
    this.onTrimRequested,
  });

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
      final file = await _writeTempFile(widget.assetId, bytes);
      final controller = VideoPlayerController.file(file);
      await controller.initialize();
      controller.addListener(_onTick);
      if (!mounted) return;
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
    final file = File('${dir.path}/vault_video_$assetId.mp4');
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
      return const Center(child: CircularProgressIndicator());
    }
    final position = controller.value.position;
    final duration = controller.value.duration;
    return AspectRatio(
      aspectRatio: controller.value.aspectRatio,
      child: Stack(
        alignment: Alignment.center,
        children: [
          VideoPlayer(controller),
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
                  if (widget.onTrimRequested != null) ...[
                    const SizedBox(width: 4),
                    IconButton(
                      tooltip: 'ভিডিও ক্লিপ করুন',
                      iconSize: 20,
                      color: Colors.white,
                      icon: const Icon(Iconsax.scissor),
                      onPressed: () {
                        final file = _tempFile;
                        if (file != null) widget.onTrimRequested!(file.path);
                      },
                    ),
                  ],
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
    final color = widget.color ?? AppColors.halalGreen;
    if (_loading)
      return const SizedBox(
        height: 36,
        width: 36,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
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
