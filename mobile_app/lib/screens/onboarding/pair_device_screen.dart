import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../../providers/session_provider.dart';
import '../../widgets/error_message_box.dart';

/// Scans (or accepts pasted text for) the pairing code shown by
/// AddDeviceScreen on an already-authenticated device, then hands
/// role+VMK to SessionProvider.beginPairing so the normal
/// password->TOTP->(face) login screens can finish the job.
class PairDeviceScreen extends StatefulWidget {
  const PairDeviceScreen({super.key});

  @override
  State<PairDeviceScreen> createState() => _PairDeviceScreenState();
}

class _PairDeviceScreenState extends State<PairDeviceScreen> {
  bool _handled = false;
  bool _manualMode = false;
  final _payloadController = TextEditingController();
  String? _error;

  Future<void> _handlePayload(String raw) async {
    if (_handled) return;
    try {
      final decoded = jsonDecode(utf8.decode(base64Decode(raw.trim()))) as Map<String, dynamic>;
      if (decoded['type'] != 'device_pairing') {
        throw const FormatException('not a pairing code');
      }
      final server = decoded['server'] as String;
      final role = decoded['role'] as String;
      final spouseId = decoded['spouse_id'] as String;
      final vmk = decoded['vmk'] as String;
      _handled = true;
      await context.read<SessionProvider>().beginPairing(server: server, role: role, spouseId: spouseId, vmkB64: vmk);
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (_) {
      _handled = false;
      setState(() => _error = 'এই কোডটা "নতুন ডিভাইস যোগ করুন" থেকে পাওয়া কোড বলে মনে হচ্ছে না। ঠিক কোডটা কিনা আবার দেখুন।');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_manualMode) {
      return Scaffold(
        appBar: AppBar(title: const Text('ডিভাইস যোগ করার কোড')),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('অন্য ফোনের সেটিংস থেকে "নতুন ডিভাইস যোগ করুন" স্ক্রিনে দেখানো পুরো টেক্সটটা এখানে পেস্ট করুন:', textAlign: TextAlign.center),
                const SizedBox(height: 12),
                TextField(controller: _payloadController, maxLines: 4, decoration: const InputDecoration(hintText: 'পেস্ট করা কোড টেক্সট')),
                const SizedBox(height: 12),
                ElevatedButton(onPressed: () => _handlePayload(_payloadController.text), child: const Text('পরবর্তী')),
                const SizedBox(height: 12),
                TextButton(onPressed: () => setState(() => _manualMode = false), child: const Text('স্ক্যান করায় ফিরে যান')),
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

    return Scaffold(
      appBar: AppBar(title: const Text('ডিভাইস যোগ করার কোড স্ক্যান করুন')),
      body: Stack(
        children: [
          MobileScanner(
            onDetect: (capture) {
              for (final barcode in capture.barcodes) {
                final value = barcode.rawValue;
                if (value != null) _handlePayload(value);
              }
            },
          ),
          Positioned(
            top: 24,
            left: 24,
            right: 24,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
              child: const Text('আপনার অন্য ফোনের "নতুন ডিভাইস যোগ করুন" স্ক্রিনে দেখানো QR কোডটা ফ্রেমের মধ্যে ধরুন', style: TextStyle(color: Colors.white), textAlign: TextAlign.center),
            ),
          ),
          if (_error != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 90,
              child: ErrorMessageBox(_error!),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 24,
            child: Center(
              child: FilledButton.tonal(
                onPressed: () => setState(() => _manualMode = true),
                child: const Text('স্ক্যান না করে হাতে টাইপ করুন'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
