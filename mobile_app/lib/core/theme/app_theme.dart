import 'package:flutter/material.dart';

/// "Halal green" — a clean, natural green accent, not neon.
class AppColors {
  static const Color halalGreen = Color(0xFF2F9E63);
  static const Color halalGreenDark = Color(0xFF7ED9A8);
  // "Intimate mode" -- either spouse can toggle the whole app's accent from
  // green to this blue from the chat screen, as a shared, at-a-glance
  // signal that "this is when we're talking about something private". See
  // DECISIONS.md. Screens that show the accent via Theme.of(context)
  // .colorScheme.primary pick this up automatically; a handful of purely
  // pre-login/disabled-feature screens intentionally keep the static green
  // above since intimate mode can never be on before a real login exists.
  static const Color intimateBlue = Color(0xFF3E7BE0);
  static const Color intimateBlueDark = Color(0xFF8FB4F5);
  static const Color husband = Color(0xFF3B7DD8);
  static const Color wife = Color(0xFFD86BA0);
  static const Color pending = Color(0xFFD8B34A);
  static const Color rejected = Color(0xFFD85C5C);
  static const Color approved = halalGreen;
}

class AppTheme {
  static ThemeData light({bool intimate = false}) {
    final seed = intimate ? AppColors.intimateBlue : AppColors.halalGreen;
    // .copyWith(primary: seed) pins colorScheme.primary to the EXACT seed
    // hex -- ColorScheme.fromSeed's Material-3 tonal palette otherwise
    // computes its own (slightly different, more muted) tone-40 shade for
    // `primary`, which was a visible, unintended color shift the moment
    // widgets across the app switched from the old hardcoded
    // AppColors.halalGreen constant to Theme.of(context).colorScheme
    // .primary for intimate-mode support. See DECISIONS.md.
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.light,
    ).copyWith(primary: seed);
    return _base(scheme, Brightness.light);
  }

  static ThemeData dark({bool intimate = false}) {
    final seed = intimate ? AppColors.intimateBlueDark : AppColors.halalGreenDark;
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.dark,
    ).copyWith(primary: seed);
    return _base(scheme, Brightness.dark);
  }

  static ThemeData _base(ColorScheme scheme, Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: isDark
          ? const Color(0xFF0F1512)
          : const Color(0xFFF6FAF7),
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
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        ),
      ),
      // Explicit, rather than relying on Material 3's own default color
      // resolution for these -- dialog "সংরক্ষণ"/"মুছে ফেলুন"/etc. buttons
      // were showing up grey instead of the accent color. See DECISIONS.md.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: scheme.primary.withValues(alpha: 0.35),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: scheme.primary),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: isDark ? const Color(0xFF17211C) : Colors.white,
        indicatorColor: scheme.primary.withValues(alpha: 0.18),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
        elevation: 0,
        // No labels shown -- the default M3 height (80) leaves a lot of
        // dead vertical space under just an icon. See DECISIONS.md.
        height: 58,
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
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(elevation: 0),
      popupMenuTheme: PopupMenuThemeData(
        elevation: 0,
        color: isDark ? const Color(0xFF17211C) : Colors.white,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
      ),
      // Kohinoor -- Apple's Bengali system typeface -- everywhere, since the
      // whole app's UI is in Bengali; Latin text (numbers, English words in
      // e.g. logs) falls back to it too since it also covers Latin glyphs.
      fontFamily: 'Kohinoor',
      textTheme: Typography.material2021(platform: TargetPlatform.android).black
          .apply(fontFamily: 'Kohinoor', bodyColor: scheme.onSurface, displayColor: scheme.onSurface),
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
