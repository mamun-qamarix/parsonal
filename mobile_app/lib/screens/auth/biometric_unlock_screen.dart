import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/security/biometric_service.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/session_provider.dart';
import '../../widgets/error_message_box.dart';

/// Shown when it's been under an hour since the last password entry --
/// just a fingerprint/face/device-PIN tap gets back in, no password
/// needed. Purely local (see SessionProvider.completeBiometricUnlock).
/// See DECISIONS.md #27.
class BiometricUnlockScreen extends StatefulWidget {
  const BiometricUnlockScreen({super.key});

  @override
  State<BiometricUnlockScreen> createState() => _BiometricUnlockScreenState();
}

class _BiometricUnlockScreenState extends State<BiometricUnlockScreen> {
  bool _checking = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryUnlock());
  }

  Future<void> _tryUnlock() async {
    if (_checking) return;
    setState(() {
      _checking = true;
      _error = null;
    });
    final ok = await BiometricService.authenticate();
    if (!mounted) return;
    if (ok) {
      context.read<SessionProvider>().completeBiometricUnlock();
    } else {
      setState(() {
        _checking = false;
        _error = 'যাচাই করা যায়নি — আবার চেষ্টা করুন, অথবা পাসওয়ার্ড দিয়ে ঢুকুন।';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = context.watch<SessionProvider>().role ?? '';
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.fingerprint, size: 72, color: AppColors.halalGreen),
              const SizedBox(height: 16),
              Text(
                role == 'husband' ? 'স্বাগতম, স্বামী' : (role == 'wife' ? 'স্বাগতম, স্ত্রী' : 'স্বাগতম'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              const Text('প্রবেশ করতে ফিঙ্গারপ্রিন্ট দিন', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 24),
              if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: ErrorMessageBox(_error!, textAlign: TextAlign.center)),
              ElevatedButton.icon(
                icon: const Icon(Icons.fingerprint),
                onPressed: _checking ? null : _tryUnlock,
                label: _checking
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('আবার চেষ্টা করুন'),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => context.read<SessionProvider>().useFallbackPassword(),
                child: const Text('পাসওয়ার্ড দিয়ে ঢুকুন'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
