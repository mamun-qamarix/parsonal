import 'package:flutter/material.dart';

import '../../core/network/error_helper.dart';
import '../../core/theme/app_theme.dart';
import '../../services/auth_service.dart';
import '../../widgets/error_message_box.dart';

/// Run from an ALREADY-AUTHENTICATED device to approve a password reset
/// someone started on a locked device (their own other phone, or their
/// spouse's) -- replaces the old authenticator-code verification step.
/// See DECISIONS.md #27.
class ApprovePasswordResetScreen extends StatefulWidget {
  const ApprovePasswordResetScreen({super.key});

  @override
  State<ApprovePasswordResetScreen> createState() => _ApprovePasswordResetScreenState();
}

class _ApprovePasswordResetScreenState extends State<ApprovePasswordResetScreen> {
  final _tokenController = TextEditingController();
  bool _loading = false;
  String? _message;
  bool _success = false;

  Future<void> _approve() async {
    final token = _tokenController.text.trim();
    if (token.isEmpty) {
      setState(() => _message = 'কোডটা লিখুন।');
      return;
    }
    setState(() {
      _loading = true;
      _message = null;
    });
    try {
      await AuthService().passwordResetApprove(token);
      setState(() {
        _success = true;
        _message = 'অনুমোদন হয়েছে। এখন সেই ডিভাইসে গিয়ে নতুন পাসওয়ার্ড সেট করা যাবে।';
      });
    } catch (e) {
      setState(() => _message = describeApiError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('পাসওয়ার্ড রিসেট অনুমোদন করুন')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.verified_user_outlined, size: 48, color: AppColors.halalGreen),
              const SizedBox(height: 12),
              const Text(
                'অন্য ডিভাইসে পাসওয়ার্ড রিসেট শুরু করলে সেখানে যে কোডটা দেখানো হয়েছে, সেটা এখানে দিন। এটা নিশ্চিত করে যে অনুরোধটা সত্যিই আপনাদের কারো কাছ থেকে এসেছে।',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 20),
              TextField(controller: _tokenController, decoration: const InputDecoration(labelText: 'রিসেট কোড'), enabled: !_success),
              const SizedBox(height: 12),
              if (_message != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: ErrorMessageBox(_message!, textAlign: TextAlign.center)),
              if (!_success)
                ElevatedButton(
                  onPressed: _loading ? null : _approve,
                  child: _loading ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('অনুমোদন করুন'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
