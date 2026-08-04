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
      final decoded = jsonDecode(utf8.decode(base64Decode(raw))) as Map<String, dynamic>;
      final server = decoded['server'] as String;
      final code = decoded['code'] as String;
      final vmk = decoded['vmk'] as String;
      _handled = true;
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => ClaimRoleScreen(server: server, token: code, vmkB64: vmk),
      ));
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('That QR code / text does not look like a valid setup code.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan setup code')),
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
            left: 0,
            right: 0,
            bottom: 24,
            child: Center(
              child: FilledButton.tonal(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Enter manually instead'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
