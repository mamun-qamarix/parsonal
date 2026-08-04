import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/session_provider.dart';
import '../../services/auth_service.dart';

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
  final _deviceName = TextEditingController(text: 'My phone');
  bool _loading = false;
  String? _error;

  Future<void> _submit() async {
    if (_password.text.length < 8) {
      setState(() => _error = 'Password must be at least 8 characters.');
      return;
    }
    if (_password.text != _confirm.text) {
      setState(() => _error = 'Passwords do not match.');
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
          );
    } catch (e) {
      setState(() => _error = 'Could not set up this device. Check the code and your connection, then try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Set up this device')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Which of you is setting up this phone?', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'husband', label: Text('Husband'), icon: Icon(Icons.man)),
                  ButtonSegment(value: 'wife', label: Text('Wife'), icon: Icon(Icons.woman)),
                ],
                selected: {_role},
                onSelectionChanged: (s) => setState(() => _role = s.first),
              ),
              const SizedBox(height: 20),
              TextField(controller: _deviceName, decoration: const InputDecoration(labelText: 'Device name')),
              const SizedBox(height: 12),
              TextField(controller: _password, obscureText: true, decoration: const InputDecoration(labelText: 'Choose a password')),
              const SizedBox(height: 12),
              TextField(controller: _confirm, obscureText: true, decoration: const InputDecoration(labelText: 'Confirm password')),
              const SizedBox(height: 20),
              if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(_error!, style: const TextStyle(color: Colors.red))),
              ElevatedButton(
                onPressed: _loading ? null : _submit,
                child: _loading ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Continue'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
