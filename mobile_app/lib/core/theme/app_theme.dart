import 'package:flutter/material.dart';

/// "Halal green" — a clean, natural green accent, not neon.
class AppColors {
  static const Color halalGreen = Color(0xFF2F9E63);
  static const Color halalGreenDark = Color(0xFF7ED9A8);
  static const Color husband = Color(0xFF3B7DD8);
  static const Color wife = Color(0xFFD86BA0);
  static const Color pending = Color(0xFFD8B34A);
  static const Color rejected = Color(0xFFD85C5C);
  static const Color approved = halalGreen;
}

class AppTheme {
  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.halalGreen,
      brightness: Brightness.light,
    );
    return _base(scheme, Brightness.light);
  }

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.halalGreenDark,
      brightness: Brightness.dark,
    );
    return _base(scheme, Brightness.dark);
  }

  static ThemeData _base(ColorScheme scheme, Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: isDark ? const Color(0xFF0F1512) : const Color(0xFFF6FAF7),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        foregroundColor: scheme.onSurface,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: isDark ? const Color(0xFF17211C) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? const Color(0xFF17211C) : const Color(0xFFEFF5F1),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.halalGreen,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: isDark ? const Color(0xFF17211C) : Colors.white,
        indicatorColor: AppColors.halalGreen.withValues(alpha: 0.18),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        elevation: 0,
      ),
      dialogTheme: DialogThemeData(
        elevation: 0,
        backgroundColor: isDark ? const Color(0xFF17211C) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        elevation: 0,
        modalElevation: 0,
        backgroundColor: isDark ? const Color(0xFF17211C) : Colors.white,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      ),
      snackBarTheme: const SnackBarThemeData(elevation: 0),
      popupMenuTheme: PopupMenuThemeData(
        elevation: 0,
        color: isDark ? const Color(0xFF17211C) : Colors.white,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(elevation: 0, focusElevation: 0, hoverElevation: 0, highlightElevation: 0),
      textTheme: Typography.material2021(platform: TargetPlatform.android).black.apply(
            bodyColor: scheme.onSurface,
            displayColor: scheme.onSurface,
          ),
    );
  }

  static Color statusColor(String status) {
    switch (status) {
      case 'pending':
        return AppColors.pending;
      case 'approved':
        return AppColors.approved;
      case 'rejected':
        return AppColors.rejected;
      default:
        return AppColors.halalGreen;
    }
  }
}
