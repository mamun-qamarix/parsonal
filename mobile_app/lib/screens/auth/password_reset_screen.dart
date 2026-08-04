import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/network/error_helper.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/session_provider.dart';
import '../../services/auth_service.dart';
import '../../widgets/password_field.dart';

/// Password reset requires BOTH spouses to independently enter their
/// authenticator code before a new password can be set (see project.md §6,
/// DECISIONS.md §13). Each spouse does their own "Verify me" step, on
/// their own device, using the same shared reset token.
class PasswordResetScreen extends StatefulWidget {
  final String role; // whose password is being reset
  const PasswordResetScreen({super.key, required this.role});

  @override
  State<PasswordResetScreen> createState() => _PasswordResetScreenState();
}

class _PasswordResetScreenState extends State<PasswordResetScreen> {
  final _tokenController = TextEditingController();
  final _codeController = TextEditingController();
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
      setState(() => _message = 'এই কোডটা আপনার সঙ্গীকে দিন, যাতে তিনিও নিজের ফোন থেকে যাচাই করতে পারেন।');
    } catch (e) {
      setState(() => _message = describeApiError(e));
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _verifyMe() async {
    final myRole = context.read<SessionProvider>().role ?? widget.role;
    if (_tokenController.text.isEmpty) {
      setState(() => _message = 'আগে রিসেট কোডটা দিন।');
      return;
    }
    if (_codeController.text.trim().length != 6) {
      setState(() => _message = 'অথেন্টিকেটর কোডটা ৬ সংখ্যার হতে হবে।');
      return;
    }
    setState(() => _loading = true);
    try {
      final result = await AuthService().passwordResetVerify(resetToken: _tokenController.text.trim(), role: myRole, code: _codeController.text.trim());
      setState(() {
        _husbandVerified = result['husband_verified'] == true;
        _wifeVerified = result['wife_verified'] == true;
        _message = 'যাচাই সম্পন্ন হয়েছে।';
      });
    } catch (e) {
      setState(() => _message = describeApiError(e));
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _complete() async {
    if (_newPassword.text.length < 8) {
      setState(() => _message = 'নতুন পাসওয়ার্ড কমপক্ষে ৮ অক্ষরের হতে হবে।');
      return;
    }
    setState(() => _loading = true);
    try {
      await AuthService().passwordResetComplete(resetToken: _tokenController.text.trim(), newPassword: _newPassword.text);
      if (!mounted) return;
      setState(() => _message = 'পাসওয়ার্ড বদলানো হয়েছে। এখন ফিরে গিয়ে নতুন পাসওয়ার্ড দিয়ে লগইন করুন।');
    } catch (e) {
      setState(() => _message = describeApiError(e));
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bothVerified = _husbandVerified && _wifeVerified;
    final roleText = widget.role == 'husband' ? 'স্বামীর' : 'স্ত্রীর';
    return Scaffold(
      appBar: AppBar(title: const Text('পাসওয়ার্ড রিসেট করুন')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('$roleText পাসওয়ার্ড রিসেট করতে দুজনকেই নিজের অথেন্টিকেটর কোড দিয়ে যাচাই করতে হবে।', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 20),
              OutlinedButton(onPressed: _loading ? null : _start, child: const Text('রিসেট শুরু করুন / কোড নিন')),
              const SizedBox(height: 12),
              TextField(controller: _tokenController, decoration: const InputDecoration(labelText: 'রিসেট কোড', helperText: 'অন্য স্পাউজের ফোন থেকে হলে এখানে কোডটা পেস্ট করুন')),
              const SizedBox(height: 12),
              TextField(
                controller: _codeController,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: const InputDecoration(labelText: 'আপনার অথেন্টিকেটর অ্যাপের ৬ সংখ্যার কোড', counterText: ''),
              ),
              const SizedBox(height: 8),
              ElevatedButton(onPressed: _loading ? null : _verifyMe, child: const Text('আমাকে যাচাই করুন')),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.man, color: _husbandVerified ? AppColors.halalGreen : Colors.grey),
                  const SizedBox(width: 4),
                  const Text('স্বামী'),
                  const SizedBox(width: 16),
                  Icon(Icons.woman, color: _wifeVerified ? AppColors.halalGreen : Colors.grey),
                  const SizedBox(width: 4),
                  const Text('স্ত্রী'),
                ],
              ),
              const SizedBox(height: 20),
              if (bothVerified) ...[
                PasswordField(controller: _newPassword, labelText: 'নতুন পাসওয়ার্ড'),
                const SizedBox(height: 12),
                ElevatedButton(onPressed: _loading ? null : _complete, child: const Text('নতুন পাসওয়ার্ড সেট করুন')),
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
