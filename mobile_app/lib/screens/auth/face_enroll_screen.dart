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
        builder: (_) => const FaceCaptureScreen(title: 'মুখ রেজিস্ট্রেশন', instructions: 'এভাবেই প্রতিবার অ্যাপ আনলক করবেন — ক্যামেরার দিকে তাকান, তারপর চোখের পলক ফেলুন'),
      ));
      if (bytes == null) {
        setState(() => _loading = false);
        return;
      }
      await AuthService().enrollFace(bytes);
      if (!mounted) return;
      context.read<SessionProvider>().markFaceEnrolled();
    } catch (e) {
      setState(() => _error = 'মুখ রেজিস্ট্রেশন ব্যর্থ হয়েছে। ব্যাকএন্ড ও ফেস-ভেরিফিকেশন সার্ভিস চালু আছে কিনা দেখে আবার চেষ্টা করুন।');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('আপনার মুখ রেজিস্টার করুন')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.face_retouching_natural, size: 64, color: AppColors.halalGreen),
              const SizedBox(height: 16),
              const Text(
                'প্রতিবার অ্যাপ খুলতে আপনার পাসওয়ার্ড আর মুখ — দুটোই লাগবে। এতে আপনার প্রাইভেট জায়গাটা সত্যিকার অর্থেই প্রাইভেট থাকে, ফোন খোলা থাকলেও অন্য কেউ ঢুকতে পারবে না।',
              ),
              const SizedBox(height: 12),
              const Text(
                'পরের স্ক্রিনে ক্যামেরা খুলবে — সরাসরি তাকিয়ে থেকে স্বাভাবিকভাবে একবার চোখের পলক ফেললেই হবে।',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 24),
              if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(_error!, style: const TextStyle(color: Colors.red))),
              ElevatedButton.icon(
                icon: const Icon(Icons.camera_alt),
                onPressed: _loading ? null : _start,
                label: _loading ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('মুখ রেজিস্ট্রেশন শুরু করুন'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
