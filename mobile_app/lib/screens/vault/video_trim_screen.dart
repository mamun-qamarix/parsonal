import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:video_trimmer/video_trimmer.dart';

import '../../core/theme/app_theme.dart';

/// Lets the user pick a start/end range out of an already-decrypted local
/// video file and export just that range as a new, shorter clip.
/// `video_trimmer` 5.x trims natively (no FFmpeg, see DECISIONS.md) so this
/// works entirely offline before anything is re-encrypted/re-uploaded.
/// Pops with the trimmed clip's bytes (or null if the user backs out) --
/// what to do with them (save as a new vault entry, a new chat message,
/// etc.) is entirely up to the caller.
class VideoTrimScreen extends StatefulWidget {
  final String sourceVideoPath;
  const VideoTrimScreen({super.key, required this.sourceVideoPath});

  @override
  State<VideoTrimScreen> createState() => _VideoTrimScreenState();
}

class _VideoTrimScreenState extends State<VideoTrimScreen> {
  final _trimmer = Trimmer();
  double _startValue = 0;
  double _endValue = 0;
  bool _playing = false;
  bool _loaded = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await _trimmer.loadVideo(videoFile: File(widget.sourceVideoPath));
    if (mounted) setState(() => _loaded = true);
  }

  Future<void> _togglePlayback() async {
    final playing = await _trimmer.videoPlaybackControl(
      startValue: _startValue,
      endValue: _endValue,
    );
    if (mounted) setState(() => _playing = playing);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      String? outputPath;
      await _trimmer.saveTrimmedVideo(
        startValue: _startValue,
        endValue: _endValue,
        onSave: (path) => outputPath = path,
      );
      if (outputPath == null) throw Exception('Trim produced no output');
      final Uint8List bytes = await File(outputPath!).readAsBytes();
      if (mounted) Navigator.of(context).pop(bytes);
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('ক্লিপ তৈরি করা যায়নি, আবার চেষ্টা করুন।')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('ভিডিও ক্লিপ করুন'),
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator(color: AppColors.halalGreen))
          : SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: Center(
                      child: GestureDetector(
                        onTap: _togglePlayback,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            VideoViewer(trimmer: _trimmer),
                            if (!_playing)
                              const Icon(Iconsax.play_circle, color: Colors.white70, size: 48),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'অংশটা টেনে বেছে নিন, তারপর সেভ করুন',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: TrimViewer(
                      trimmer: _trimmer,
                      viewerHeight: 50,
                      durationStyle: DurationStyle.FORMAT_MM_SS,
                      maxVideoLength: const Duration(seconds: 60),
                      onChangeStart: (v) => _startValue = v,
                      onChangeEnd: (v) => _endValue = v,
                      onChangePlaybackState: (playing) {
                        if (mounted) setState(() => _playing = playing);
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: ElevatedButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Iconsax.scissor),
                      label: Text(_saving ? 'ক্লিপ তৈরি হচ্ছে...' : 'ক্লিপ সেভ করুন'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  @override
  void dispose() {
    _trimmer.dispose();
    super.dispose();
  }
}
