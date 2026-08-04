import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../providers/session_provider.dart';
import '../../services/auth_service.dart';
import 'face_capture_screen.dart';

class FaceEnrollScreen extends StatefulWidget {
  const FaceEnrollScreen({super.key});

  @override
  State<FaceEnrollScreen> createState() => _FaceEnrollScreenState();
}

class _FaceEnrollScreenState extends State<FaceEnrollScreen> {
  bool _loading = false;
  String? _error;

  Future<void> _start() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final bytes = await Navigator.of(context).push<dynamic>(MaterialPageRoute(
        builder: (_) => const FaceCaptureScreen(title: 'Register your face', instructions: 'This is how you\'ll unlock the app each time'),
      ));
      if (bytes == null) {
        setState(() => _loading = false);
        return;
      }
      await AuthService().enrollFace(bytes);
      if (!mounted) return;
      context.read<SessionProvider>().markFaceEnrolled();
    } catch (e) {
      setState(() => _error = 'Face registration failed. Make sure the backend and face-recognition service are reachable, then try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Register your face')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.face_retouching_natural, size: 64, color: AppColors.halalGreen),
              const SizedBox(height: 16),
              const Text(
                'Every time you open the app, you\'ll need your password and your face — both, every time. '
                'This keeps your private space private, even if someone else has your phone unlocked.',
              ),
              const SizedBox(height: 24),
              if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(_error!, style: const TextStyle(color: Colors.red))),
              ElevatedButton.icon(
                icon: const Icon(Icons.camera_alt),
                onPressed: _loading ? null : _start,
                label: _loading ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Start face registration'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
