import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/storage/secure_storage_service.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/session_provider.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

/// Lets an already-authenticated device add a second phone to the SAME
/// role (lost/replaced phone, or wanting the account on two of one
/// spouse's own devices) without ever re-claiming that role -- claiming
/// is a one-time, whole-account action. The QR carries role+VMK
/// peer-to-peer (never through the server, keeping the E2E design
/// intact); the new device still has to pass a normal password (+face)
/// login to get real tokens. See DECISIONS.md.
class AddDeviceScreen extends StatefulWidget {
  const AddDeviceScreen({super.key});

  @override
  State<AddDeviceScreen> createState() => _AddDeviceScreenState();
}

class _AddDeviceScreenState extends State<AddDeviceScreen> {
  String? _payload;
  bool _revealed = false;

  @override
  void initState() {
    super.initState();
    _build();
  }

  Future<void> _build() async {
    final session = context.read<SessionProvider>();
    final server = await SecureStorageService.instance.server;
    final vmk = session.vmk;
    if (server == null ||
        vmk == null ||
        session.role == null ||
        session.spouseId == null)
      return;
    final payload = {
      'type': 'device_pairing',
      'server': server,
      'role': session.role,
      'spouse_id': session.spouseId,
      'vmk': base64Encode(vmk),
    };
    final encoded = base64Encode(utf8.encode(jsonEncode(payload)));
    if (mounted) setState(() => _payload = encoded);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('নতুন ডিভাইস যোগ করুন')),
      body: _payload == null
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.rejected.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        children: [
                          Icon(Iconsax.warning_2, color: AppColors.rejected),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'এই QR কোডে আপনার ভল্টের পুরো চাবি (key) আছে। শুধু আপনার নিজের আরেকটা ফোনেই এটা স্ক্যান করান — অন্য কাউকে দেখাবেন না বা স্ক্রিনশট শেয়ার করবেন না।',
                              style: TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'নতুন ফোনে অ্যাপ ইনস্টল করে "ইতিমধ্যে অ্যাকাউন্ট আছে? এই ডিভাইসটা যোগ করুন" এ চেপে নিচের কোডটা স্ক্যান করুন। এরপর সেই ফোনেই পাসওয়ার্ড দিয়ে ঢুকতে হবে।',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: QrImageView(
                          data: _payload!,
                          size: 220,
                          backgroundColor: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Center(
                      child: TextButton(
                        onPressed: () => setState(() => _revealed = !_revealed),
                        child: Text(
                          _revealed
                              ? 'কোড লুকান'
                              : 'স্ক্যান করতে না পারলে — কোড টেক্সট হিসেবে কপি করুন',
                        ),
                      ),
                    ),
                    if (_revealed) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: SelectableText(
                          _payload!,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Center(
                        child: OutlinedButton.icon(
                          icon: const Icon(Iconsax.copy, size: 18),
                          label: const Text('কপি করুন'),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: _payload!));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('কপি হয়েছে')),
                            );
                          },
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    Text(
                      'কাজ শেষ হলে এই স্ক্রিন থেকে বেরিয়ে যান — কোডটা আর দরকার নেই।',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
