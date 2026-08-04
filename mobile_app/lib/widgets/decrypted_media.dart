import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

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

class DecryptedFullImage extends StatelessWidget {
  final String assetId;
  const DecryptedFullImage({super.key, required this.assetId});

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
        return InteractiveViewer(child: Image.memory(snapshot.data!));
      },
    );
  }
}

/// Decrypts a video into a temp buffer and plays it via VideoPlayer's
/// bytes-backed data source.
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
