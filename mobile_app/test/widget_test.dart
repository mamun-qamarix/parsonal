// Basic sanity tests that don't require platform channels (secure storage,
// camera, etc.), which aren't available in the plain widget-test harness.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:couple_vault/core/theme/app_theme.dart';

void main() {
  test('dark theme builds without error', () {
    // App is dark-theme-only now, per DECISIONS.md #39.
    final dark = AppTheme.dark();
    expect(dark.brightness, equals(Brightness.dark));
  });

  test('status colors are defined for every known status', () {
    expect(AppTheme.statusColor('pending'), equals(AppColors.pending));
    expect(AppTheme.statusColor('approved'), equals(AppColors.approved));
    expect(AppTheme.statusColor('rejected'), equals(AppColors.rejected));
  });
}
