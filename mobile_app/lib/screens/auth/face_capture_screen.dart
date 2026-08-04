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
class FaceCaptureScreen extends StatefulWidget {
  final String title;
  final String instructions;
  const FaceCaptureScreen({super.key, this.title = 'Face verification', this.instructions = 'Look at the camera and blink naturally'});

  @override
  State<FaceCaptureScreen> createState() => _FaceCaptureScreenState();
}

class _FaceCaptureScreenState extends State<FaceCaptureScreen> {
  CameraController? _controller;
  late final FaceDetector _detector;
  _LivenessStage _stage = _LivenessStage.waitingOpenEyes;
  bool _busy = false;
  bool _capturing = false;
  String _hint = 'Getting camera ready...';
  Timer? _timeoutTimer;

  @override
  void initState() {
    super.initState();
    _detector = FaceDetector(
      options: FaceDetectorOptions(enableClassification: true, performanceMode: FaceDetectorMode.fast),
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
      imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
    );
    await controller.initialize();
    if (!mounted) {
      await controller.dispose();
      return;
    }
    setState(() {
      _controller = controller;
      _hint = 'Look at the camera';
    });
    await controller.startImageStream(_onFrame);
    _timeoutTimer = Timer(const Duration(seconds: 45), () {
      if (mounted && _stage != _LivenessStage.done) {
        Navigator.of(context).pop(null);
      }
    });
  }

  Future<void> _onFrame(CameraImage image) async {
    if (_busy || _capturing || _controller == null) return;
    _busy = true;
    try {
      final inputImage = _toInputImage(image, _controller!.description);
      if (inputImage == null) return;
      final faces = await _detector.processImage(inputImage);
      if (faces.isEmpty) {
        if (mounted) setState(() => _hint = 'No face detected — center your face in frame');
        return;
      }
      final face = faces.first;
      final leftOpen = face.leftEyeOpenProbability;
      final rightOpen = face.rightEyeOpenProbability;
      if (leftOpen == null || rightOpen == null) {
        if (mounted) setState(() => _hint = 'Hold still...');
        return;
      }
      final avgOpen = (leftOpen + rightOpen) / 2;

      if (_stage == _LivenessStage.waitingOpenEyes) {
        if (avgOpen > 0.6) {
          _stage = _LivenessStage.waitingBlink;
          if (mounted) setState(() => _hint = 'Great — now blink');
        } else {
          if (mounted) setState(() => _hint = 'Open your eyes and look at the camera');
        }
      } else if (_stage == _LivenessStage.waitingBlink) {
        if (avgOpen < 0.3) {
          _stage = _LivenessStage.done;
          if (mounted) setState(() => _hint = 'Blink detected — capturing...');
          await _captureStill();
        }
      }
    } catch (_) {
      // Ignore transient per-frame processing errors.
    } finally {
      _busy = false;
    }
  }

  Future<void> _captureStill() async {
    if (_capturing || _controller == null) return;
    _capturing = true;
    try {
      await _controller!.stopImageStream();
      final file = await _controller!.takePicture();
      final bytes = await File(file.path).readAsBytes();
      if (mounted) Navigator.of(context).pop(bytes);
    } catch (_) {
      if (mounted) Navigator.of(context).pop(null);
    }
  }

  InputImage? _toInputImage(CameraImage image, CameraDescription camera) {
    final rotation = InputImageRotationValue.fromRawValue(camera.sensorOrientation) ?? InputImageRotation.rotation0deg;
    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null) return null;
    if (image.planes.isEmpty) return null;
    final plane = image.planes.first;
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  @override
  void dispose() {
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
      appBar: AppBar(title: Text(widget.title), backgroundColor: Colors.black, foregroundColor: Colors.white),
      body: Stack(
        alignment: Alignment.center,
        children: [
          if (controller != null && controller.value.isInitialized)
            Center(child: AspectRatio(aspectRatio: controller.value.aspectRatio, child: CameraPreview(controller)))
          else
            const CircularProgressIndicator(color: AppColors.halalGreen),
          Positioned(
            bottom: 60,
            left: 24,
            right: 24,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(14)),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(widget.instructions, style: const TextStyle(color: Colors.white70), textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  Text(_hint, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
