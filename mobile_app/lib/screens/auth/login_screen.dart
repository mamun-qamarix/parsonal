import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/security/duress_service.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/session_provider.dart';
import '../../services/auth_service.dart';
import 'password_reset_screen.dart';

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
      final challenge = await AuthService().loginPassword(role: role, password: _password.text, deviceName: 'this phone');
      session.setPendingChallenge(challenge);
    } catch (e) {
      setState(() => _error = 'Incorrect password, or the server is unreachable.');
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
              Icon(role == 'husband' ? Icons.man : Icons.woman, size: 56, color: AppColors.halalGreen),
              const SizedBox(height: 8),
              Text('Welcome back, ${role[0].toUpperCase()}${role.substring(1)}', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 24),
              TextField(
                controller: _password,
                obscureText: true,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Password'),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 16),
              if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(_error!, style: const TextStyle(color: Colors.red))),
              ElevatedButton(
                onPressed: _loading ? null : _submit,
                child: _loading ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Continue'),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PasswordResetScreen(role: role))),
                child: const Text('Forgot password?'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
