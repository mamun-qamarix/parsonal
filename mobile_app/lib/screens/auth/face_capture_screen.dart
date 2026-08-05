import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../../core/theme/app_theme.dart';

enum _LivenessStage { waitingOpenEyes, waitingBlink, done }

/// Captures a single still frame from the front camera after confirming a
/// blink (simple, fully on-device liveness check — see DECISIONS.md §7).
/// Pops with the captured JPEG bytes, or null if the user backs out.
///
/// Uses repeated still captures (takePicture + InputImage.fromFilePath)
/// rather than a raw camera image stream: decoding a normal JPEG file is
/// far more reliable across real devices than manually converting each
/// platform's raw YUV/NV21 frame format, which varies enough between
/// devices/CameraX versions to silently fail on some phones.
class FaceCaptureScreen extends StatefulWidget {
  final String title;
  final String instructions;
  const FaceCaptureScreen({
    super.key,
    this.title = 'মুখ যাচাই',
    this.instructions =
        'ক্যামেরার দিকে সরাসরি তাকান, তারপর স্বাভাবিকভাবে চোখের পলক ফেলুন',
  });

  @override
  State<FaceCaptureScreen> createState() => _FaceCaptureScreenState();
}

class _FaceCaptureScreenState extends State<FaceCaptureScreen> {
  CameraController? _controller;
  late final FaceDetector _detector;
  _LivenessStage _stage = _LivenessStage.waitingOpenEyes;
  bool _checking = false;
  bool _done = false;
  String _hint = 'ক্যামেরা প্রস্তুত হচ্ছে...';
  Timer? _pollTimer;
  Timer? _timeoutTimer;

  @override
  void initState() {
    super.initState();
    _detector = FaceDetector(
      options: FaceDetectorOptions(
        enableClassification: true,
        performanceMode: FaceDetectorMode.accurate,
      ),
    );
    _init();
  }

  Future<void> _init() async {
    final cameras = await availableCameras();
    final front = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );
    final controller = CameraController(
      front,
      ResolutionPreset.medium,
      enableAudio: false,
    );
    await controller.initialize();
    if (!mounted) {
      await controller.dispose();
      return;
    }
    setState(() {
      _controller = controller;
      _hint = 'আপনার মুখ ফ্রেমের মাঝখানে রাখুন';
    });
    _pollTimer = Timer.periodic(
      const Duration(milliseconds: 900),
      (_) => _checkOnce(),
    );
    _timeoutTimer = Timer(const Duration(seconds: 60), () {
      if (mounted && !_done) {
        Navigator.of(context).pop(null);
      }
    });
  }

  Future<void> _checkOnce() async {
    if (_checking ||
        _done ||
        _controller == null ||
        !_controller!.value.isInitialized)
      return;
    _checking = true;
    XFile? file;
    try {
      file = await _controller!.takePicture();
      final inputImage = InputImage.fromFilePath(file.path);
      final faces = await _detector.processImage(inputImage);

      if (faces.isEmpty) {
        if (mounted)
          setState(
            () => _hint = 'কোনো মুখ দেখা যাচ্ছে না — ক্যামেরার দিকে তাকান',
          );
        return;
      }
      final face = faces.first;
      final leftOpen = face.leftEyeOpenProbability;
      final rightOpen = face.rightEyeOpenProbability;
      if (leftOpen == null || rightOpen == null) {
        if (mounted) setState(() => _hint = 'স্থির থাকুন...');
        return;
      }
      final avgOpen = (leftOpen + rightOpen) / 2;

      if (_stage == _LivenessStage.waitingOpenEyes) {
        if (avgOpen > 0.6) {
          _stage = _LivenessStage.waitingBlink;
          if (mounted)
            setState(() => _hint = 'ভালো — এবার একবার চোখের পলক ফেলুন');
        } else {
          if (mounted) setState(() => _hint = 'চোখ খুলে ক্যামেরার দিকে তাকান');
        }
      } else if (_stage == _LivenessStage.waitingBlink) {
        if (avgOpen < 0.35) {
          _stage = _LivenessStage.done;
          _done = true;
          _pollTimer?.cancel();
          _timeoutTimer?.cancel();
          if (mounted) setState(() => _hint = '✓ সফল হয়েছে!');
          await Future.delayed(const Duration(milliseconds: 700));
          final bytes = await File(file.path).readAsBytes();
          if (mounted) Navigator.of(context).pop(bytes);
          return;
        }
      }
    } catch (_) {
      // Ignore a single failed check — the next poll tick will retry.
    } finally {
      final leftover = file;
      if (leftover != null && !_done) {
        // Clean up intermediate captures; the final success frame is read
        // and popped above before this runs (guarded by _done).
        File(leftover.path).delete().catchError((_) => File(leftover.path));
      }
      _checking = false;
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _timeoutTimer?.cancel();
    _controller?.dispose();
    _detector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        alignment: Alignment.center,
        children: [
          if (controller != null && controller.value.isInitialized)
            Center(
              child: ClipRect(
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    // camera plugin reports size/aspectRatio in the sensor's
                    // landscape orientation; swapping width/height here is
                    // what keeps a front-facing portrait preview from
                    // looking squished.
                    width: controller.value.previewSize?.height ?? 1,
                    height: controller.value.previewSize?.width ?? 1,
                    child: CameraPreview(controller),
                  ),
                ),
              ),
            )
          else
            const CircularProgressIndicator(color: AppColors.halalGreen),
          Positioned(
            bottom: 60,
            left: 24,
            right: 24,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.instructions,
                    style: const TextStyle(color: Colors.white70),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _hint,
                    style: TextStyle(
                      color: _done ? AppColors.halalGreenDark : Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
