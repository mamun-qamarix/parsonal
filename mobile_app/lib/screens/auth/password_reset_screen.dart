import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../providers/session_provider.dart';
import '../../services/auth_service.dart';
import 'face_capture_screen.dart';

/// Password reset requires BOTH spouses to independently pass face
/// verification before a new password can be set (see project.md §6). Each
/// spouse does their own "Verify my face" step, on their own device, using
/// the same shared reset token.
class PasswordResetScreen extends StatefulWidget {
  final String role; // whose password is being reset
  const PasswordResetScreen({super.key, required this.role});

  @override
  State<PasswordResetScreen> createState() => _PasswordResetScreenState();
}

class _PasswordResetScreenState extends State<PasswordResetScreen> {
  final _tokenController = TextEditingController();
  final _newPassword = TextEditingController();
  bool _husbandVerified = false;
  bool _wifeVerified = false;
  bool _loading = false;
  String? _message;

  Future<void> _start() async {
    setState(() => _loading = true);
    try {
      final result = await AuthService().passwordResetInitiate(widget.role);
      _tokenController.text = result['reset_token'];
      setState(() => _message = 'Share this code with your spouse so they can verify on their own phone too.');
    } catch (_) {
      setState(() => _message = 'Could not start password reset.');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _verifyMyFace() async {
    final myRole = context.read<SessionProvider>().role ?? widget.role;
    if (_tokenController.text.isEmpty) {
      setState(() => _message = 'Enter the reset code first.');
      return;
    }
    final bytes = await Navigator.of(context).push<dynamic>(MaterialPageRoute(builder: (_) => const FaceCaptureScreen()));
    if (bytes == null) return;
    setState(() => _loading = true);
    try {
      final result = await AuthService().passwordResetVerifyFace(resetToken: _tokenController.text.trim(), role: myRole, jpegBytes: bytes);
      setState(() {
        _husbandVerified = result['husband_verified'] == true;
        _wifeVerified = result['wife_verified'] == true;
        _message = 'Verified.';
      });
    } catch (_) {
      setState(() => _message = 'Face verification failed.');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _complete() async {
    if (_newPassword.text.length < 8) {
      setState(() => _message = 'New password must be at least 8 characters.');
      return;
    }
    setState(() => _loading = true);
    try {
      await AuthService().passwordResetComplete(resetToken: _tokenController.text.trim(), newPassword: _newPassword.text);
      if (!mounted) return;
      setState(() => _message = 'Password changed. Go back and log in with the new password.');
    } catch (_) {
      setState(() => _message = 'Could not complete reset — make sure both spouses have verified.');
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bothVerified = _husbandVerified && _wifeVerified;
    return Scaffold(
      appBar: AppBar(title: const Text('Reset password')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Resetting the ${widget.role} password requires both of you to verify your face.', style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 20),
              OutlinedButton(onPressed: _loading ? null : _start, child: const Text('Start reset / get code')),
              const SizedBox(height: 12),
              TextField(controller: _tokenController, decoration: const InputDecoration(labelText: 'Reset code')),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: _loading ? null : _verifyMyFace, child: const Text('Verify my face')),
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(Icons.man, color: _husbandVerified ? AppColors.halalGreen : Colors.grey),
                  const SizedBox(width: 4),
                  const Text('Husband'),
                  const SizedBox(width: 16),
                  Icon(Icons.woman, color: _wifeVerified ? AppColors.halalGreen : Colors.grey),
                  const SizedBox(width: 4),
                  const Text('Wife'),
                ],
              ),
              const SizedBox(height: 20),
              if (bothVerified) ...[
                TextField(controller: _newPassword, obscureText: true, decoration: const InputDecoration(labelText: 'New password')),
                const SizedBox(height: 12),
                ElevatedButton(onPressed: _loading ? null : _complete, child: const Text('Set new password')),
              ],
              if (_message != null) ...[
                const SizedBox(height: 16),
                Text(_message!, textAlign: TextAlign.center),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
