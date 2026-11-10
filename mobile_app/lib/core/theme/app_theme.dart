import 'package:flutter/material.dart';

/// "Halal green" — a clean, natural green accent, not neon.
class AppColors {
  static const Color halalGreen = Color(0xFF2F9E63);
  static const Color halalGreenDark = Color(0xFF7ED9A8);
  // "Intimate mode" -- either spouse can toggle the whole app's accent from
  // green to this blue from the chat screen, as a shared, at-a-glance
  // signal. Screens that use Theme.of(context).colorScheme.primary pick
  // this up automatically. See DECISIONS.md.
  static const Color intimateBlue = Color(0xFF3E7BE0);
  static const Color intimateBlueDark = Color(0xFF8FB4F5);
  static const Color husband = Color(0xFF3B7DD8);
  static const Color wife = Color(0xFFD86BA0);
  static const Color pending = Color(0xFFD8B34A);
  static const Color rejected = Color(0xFFD85C5C);
  static const Color approved = halalGreen;

  // Modern-messenger surfaces (DECISIONS.md #56): one deep background,
  // two stepped-up surfaces, hairline borders -- flat, no shadows.
  static const Color bg = Color(0xFF0B100E);
  static const Color surface = Color(0xFF121A16);
  static const Color surfaceHigh = Color(0xFF1B2620);
  static const Color line = Color(0x12FFFFFF); // ~7% white hairline
  static const Color muted = Color(0xFF8A9A91);
  static const Color faint = Color(0xFF5A6660);
  static const Color mint = Color(0xFF5DCAA5); // accent TEXT/ICONS on dark
  static const Color mintIntimate = Color(0xFF85B7EB);
  static const Color bubbleMine = Color(0xFF1F7A4D);
  static const Color bubbleMineIntimate = Color(0xFF2C5FB3);
  static const Color bubbleTheirs = Color(0xFF1B2620);
}

class AppTheme {
  /// Dark-theme-only (DECISIONS.md #39/#40). One solid seed color used as a
  /// fill everywhere, with a contrast-correct foreground computed from the
  /// color itself.
  static ThemeData dark({bool intimate = false}) {
    final seed = intimate ? AppColors.intimateBlue : AppColors.halalGreen;
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.dark,
    ).copyWith(primary: seed, onPrimary: _onColorFor(seed));
    return _base(scheme, intimate: intimate);
  }

  static Color _onColorFor(Color color) {
    return ThemeData.estimateBrightnessForColor(color) == Brightness.dark
        ? Colors.white
        : Colors.black87;
  }

  /// Per-tier type scale (bigger = bolder, smaller = lighter, compact meta
  /// text) -- not just the default theme with a font swapped in.
  static TextTheme _textTheme(Color on) {
    TextStyle t(double size, FontWeight w, {double? h, Color? c}) => TextStyle(
          fontFamily: 'Kohinoor',
          fontSize: size,
          fontWeight: w,
          height: h,
          color: c ?? on,
        );
    return TextTheme(
      displayLarge: t(40, FontWeight.w700),
      displayMedium: t(34, FontWeight.w700),
      displaySmall: t(28, FontWeight.w700),
      headlineLarge: t(26, FontWeight.w700),
      headlineMedium: t(22, FontWeight.w700),
      headlineSmall: t(20, FontWeight.w600),
      titleLarge: t(18, FontWeight.w600),
      titleMedium: t(15, FontWeight.w600),
      titleSmall: t(13.5, FontWeight.w500),
      bodyLarge: t(15, FontWeight.w400, h: 1.45),
      bodyMedium: t(14, FontWeight.w400, h: 1.45),
      bodySmall: t(12.5, FontWeight.w400, h: 1.4),
      labelLarge: t(14, FontWeight.w600),
      labelMedium: t(12, FontWeight.w500),
      labelSmall: t(10.5, FontWeight.w400, c: AppColors.muted),
    );
  }

  static ThemeData _base(ColorScheme scheme, {required bool intimate}) {
    final accentText = intimate ? AppColors.mintIntimate : AppColors.mint;
    final cs = scheme.copyWith(
      surface: AppColors.bg,
      surfaceContainerLowest: AppColors.bg,
      surfaceContainerLow: AppColors.surface,
      surfaceContainer: AppColors.surface,
      surfaceContainerHigh: AppColors.surfaceHigh,
      surfaceContainerHighest: AppColors.surfaceHigh,
      outline: AppColors.line,
      outlineVariant: AppColors.line,
      onSurfaceVariant: AppColors.muted,
      tertiary: accentText,
    );
    final text = _textTheme(cs.onSurface);
    const hairline = BorderSide(color: AppColors.line, width: 0.5);
    return ThemeData(
      useMaterial3: true,
      colorScheme: cs,
      scaffoldBackgroundColor: AppColors.bg,
      canvasColor: AppColors.bg,
      dividerColor: AppColors.line,
      dividerTheme: const DividerThemeData(color: AppColors.line, thickness: 0.5, space: 1),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        foregroundColor: cs.onSurface,
        titleTextStyle: text.titleLarge,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: hairline),
        margin: EdgeInsets.zero,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: accentText,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        subtitleTextStyle: text.bodySmall?.copyWith(color: AppColors.muted),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceHigh,
        hintStyle: const TextStyle(color: AppColors.faint),
        labelStyle: const TextStyle(color: AppColors.muted),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: hairline),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: cs.primary.withValues(alpha: 0.7), width: 1),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: cs.primary,
          foregroundColor: cs.onPrimary,
          disabledBackgroundColor: cs.primary.withValues(alpha: 0.35),
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontFamily: 'Kohinoor', fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: cs.primary,
          foregroundColor: cs.onPrimary,
          disabledBackgroundColor: cs.primary.withValues(alpha: 0.35),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: accentText),
      ),
      // Secondary actions are full pills; primary actions are 12px rounded
      // rects -- the shape contrast itself says which is which.
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: cs.onSurface,
          side: const BorderSide(color: Color(0x33FFFFFF), width: 0.5),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
          shape: const StadiumBorder(),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.transparent,
        selectedColor: cs.primary,
        side: const BorderSide(color: Color(0x24FFFFFF), width: 0.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        labelStyle: const TextStyle(fontFamily: 'Kohinoor', fontSize: 12.5),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: cs.primary.withValues(alpha: 0.16),
        indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
        elevation: 0,
        height: 60,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 23,
            color: states.contains(WidgetState.selected) ? accentText : AppColors.muted,
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        elevation: 0,
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: hairline),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        elevation: 0,
        modalElevation: 0,
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: Color(0x33FFFFFF),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      ),
      snackBarTheme: SnackBarThemeData(
        elevation: 0,
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.surfaceHigh,
        contentTextStyle: TextStyle(fontFamily: 'Kohinoor', color: cs.onSurface),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      popupMenuTheme: PopupMenuThemeData(
        elevation: 0,
        color: AppColors.surfaceHigh,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: hairline),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Colors.white : AppColors.muted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? cs.primary : AppColors.surfaceHigh,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      // Kohinoor -- Apple's Bengali system typeface -- everywhere, since the
      // whole app's UI is in Bengali.
      fontFamily: 'Kohinoor',
      textTheme: text,
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
