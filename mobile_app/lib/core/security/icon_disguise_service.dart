import 'dart:io';

import 'package:flutter/services.dart';

/// Switches the home-screen launcher name/icon between the real identity
/// and an innocuous decoy (Android only — see MainActivity.kt). project.md §6.
class IconDisguiseService {
  static const _channel = MethodChannel('couple_vault/icon_disguise');

  static const options = {
    'real': 'পার্সোনাল (আসল নাম)',
    'notes': 'Notes',
    'calculator': 'Calculator',
  };

  static Future<String> getCurrentIdentity() async {
    if (!Platform.isAndroid) return 'real';
    try {
      return await _channel.invokeMethod<String>('getIdentity') ?? 'real';
    } catch (_) {
      return 'real';
    }
  }

  static Future<void> setIdentity(String key) async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod('setIdentity', {'identity': key});
  }
}
