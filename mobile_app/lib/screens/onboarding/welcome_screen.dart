import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../widgets/error_message_box.dart';
import 'claim_role_screen.dart';
import 'pair_device_screen.dart';
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
      setState(() => _error = 'কোডটা পড়া যায়নি। পুরো টেক্সট ঠিকভাবে পেস্ট করেছেন কিনা আবার দেখুন।');
    }
  }

  void _submitFields() {
    if (_serverController.text.isEmpty || _codeController.text.isEmpty || _vmkController.text.isEmpty) {
      setState(() => _error = 'সবগুলো ঘর পূরণ করা লাগবে।');
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
              const Text('আপনাদের দুজনের একান্ত প্রাইভেট জায়গা। নিজেদের সার্ভারে হোস্ট করা — আর কেউ এটা দেখতে পারবে না।'),
              const SizedBox(height: 8),
              const Text(
                'শুরু করতে, আপনার সঙ্গী বা যিনি সার্ভার সেটআপ করেছেন তার কাছ থেকে "সেটআপ কোড" (QR কোড) নিন এবং নিচে স্ক্যান করুন।',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 32),
              if (!_manualMode) ...[
                ElevatedButton.icon(
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('সেটআপ কোড স্ক্যান করুন'),
                  onPressed: () async {
                    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ScanSetupScreen()));
                  },
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => setState(() => _manualMode = true),
                  child: const Text('কোড হাতে টাইপ করে দিন'),
                ),
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 12),
                const Text(
                  'ইতিমধ্যে আপনার স্বামী/স্ত্রী এই অ্যাকাউন্ট অন্য ফোনে ব্যবহার করছেন এবং আপনি এই ফোনটাও যোগ করতে চান?',
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  icon: const Icon(Icons.qr_code_2),
                  label: const Text('ইতিমধ্যে অ্যাকাউন্ট আছে? এই ডিভাইসটা যোগ করুন'),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PairDeviceScreen())),
                ),
              ] else ...[
                Text('অ্যাডমিন প্যানেল থেকে দেখানো পুরো টেক্সটটা এখানে পেস্ট করুন:', style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 8),
                TextField(controller: _payloadController, maxLines: 3, decoration: const InputDecoration(hintText: 'পেস্ট করা সেটআপ কোড টেক্সট')),
                const SizedBox(height: 12),
                ElevatedButton(onPressed: _submitPayload, child: const Text('পরবর্তী')),
                const SizedBox(height: 20),
                const Divider(),
                const SizedBox(height: 8),
                Text('...অথবা আলাদাভাবে প্রতিটা ঘর পূরণ করুন:', style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 8),
                TextField(controller: _serverController, decoration: const InputDecoration(hintText: 'সার্ভার (https://...)')),
                const SizedBox(height: 8),
                TextField(controller: _codeController, decoration: const InputDecoration(hintText: 'সেটআপ কোড')),
                const SizedBox(height: 8),
                TextField(controller: _vmkController, decoration: const InputDecoration(hintText: 'ভল্ট কী (অ্যাডমিন প্যানেল থেকে)')),
                const SizedBox(height: 12),
                OutlinedButton(onPressed: _submitFields, child: const Text('এই তথ্য দিয়ে এগিয়ে যান')),
                const SizedBox(height: 12),
                TextButton(onPressed: () => setState(() => _manualMode = false), child: const Text('স্ক্যান করায় ফিরে যান')),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                ErrorMessageBox(_error!),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
