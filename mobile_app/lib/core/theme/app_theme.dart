import 'package:flutter/material.dart';

/// "Halal green" — a clean, natural green accent, not neon.
class AppColors {
  static const Color halalGreen = Color(0xFF2F9E63);
  static const Color halalGreenDark = Color(0xFF7ED9A8);
  // "Intimate mode" -- either spouse can toggle the whole app's accent from
  // green to this blue from the chat screen, as a shared, at-a-glance
  // signal that "this is when we're talking about something private". See
  // DECISIONS.md. Screens that show the accent via Theme.of(context)
  // .colorScheme.primary pick this up automatically.
  static const Color intimateBlue = Color(0xFF3E7BE0);
  static const Color intimateBlueDark = Color(0xFF8FB4F5);
  static const Color husband = Color(0xFF3B7DD8);
  static const Color wife = Color(0xFFD86BA0);
  static const Color pending = Color(0xFFD8B34A);
  static const Color rejected = Color(0xFFD85C5C);
  static const Color approved = halalGreen;
}

class AppTheme {
  /// The app is dark-theme-only now, per explicit request -- no light
  /// theme anywhere, so there's no light/dark seed-color split to get
  /// wrong either. Always uses the one solid, vivid green (or blue, in
  /// intimate mode) rather than a separate pale "for dark mode" tint --
  /// that pale tint was designed for accent TEXT on a dark background,
  /// not as a button FILL color, and using it as one was the actual root
  /// cause of the "green looks washed out/white" reports (see DECISIONS.md
  /// #39). One color, used consistently as a solid fill everywhere, with
  /// contrast-correct foreground computed below rather than assumed.
  static ThemeData dark({bool intimate = false}) {
    final seed = intimate ? AppColors.intimateBlue : AppColors.halalGreen;
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.dark,
    ).copyWith(primary: seed, onPrimary: _onColorFor(seed));
    return _base(scheme);
  }

  /// Picks black or white for text/icons drawn on top of [color], based on
  /// that color's own actual brightness -- not an assumption tied to
  /// whether the overall theme happens to be light or dark. This is what
  /// let the "dark mode primary is pale, so hardcoded white text
  /// disappears" bug happen in the first place: the foreground was chosen
  /// for the *theme's* brightness instead of the *color's*. See
  /// DECISIONS.md #39.
  static Color _onColorFor(Color color) {
    return ThemeData.estimateBrightnessForColor(color) == Brightness.dark
        ? Colors.white
        : Colors.black87;
  }

  static ThemeData _base(ColorScheme scheme) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFF0F1512),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        foregroundColor: scheme.onSurface,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: const Color(0xFF17211C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF17211C),
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
          foregroundColor: scheme.onPrimary,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          disabledBackgroundColor: scheme.primary.withValues(alpha: 0.35),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: scheme.primary),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.primary,
          side: BorderSide(color: scheme.primary),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: const Color(0xFF17211C),
        indicatorColor: scheme.primary.withValues(alpha: 0.18),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
        elevation: 0,
        // No labels shown -- the default M3 height (80) leaves a lot of
        // dead vertical space under just an icon. See DECISIONS.md.
        height: 58,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : Colors.grey,
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        elevation: 0,
        backgroundColor: const Color(0xFF17211C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        elevation: 0,
        modalElevation: 0,
        backgroundColor: const Color(0xFF17211C),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(elevation: 0),
      popupMenuTheme: const PopupMenuThemeData(
        elevation: 0,
        color: Color(0xFF17211C),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
      ),
      // Kohinoor -- Apple's Bengali system typeface -- everywhere, since the
      // whole app's UI is in Bengali; Latin text (numbers, English words in
      // e.g. logs) falls back to it too since it also covers Latin glyphs.
      fontFamily: 'Kohinoor',
      textTheme: Typography.material2021(platform: TargetPlatform.android).white
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
