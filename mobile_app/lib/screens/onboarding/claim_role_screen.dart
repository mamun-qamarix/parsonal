import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/network/error_helper.dart';
import '../../providers/session_provider.dart';
import '../../services/auth_service.dart';
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
            accessToken: result['access_token'],
            refreshToken: result['refresh_token'],
            vmkB64: result['vmk_b64'],
            totpSecret: result['totp_secret'],
            totpProvisioningUri: result['totp_provisioning_uri'],
          );
    } catch (e) {
      setState(() => _error = describeApiError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'husband', label: Text('স্বামী'), icon: Icon(Icons.man)),
                  ButtonSegment(value: 'wife', label: Text('স্ত্রী'), icon: Icon(Icons.woman)),
                ],
                selected: {_role},
                onSelectionChanged: (s) => setState(() => _role = s.first),
              ),
              const SizedBox(height: 20),
              TextField(controller: _deviceName, decoration: const InputDecoration(labelText: 'ডিভাইসের নাম', helperText: 'শুধু চেনার জন্য, যেমন "আমার ফোন"')),
              const SizedBox(height: 12),
              PasswordField(controller: _password, labelText: 'একটা পাসওয়ার্ড দিন', hintText: 'কমপক্ষে ৮ অক্ষর'),
              const SizedBox(height: 12),
              PasswordField(controller: _confirm, labelText: 'পাসওয়ার্ড আবার লিখুন'),
              const SizedBox(height: 8),
              const Text(
                'এই পাসওয়ার্ড আর আপনার মুখ — দুটোই লাগবে প্রতিবার অ্যাপ খুলতে। মনে রাখার মতো একটা পাসওয়ার্ড দিন।',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
              const SizedBox(height: 20),
              if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(_error!, style: const TextStyle(color: Colors.red))),
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
