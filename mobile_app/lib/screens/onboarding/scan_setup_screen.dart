import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'claim_role_screen.dart';

class ScanSetupScreen extends StatefulWidget {
  const ScanSetupScreen({super.key});

  @override
  State<ScanSetupScreen> createState() => _ScanSetupScreenState();
}

class _ScanSetupScreenState extends State<ScanSetupScreen> {
  bool _handled = false;

  void _handlePayload(String raw) {
    if (_handled) return;
    try {
      final decoded =
          jsonDecode(utf8.decode(base64Decode(raw))) as Map<String, dynamic>;
      final server = decoded['server'] as String;
      final code = decoded['code'] as String;
      final vmk = decoded['vmk'] as String;
      _handled = true;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) =>
              ClaimRoleScreen(server: server, token: code, vmkB64: vmk),
        ),
      );
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'এই QR কোড বা টেক্সটটা সঠিক সেটআপ কোড বলে মনে হচ্ছে না।',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('সেটআপ কোড স্ক্যান করুন')),
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
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'অ্যাডমিন প্যানেলে দেখানো QR কোডটা ফ্রেমের মধ্যে ধরুন',
                style: TextStyle(color: Colors.white),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 24,
            child: Center(
              child: FilledButton.tonal(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('স্ক্যান না করে হাতে টাইপ করুন'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
