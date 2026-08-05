import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/network/error_helper.dart';
import '../../services/auth_service.dart';
import '../../widgets/error_message_box.dart';
import '../../widgets/password_field.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

/// Password reset needs approval from an already-authenticated device
/// (either spouse's, or the same person's other device) instead of an
/// authenticator code, which no longer exists (DECISIONS.md #27). This
/// screen generates the reset code and polls until it's been approved
/// from Settings -> "পাসওয়ার্ড রিসেট অনুমোদন করুন" on that other device.
class PasswordResetScreen extends StatefulWidget {
  final String role; // whose password is being reset
  const PasswordResetScreen({super.key, required this.role});

  @override
  State<PasswordResetScreen> createState() => _PasswordResetScreenState();
}

class _PasswordResetScreenState extends State<PasswordResetScreen> {
  final _newPassword = TextEditingController();
  String? _resetToken;
  bool _approved = false;
  bool _loading = false;
  String? _message;
  Timer? _pollTimer;

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _loading = true;
      _message = null;
    });
    try {
      final result = await AuthService().passwordResetInitiate(widget.role);
      _resetToken = result['reset_token'];
      _startPolling();
    } catch (e) {
      setState(() => _message = describeApiError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (_resetToken == null) return;
      try {
        final approved = await AuthService().passwordResetStatus(_resetToken!);
        if (approved && mounted) {
          setState(() => _approved = true);
          _pollTimer?.cancel();
        }
      } catch (_) {
        // Transient network hiccup while polling -- just try again next tick.
      }
    });
  }

  Future<void> _complete() async {
    if (_newPassword.text.length < 8) {
      setState(() => _message = 'নতুন পাসওয়ার্ড কমপক্ষে ৮ অক্ষরের হতে হবে।');
      return;
    }
    setState(() => _loading = true);
    try {
      await AuthService().passwordResetComplete(
        resetToken: _resetToken!,
        newPassword: _newPassword.text,
      );
      if (!mounted) return;
      setState(
        () => _message =
            'পাসওয়ার্ড বদলানো হয়েছে। এখন ফিরে গিয়ে নতুন পাসওয়ার্ড দিয়ে লগইন করুন।',
      );
    } catch (e) {
      setState(() => _message = describeApiError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final roleText = widget.role == 'husband' ? 'স্বামীর' : 'স্ত্রীর';
    return Scaffold(
      appBar: AppBar(title: const Text('পাসওয়ার্ড রিসেট করুন')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '$roleText পাসওয়ার্ড রিসেট করতে, আগে থেকে লগইন করা আছে এমন যেকোনো ডিভাইস (নিজের অন্য ফোন বা সঙ্গীর ফোন) থেকে এই কোডটা অনুমোদন করাতে হবে।',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              if (_resetToken == null)
                ElevatedButton(
                  onPressed: _loading ? null : _start,
                  child: const Text('রিসেট শুরু করুন / কোড নিন'),
                )
              else ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'এই কোডটা অন্য ডিভাইসে দিন:',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 8),
                      SelectableText(
                        _resetToken!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (!_approved)
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 10),
                      Text(
                        'অন্য ডিভাইস থেকে অনুমোদনের অপেক্ষায়...',
                        style: TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                    ],
                  )
                else ...[
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Iconsax.tick_circle_copy,
                        color: Colors.green,
                        size: 18,
                      ),
                      SizedBox(width: 6),
                      Text(
                        'অনুমোদন হয়েছে ✓',
                        style: TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  PasswordField(
                    controller: _newPassword,
                    labelText: 'নতুন পাসওয়ার্ড',
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: _loading ? null : _complete,
                    child: const Text('নতুন পাসওয়ার্ড সেট করুন'),
                  ),
                ],
              ],
              if (_message != null) ...[
                const SizedBox(height: 16),
                ErrorMessageBox(_message!, textAlign: TextAlign.center),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
