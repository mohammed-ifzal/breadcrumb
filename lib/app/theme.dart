import 'package:flutter/material.dart';

/// Breadcrumb's dark theme: colours, sizes, type scale and the app-wide
/// [ThemeData]. `main.dart` applies [BreadcrumbTheme.themeData], so every
/// screen inherits it. System font only: the demo runs offline, so no font
/// downloads.
class BreadcrumbTheme {
  BreadcrumbTheme._();

  // Colours.
  static const Color background = Color(0xFF0B0F14);
  static const Color surface = Color(0xFF141A22);
  static const Color surfaceRaised = Color(0xFF1A222C);
  static const Color border = Color(0xFF1E2734);
  static const Color accent = Color(0xFF2DE2C3);
  static const Color onAccent = Color(0xFF0B0F14);
  static const Color warning = Color(0xFFFFB020);
  static const Color danger = Color(0xFFFF6B5E);
  static const Color textPrimary = Color(0xFFF2F5F7);
  static const Color textSecondary = Color(0xFF9AA4AE);
  static const Color textFaint = Color(0xFF6B7785);

  /// Soft teal glow for the one active element on a screen.
  static List<BoxShadow> get accentGlow => [
        BoxShadow(
          color: accent.withValues(alpha: 0.25),
          blurRadius: 24,
        ),
      ];

  // Sizes.
  static const double radius = 20;
  static const double minTouch = 56;
  static const BorderRadius borderRadius = BorderRadius.all(Radius.circular(radius));

  // Type scale.
  static const TextStyle liveInstruction = TextStyle(
    fontSize: 42,
    fontWeight: FontWeight.w800,
    height: 1.1,
    letterSpacing: -0.8,
    color: textPrimary,
  );
  static const TextStyle display = TextStyle(
    fontSize: 40,
    fontWeight: FontWeight.w800,
    height: 1.1,
    letterSpacing: -1.0,
    color: textPrimary,
  );
  static const TextStyle heading = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w700,
    height: 1.2,
    letterSpacing: -0.4,
    color: textPrimary,
  );
  static const TextStyle title = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    height: 1.25,
    color: textPrimary,
  );
  static const TextStyle body = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w400,
    height: 1.4,
    color: textPrimary,
  );
  static const TextStyle bodySecondary = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w400,
    height: 1.4,
    color: textSecondary,
  );
  static const TextStyle label = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w700,
    height: 1.3,
    letterSpacing: 1.2,
    color: textSecondary,
  );
  static const TextStyle button = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.2,
  );

  // Button styles.
  static final ButtonStyle primaryButton = ElevatedButton.styleFrom(
    backgroundColor: accent,
    foregroundColor: onAccent,
    disabledBackgroundColor: surfaceRaised,
    disabledForegroundColor: textSecondary,
    minimumSize: const Size(minTouch, minTouch),
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
    shape: const RoundedRectangleBorder(borderRadius: borderRadius),
    textStyle: button,
    elevation: 0,
  );

  static final ButtonStyle secondaryButton = OutlinedButton.styleFrom(
    foregroundColor: textPrimary,
    backgroundColor: surface,
    side: const BorderSide(color: border),
    minimumSize: const Size(minTouch, minTouch),
    // Tighter than the primary button so rows of secondary actions fit 360 dp.
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
    shape: const RoundedRectangleBorder(borderRadius: borderRadius),
    textStyle: button.copyWith(fontSize: 17),
  );

  // Names used by the t3/real-sensors screens.
  static const Color textLight = textPrimary;
  static const Color textMuted = textSecondary;
  static const Color surfaceBorder = border;

  static ThemeData get themeData {
    const scheme = ColorScheme.dark(
      primary: accent,
      onPrimary: onAccent,
      secondary: warning,
      onSecondary: onAccent,
      surface: surface,
      onSurface: textPrimary,
      onSurfaceVariant: textSecondary,
      surfaceContainerHighest: surfaceRaised,
      outline: border,
      outlineVariant: border,
      error: danger,
      onError: onAccent,
    );

    final outline = OutlineInputBorder(
      borderRadius: borderRadius,
      borderSide: const BorderSide(color: border),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      textTheme: const TextTheme(
        displayLarge: liveInstruction,
        displayMedium: display,
        headlineLarge: heading,
        headlineMedium: heading,
        headlineSmall: title,
        titleLarge: title,
        titleMedium: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: textPrimary),
        titleSmall: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: textPrimary),
        bodyLarge: body,
        bodyMedium: body,
        bodySmall: TextStyle(fontSize: 15, height: 1.4, color: textSecondary),
        labelLarge: button,
        labelMedium: label,
        labelSmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.8, color: textSecondary),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        foregroundColor: textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        toolbarHeight: 64,
        titleTextStyle: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: textPrimary),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(style: primaryButton),
      outlinedButtonTheme: OutlinedButtonThemeData(style: secondaryButton),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
          minimumSize: const Size(minTouch, minTouch),
          textStyle: button,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: textPrimary,
          minimumSize: const Size(minTouch, minTouch),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        border: outline,
        enabledBorder: outline,
        focusedBorder: outline.copyWith(borderSide: const BorderSide(color: accent, width: 2)),
        hintStyle: const TextStyle(fontSize: 17, color: textFaint),
        labelStyle: const TextStyle(fontSize: 17, color: textSecondary),
        floatingLabelStyle: const TextStyle(color: accent),
      ),
      cardTheme: const CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: borderRadius,
          side: BorderSide(color: border),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        minVerticalPadding: 12,
        iconColor: textSecondary,
        textColor: textPrimary,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: border,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(radius)),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: surfaceRaised,
        contentTextStyle: body,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: borderRadius),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: accent,
        linearTrackColor: border,
        circularTrackColor: Colors.transparent,
      ),
      dividerTheme: const DividerThemeData(color: border, thickness: 1, space: 24),
      iconTheme: const IconThemeData(color: textPrimary, size: 24),
    );
  }
}
