import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/network/error_helper.dart';
import '../../core/security/duress_service.dart';
import '../../core/storage/device_name_service.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/session_provider.dart';
import '../../services/auth_service.dart';
import '../../widgets/error_message_box.dart';
import '../../widgets/password_field.dart';
import 'password_reset_screen.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _password = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _submit() async {
    final session = context.read<SessionProvider>();
    final role = session.role;
    final spouseId = session.spouseId;
    if (role == null || spouseId == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      if (await DuressService.matches(_password.text, spouseId)) {
        session.enterDecoyMode();
        return;
      }
      final deviceName = await DeviceNameService.detect();
      final result = await AuthService().loginPassword(
        role: role,
        password: _password.text,
        deviceName: deviceName,
      );
      // Face verification is disabled app-wide for now (see DECISIONS.md) --
      // password alone always completes login, even if a profile still has
      // an old server-side face_verification_enabled flag set from before
      // this was turned off, since there's no longer any UI to re-enable
      // it or capture a face at all.
      await session.completeLogin(
        accessToken: result['access_token'],
        refreshToken: result['refresh_token'],
        role: result['role'],
        spouseId: result['spouse_id'],
        deviceId: result['device_id'],
      );
    } catch (e) {
      setState(() => _error = describeApiError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
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
              Icon(
                role == 'husband' ? Iconsax.man : Iconsax.woman,
                size: 56,
                color: AppColors.halalGreen,
              ),
              const SizedBox(height: 8),
              Text(
                role == 'husband'
                    ? 'ফিরে আসার জন্য স্বাগতম'
                    : 'ফিরে আসার জন্য স্বাগতম',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              const Text(
                'আপনার পাসওয়ার্ড দিন',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 24),
              PasswordField(
                controller: _password,
                labelText: 'পাসওয়ার্ড',
                autofocus: true,
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 16),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: ErrorMessageBox(_error!, textAlign: TextAlign.center),
                ),
              ElevatedButton(
                onPressed: _loading ? null : _submit,
                child: _loading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('পরবর্তী'),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PasswordResetScreen(role: role),
                  ),
                ),
                child: const Text('পাসওয়ার্ড ভুলে গেছেন?'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
