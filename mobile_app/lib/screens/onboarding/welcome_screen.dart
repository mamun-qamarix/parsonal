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
  final _payloadController = TextEditingController();
  String? _error;

  @override
  void initState() {
    super.initState();
    _payloadController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _payloadController.dispose();
    super.dispose();
  }

  void _submitPayload() {
    try {
      final decoded = jsonDecode(utf8.decode(base64Decode(_payloadController.text.trim()))) as Map<String, dynamic>;
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ClaimRoleScreen(server: decoded['server'], token: decoded['code'], vmkB64: decoded['vmk']),
      ));
    } catch (_) {
      setState(() => _error = 'কোডটা পড়া যায়নি। পুরো টেক্সট ঠিকভাবে পেস্ট করেছেন কিনা আবার দেখুন।');
    }
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
              Text('পার্সোনাল', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text(
                'আপনাদের দুজনের একান্ত প্রাইভেট জায়গা। নিজেদের সার্ভারে হোস্ট করা — আর কেউ এটা দেখতে পারবে না।',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'শুরু করতে, আপনার সঙ্গী বা যিনি সার্ভার সেটআপ করেছেন তার কাছ থেকে "সেটআপ কোড" নিন — নিচে টাইপ/পেস্ট করুন, অথবা QR কোড স্ক্যান করুন।',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _payloadController,
                decoration: const InputDecoration(hintText: 'সেটআপ কোড লিখুন বা পেস্ট করুন', border: OutlineInputBorder()),
                onSubmitted: (_) {
                  if (_payloadController.text.trim().isNotEmpty) _submitPayload();
                },
              ),
              if (_payloadController.text.trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                ElevatedButton(onPressed: _submitPayload, child: const Text('পরবর্তী')),
              ],
              const SizedBox(height: 16),
              ElevatedButton.icon(
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('সেটআপ কোড স্ক্যান করুন'),
                onPressed: () async {
                  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ScanSetupScreen()));
                },
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
