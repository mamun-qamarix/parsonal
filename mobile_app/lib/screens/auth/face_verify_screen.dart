import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../providers/session_provider.dart';
import '../../services/auth_service.dart';
import 'face_capture_screen.dart';

class FaceVerifyScreen extends StatefulWidget {
  const FaceVerifyScreen({super.key});

  @override
  State<FaceVerifyScreen> createState() => _FaceVerifyScreenState();
}

class _FaceVerifyScreenState extends State<FaceVerifyScreen> {
  bool _loading = false;
  String? _error;

  Future<void> _start() async {
    final session = context.read<SessionProvider>();
    final challenge = session.pendingChallengeToken;
    if (challenge == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final bytes = await Navigator.of(context).push<dynamic>(MaterialPageRoute(
        builder: (_) => const FaceCaptureScreen(),
      ));
      if (bytes == null) {
        setState(() => _loading = false);
        return;
      }
      final result = await AuthService().loginFace(challengeToken: challenge, jpegBytes: bytes);
      if (!mounted) return;
      await session.completeLogin(
        accessToken: result['access_token'],
        refreshToken: result['refresh_token'],
        role: result['role'],
        spouseId: result['spouse_id'],
      );
    } catch (e) {
      setState(() => _error = 'মুখ মেলেনি। আবার চেষ্টা করুন।');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('মুখ যাচাই')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.face, size: 64, color: AppColors.halalGreen),
              const SizedBox(height: 16),
              const Text('এবার নিশ্চিত করুন সত্যিই আপনি এসেছেন।', textAlign: TextAlign.center),
              const SizedBox(height: 24),
              if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(_error!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center)),
              ElevatedButton.icon(
                icon: const Icon(Icons.camera_alt),
                onPressed: _loading ? null : _start,
                label: _loading ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('মুখ দিয়ে যাচাই করুন'),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => context.read<SessionProvider>().cancelFaceVerify(),
                child: const Text('পেছনে যান'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
