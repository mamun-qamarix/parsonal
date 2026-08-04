import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_globals.dart';
import '../../core/network/error_helper.dart';
import '../../providers/session_provider.dart';
import '../../services/auth_service.dart';
import '../../widgets/error_message_box.dart';
import '../../widgets/password_field.dart';

class ClaimRoleScreen extends StatefulWidget {
  final String server;
  final String token;
  final String vmkB64;
  const ClaimRoleScreen({super.key, required this.server, required this.token, required this.vmkB64});

  @override
  State<ClaimRoleScreen> createState() => _ClaimRoleScreenState();
}

class _ClaimRoleScreenState extends State<ClaimRoleScreen> {
  String _role = 'husband';
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _deviceName = TextEditingController(text: 'আমার ফোন');
  bool _loading = false;
  String? _error;

  Future<void> _submit() async {
    if (_password.text.length < 8) {
      setState(() => _error = 'পাসওয়ার্ড কমপক্ষে ৮ অক্ষরের হতে হবে।');
      return;
    }
    if (_password.text != _confirm.text) {
      setState(() => _error = 'দুটো পাসওয়ার্ড মিলছে না।');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await AuthService().claimRole(
        server: widget.server,
        token: widget.token,
        role: _role,
        password: _password.text,
        deviceName: _deviceName.text,
      );
      if (!mounted) return;
      await context.read<SessionProvider>().completeClaim(
            server: widget.server,
            role: result['role'],
            spouseId: result['spouse_id'],
            deviceId: result['device_id'],
            accessToken: result['access_token'],
            refreshToken: result['refresh_token'],
            vmkB64: result['vmk_b64'],
            totpSecret: result['totp_secret'],
            totpProvisioningUri: result['totp_provisioning_uri'],
          );
    } catch (e) {
      if (_isAlreadyRegistered(e)) {
        // This role was already claimed (e.g. reinstalling this same phone,
        // or adding another device with the same admin-issued code) --
        // instead of a dead-end error, fall back to a normal login with
        // the role+VMK we already have from this code. See DECISIONS.md.
        await context.read<SessionProvider>().beginPairing(server: widget.server, role: _role, spouseId: '', vmkB64: widget.vmkB64);
        if (!mounted) return;
        final roleLabel = _role == 'husband' ? 'স্বামী' : 'স্ত্রী';
        scaffoldMessengerKey.currentState?.showSnackBar(
          SnackBar(content: Text('"$roleLabel" রোলটা আগে থেকেই সেটআপ করা আছে — এখন সেই পাসওয়ার্ড দিয়ে লগইন করুন।'), duration: const Duration(seconds: 4)),
        );
        Navigator.of(context).popUntil((route) => route.isFirst);
        return;
      }
      setState(() => _error = describeApiError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _isAlreadyRegistered(Object e) {
    if (e is! DioException) return false;
    final data = e.response?.data;
    final detail = data is Map ? data['detail']?.toString() : null;
    return e.response?.statusCode == 409 && (detail?.contains('already registered') ?? false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('এই ফোনটা সেটআপ করুন')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'আপনাদের মধ্যে কে এই ফোনটা সেটআপ করছেন? এটাই ঠিক করবে অ্যাপে আপনি কার তথ্য হিসেবে চিহ্নিত হবেন।',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Center(
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'husband', label: Text('স্বামী'), icon: Icon(Icons.man)),
                    ButtonSegment(value: 'wife', label: Text('স্ত্রী'), icon: Icon(Icons.woman)),
                  ],
                  selected: {_role},
                  onSelectionChanged: (s) => setState(() => _role = s.first),
                ),
              ),
              const SizedBox(height: 20),
              TextField(controller: _deviceName, decoration: const InputDecoration(labelText: 'ডিভাইসের নাম', helperText: 'শুধু চেনার জন্য, যেমন "আমার ফোন"')),
              const SizedBox(height: 12),
              PasswordField(controller: _password, labelText: 'একটা পাসওয়ার্ড দিন', hintText: 'কমপক্ষে ৮ অক্ষর'),
              const SizedBox(height: 12),
              PasswordField(controller: _confirm, labelText: 'পাসওয়ার্ড আবার লিখুন', onSubmitted: (_) => _submit()),
              const SizedBox(height: 8),
              const Text(
                'এই পাসওয়ার্ড আর একটা অথেন্টিকেটর কোড — দুটোই লাগবে প্রতিবার অ্যাপ খুলতে (পরের ধাপে সেটআপ করবেন)। মনে রাখার মতো একটা পাসওয়ার্ড দিন।',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
              const SizedBox(height: 20),
              if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: ErrorMessageBox(_error!)),
              ElevatedButton(
                onPressed: _loading ? null : _submit,
                child: _loading ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('পরবর্তী ধাপ'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
