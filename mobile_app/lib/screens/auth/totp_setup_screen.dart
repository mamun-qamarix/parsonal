import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/network/error_helper.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/session_provider.dart';
import '../../services/auth_service.dart';

/// Mandatory one-time step after claiming a role: scan the TOTP secret into
/// an authenticator app (Google Authenticator, Authy, etc) and prove it by
/// entering one code back. See DECISIONS.md §13.
class TotpSetupScreen extends StatefulWidget {
  const TotpSetupScreen({super.key});

  @override
  State<TotpSetupScreen> createState() => _TotpSetupScreenState();
}

class _TotpSetupScreenState extends State<TotpSetupScreen> {
  final _codeController = TextEditingController();
  bool _loading = false;
  String? _error;
  bool _showSecret = false;

  Future<void> _confirm() async {
    if (_codeController.text.trim().length != 6) {
      setState(() => _error = 'কোডটা ৬ সংখ্যার হতে হবে।');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await AuthService().totpSetupConfirm(_codeController.text.trim());
      if (!mounted) return;
      context.read<SessionProvider>().completeTotpSetup();
    } catch (e) {
      setState(() => _error = describeApiError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>();
    final uri = session.pendingTotpProvisioningUri;
    final secret = session.pendingTotpSecret;

    return Scaffold(
      appBar: AppBar(title: const Text('অথেন্টিকেটর অ্যাপ যুক্ত করুন'), automaticallyImplyLeading: false),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.shield_outlined, size: 56, color: AppColors.halalGreen),
              const SizedBox(height: 12),
              const Text(
                'প্রতিবার লগইন করতে পাসওয়ার্ডের সাথে একটা ৬ সংখ্যার কোডও লাগবে — এটা আসে আপনার ফোনের একটা "অথেন্টিকেটর" অ্যাপ থেকে (যেমন Google Authenticator, Authy)। এখন সেটা সেটআপ করে নিন।',
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
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 24, letterSpacing: 8),
                decoration: const InputDecoration(counterText: ''),
                onSubmitted: (_) => _confirm(),
              ),
              if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center)),
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
