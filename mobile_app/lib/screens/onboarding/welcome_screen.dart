import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'claim_role_screen.dart';
import 'scan_setup_screen.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  bool _manualMode = false;
  final _serverController = TextEditingController();
  final _codeController = TextEditingController();
  final _vmkController = TextEditingController();
  final _payloadController = TextEditingController();
  String? _error;

  void _submitPayload() {
    try {
      final decoded = jsonDecode(utf8.decode(base64Decode(_payloadController.text.trim()))) as Map<String, dynamic>;
      _go(decoded['server'], decoded['code'], decoded['vmk']);
    } catch (_) {
      setState(() => _error = 'Could not read that code. Double check you pasted the full text.');
    }
  }

  void _submitFields() {
    if (_serverController.text.isEmpty || _codeController.text.isEmpty || _vmkController.text.isEmpty) {
      setState(() => _error = 'All fields are required.');
      return;
    }
    _go(_serverController.text.trim(), _codeController.text.trim(), _vmkController.text.trim());
  }

  void _go(String server, String code, String vmk) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ClaimRoleScreen(server: server, token: code, vmkB64: vmk),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 40),
              const Icon(Icons.favorite, size: 56, color: AppColors.halalGreen),
              const SizedBox(height: 16),
              Text('Couple\'s Vault', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('A private space for you and your spouse. Self-hosted on your own server — nothing else sees it.'),
              const SizedBox(height: 32),
              if (!_manualMode) ...[
                ElevatedButton.icon(
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Scan setup code'),
                  onPressed: () async {
                    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ScanSetupScreen()));
                  },
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => setState(() => _manualMode = true),
                  child: const Text('Enter setup code manually'),
                ),
              ] else ...[
                Text('Paste the full setup text from the admin panel:', style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 8),
                TextField(controller: _payloadController, maxLines: 3, decoration: const InputDecoration(hintText: 'Pasted setup code text')),
                const SizedBox(height: 12),
                ElevatedButton(onPressed: _submitPayload, child: const Text('Continue')),
                const SizedBox(height: 20),
                const Divider(),
                const SizedBox(height: 8),
                Text('...or fill in fields separately:', style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 8),
                TextField(controller: _serverController, decoration: const InputDecoration(hintText: 'Server (https://...)')),
                const SizedBox(height: 8),
                TextField(controller: _codeController, decoration: const InputDecoration(hintText: 'Setup code')),
                const SizedBox(height: 8),
                TextField(controller: _vmkController, decoration: const InputDecoration(hintText: 'Vault key (from admin panel)')),
                const SizedBox(height: 12),
                OutlinedButton(onPressed: _submitFields, child: const Text('Continue with fields')),
                const SizedBox(height: 12),
                TextButton(onPressed: () => setState(() => _manualMode = false), child: const Text('Back to scanning')),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: AppColors.rejected)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
