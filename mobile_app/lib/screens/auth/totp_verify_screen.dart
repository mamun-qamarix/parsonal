import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/network/error_helper.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/session_provider.dart';
import '../../services/auth_service.dart';
import '../../widgets/error_message_box.dart';

/// Second mandatory login step: enter the current code from the
/// authenticator app. If face verification is also enabled for this
/// spouse, a face-verify step follows; otherwise this completes login.
class TotpVerifyScreen extends StatefulWidget {
  const TotpVerifyScreen({super.key});

  @override
  State<TotpVerifyScreen> createState() => _TotpVerifyScreenState();
}

class _TotpVerifyScreenState extends State<TotpVerifyScreen> {
  final _codeController = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _submit() async {
    final session = context.read<SessionProvider>();
    final challenge = session.pendingTotpChallengeToken;
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
      final result = await AuthService().loginTotp(challengeToken: challenge, code: _codeController.text.trim());
      if (!mounted) return;
      if (result['requires_face'] == true) {
        session.setPendingFaceChallenge(result['face_challenge_token']);
      } else {
        await session.completeLogin(
          accessToken: result['access_token'],
          refreshToken: result['refresh_token'],
          role: result['role'],
          spouseId: result['spouse_id'],
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
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.pin_outlined, size: 56, color: AppColors.halalGreen),
              const SizedBox(height: 12),
              const Text('আপনার অথেন্টিকেটর অ্যাপে দেখানো ৬ সংখ্যার কোডটা দিন', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 20),
              TextField(
                controller: _codeController,
                keyboardType: TextInputType.number,
                maxLength: 6,
                autofocus: true,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 24, letterSpacing: 8),
                decoration: const InputDecoration(counterText: ''),
                onSubmitted: (_) => _submit(),
              ),
              if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: ErrorMessageBox(_error!, textAlign: TextAlign.center)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loading ? null : _submit,
                child: _loading ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('পরবর্তী'),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => context.read<SessionProvider>().cancelTotpVerify(),
                child: const Text('পেছনে যান'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
