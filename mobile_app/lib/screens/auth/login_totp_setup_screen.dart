import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/network/error_helper.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/session_provider.dart';
import '../../services/auth_service.dart';
import '../../widgets/error_message_box.dart';

/// This device has never confirmed its own authenticator entry before --
/// either a fresh install, or a device just paired onto an
/// already-claimed role (which shares the role's password but always gets
/// its own independent TOTP secret). Mirrors TotpSetupScreen's UI, but
/// confirms via /auth/login/totp-setup-confirm since there's no real
/// access token yet at this point in login. See DECISIONS.md #21.
class LoginTotpSetupScreen extends StatefulWidget {
  const LoginTotpSetupScreen({super.key});

  @override
  State<LoginTotpSetupScreen> createState() => _LoginTotpSetupScreenState();
}

class _LoginTotpSetupScreenState extends State<LoginTotpSetupScreen> {
  final _codeController = TextEditingController();
  bool _loading = false;
  String? _error;
  bool _showSecret = false;

  Future<void> _confirm() async {
    final session = context.read<SessionProvider>();
    final challenge = session.pendingLoginTotpSetupChallengeToken;
    if (challenge == null) return;
    if (_codeController.text.trim().length != 6) {
      setState(() => _error = 'কোডটা ৬ সংখ্যার হতে হবে।');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await AuthService().loginTotpSetupConfirm(challengeToken: challenge, code: _codeController.text.trim());
      if (!mounted) return;
      if (result['requires_face'] == true) {
        session.setPendingFaceChallenge(result['face_challenge_token']);
      } else {
        await session.completeLogin(
          accessToken: result['access_token'],
          refreshToken: result['refresh_token'],
          role: result['role'],
          spouseId: result['spouse_id'],
          deviceId: result['device_id'],
        );
      }
    } catch (e) {
      setState(() => _error = describeApiError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>();
    final uri = session.pendingLoginTotpSetupUri;
    final secret = session.pendingLoginTotpSetupSecret;

    return Scaffold(
      appBar: AppBar(
        title: const Text('এই ডিভাইসের জন্য অথেন্টিকেটর'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.read<SessionProvider>().cancelLoginTotpSetup(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.shield_outlined, size: 56, color: AppColors.halalGreen),
              const SizedBox(height: 12),
              const Text(
                'পাসওয়ার্ড ঠিক আছে। কিন্তু এই ফোনে আগে কখনো অথেন্টিকেটর কোড সেটআপ করা হয়নি — প্রতিটা ডিভাইসের নিজস্ব আলাদা অথেন্টিকেটর এন্ট্রি থাকে। এখন সেটা সেটআপ করে নিন।',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              const Text('১. আপনার ফোনে Google Authenticator বা Authy অ্যাপ না থাকলে আগে সেটা ইনস্টল করুন।', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              const Text('২. সেই অ্যাপ দিয়ে নিচের QR কোডটা স্ক্যান করুন:', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 16),
              if (uri != null)
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                    child: QrImageView(data: uri, size: 200, backgroundColor: Colors.white),
                  ),
                ),
              const SizedBox(height: 12),
              Center(
                child: TextButton(
                  onPressed: () => setState(() => _showSecret = !_showSecret),
                  child: Text(_showSecret ? 'কী লুকান' : 'স্ক্যান করতে না পারলে — কী হাতে টাইপ করুন'),
                ),
              ),
              if (_showSecret && secret != null)
                SelectableText(secret, textAlign: TextAlign.center, style: const TextStyle(fontFamily: 'monospace', fontSize: 16, letterSpacing: 2)),
              const SizedBox(height: 20),
              const Text('৩. অথেন্টিকেটর অ্যাপে এখন যে ৬ সংখ্যার কোডটা দেখাচ্ছে, সেটা এখানে লিখুন:', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              TextField(
                controller: _codeController,
                keyboardType: TextInputType.number,
                maxLength: 6,
                autofocus: true,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 24, letterSpacing: 8),
                decoration: const InputDecoration(counterText: ''),
                onSubmitted: (_) => _confirm(),
              ),
              if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: ErrorMessageBox(_error!, textAlign: TextAlign.center)),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _loading ? null : _confirm,
                child: _loading ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('নিশ্চিত করুন'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
