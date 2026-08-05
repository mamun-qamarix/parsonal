import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../core/theme/app_theme.dart';
import '../providers/session_provider.dart';
import '../services/media_service.dart';

class _DecryptedMediaCache {
  static final Map<String, Uint8List> _cache = {};

  static Future<Uint8List> get(String key, Future<Uint8List> Function() loader) async {
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
class DecryptedThumbnail extends StatelessWidget {
  final String assetId;
  final bool hasThumbnail;
  final BoxFit fit;
  const DecryptedThumbnail({super.key, required this.assetId, required this.hasThumbnail, this.fit = BoxFit.cover});

  @override
  Widget build(BuildContext context) {
    final vmk = context.read<SessionProvider>().vmk!;
    final service = MediaService();
    return FutureBuilder<Uint8List>(
      future: _DecryptedMediaCache.get(
        'thumb:$assetId',
        () => hasThumbnail ? service.downloadThumbnail(vmk, assetId) : service.downloadRaw(vmk, assetId),
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Container(color: Colors.grey.withValues(alpha: 0.15), child: const Center(child: CircularProgressIndicator(strokeWidth: 2)));
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return Container(color: Colors.grey.withValues(alpha: 0.15), child: const Icon(Icons.broken_image_outlined));
        }
        return Image.memory(snapshot.data!, fit: fit);
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
  const DecryptedFullImage({super.key, required this.assetId, this.fit = BoxFit.contain, this.zoomable = true});

  @override
  Widget build(BuildContext context) {
    final vmk = context.read<SessionProvider>().vmk!;
    final service = MediaService();
    return FutureBuilder<Uint8List>(
      future: _DecryptedMediaCache.get('full:$assetId', () => service.downloadRaw(vmk, assetId)),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return const Center(child: Icon(Icons.broken_image_outlined, size: 48));
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
class DecryptedVideoPlayer extends StatefulWidget {
  final String assetId;
  const DecryptedVideoPlayer({super.key, required this.assetId});

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
      final bytes = await _DecryptedMediaCache.get('full:${widget.assetId}', () => MediaService().downloadRaw(vmk, widget.assetId));
      final file = await _writeTempFile(widget.assetId, bytes);
      final controller = VideoPlayerController.file(file);
      await controller.initialize();
      if (!mounted) return;
      setState(() {
        _controller = controller;
        _tempFile = file;
      });
    } catch (_) {
      if (mounted) setState(() => _error = true);
    }
  }

  Future<File> _writeTempFile(String assetId, Uint8List bytes) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/vault_video_$assetId.mp4');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  @override
  Widget build(BuildContext context) {
    if (_error) return const Center(child: Icon(Icons.error_outline));
    final controller = _controller;
    if (controller == null) return const Center(child: CircularProgressIndicator());
    return AspectRatio(
      aspectRatio: controller.value.aspectRatio,
      child: Stack(
        alignment: Alignment.center,
        children: [
          VideoPlayer(controller),
          IconButton(
            iconSize: 56,
            color: Colors.white,
            icon: Icon(controller.value.isPlaying ? Icons.pause_circle : Icons.play_circle),
            onPressed: () => setState(() => controller.value.isPlaying ? controller.pause() : controller.play()),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
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
      final bytes = await _DecryptedMediaCache.get('full:${widget.assetId}', () => MediaService().downloadRaw(vmk, widget.assetId));
      if (mounted) setState(() { _bytes = bytes; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _error = true; _loading = false; });
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

  String _fmt(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? AppColors.halalGreen;
    if (_loading) return const SizedBox(height: 36, width: 36, child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
    if (_error) return Icon(Icons.error_outline, color: color);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          icon: Icon(_playing ? Icons.pause_circle_filled : Icons.play_circle_filled, color: color, size: 32),
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
                value: _duration.inMilliseconds > 0 ? _position.inMilliseconds / _duration.inMilliseconds : 0,
                color: color,
                backgroundColor: color.withValues(alpha: 0.2),
                minHeight: 3,
              ),
              const SizedBox(height: 3),
              Text(
                _duration.inMilliseconds > 0 ? '${_fmt(_position)} / ${_fmt(_duration)}' : 'ভয়েস মেসেজ',
                style: TextStyle(fontSize: 10, color: color),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
