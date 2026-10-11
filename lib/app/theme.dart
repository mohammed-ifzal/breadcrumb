import 'package:flutter/material.dart';

/// Breadcrumb's dark theme: colours, sizes, type scale and the app-wide
/// [ThemeData]. `main.dart` applies [BreadcrumbTheme.themeData], so every
/// screen inherits it. Inter is bundled (the demo runs offline).
class BreadcrumbTheme {
  BreadcrumbTheme._();

  static const String fontFamily = 'Inter';

  /// Tabular figures for numbers (e.g. step counts) so digits align and don't jitter.
  static const TextStyle tabularFigures = TextStyle(
    fontFamily: fontFamily,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  // Colours.
  static const Color background = Color(0xFF0E1116);
  static const Color surface = Color(0xFF161B22);
  static const Color surfaceRaised = Color(0xFF1C222B);
  static const Color border = Color(0xFF262C36);
  static const Color accent = Color(0xFF2DE2C3);
  static const Color onAccent = Color(0xFF0E1116);
  static const Color warning = Color(0xFFFFB020);
  static const Color danger = Color(0xFFFF6B5E);
  static const Color textPrimary = Color(0xFFF2F5F7);
  static const Color textSecondary = Color(0xFF8B949E);
  static const Color textFaint = Color(0xFF6B7785);

  // Sizes.
  static const double radius = 14;
  static const double minTouch = 52;

  /// 8-pt grid; screens pad 16.
  static const double screenPadding = 16;
  static const BorderRadius borderRadius = BorderRadius.all(Radius.circular(radius));

  // Type scale: Inter. Titles 22 semibold, body 16, captions 13.
  static const TextStyle liveInstruction = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w600,
    height: 1.15,
    letterSpacing: -0.4,
    color: textPrimary,
  );
  static const TextStyle display = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w600,
    height: 1.15,
    letterSpacing: -0.5,
    color: textPrimary,
  );
  static const TextStyle heading = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w600,
    height: 1.2,
    letterSpacing: -0.2,
    color: textPrimary,
  );
  static const TextStyle title = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w600,
    height: 1.25,
    color: textPrimary,
  );
  static const TextStyle body = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 1.4,
    color: textPrimary,
  );
  static const TextStyle bodySecondary = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 1.4,
    color: textSecondary,
  );
  static const TextStyle caption = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.35,
    color: textSecondary,
    fontFeatures: [FontFeature.tabularFigures()],
  );
  static const TextStyle label = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    height: 1.35,
    color: textSecondary,
    fontFeatures: [FontFeature.tabularFigures()],
  );
  static const TextStyle button = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
  );

  // Button styles.
  static final ButtonStyle primaryButton = ElevatedButton.styleFrom(
    backgroundColor: accent,
    foregroundColor: onAccent,
    disabledBackgroundColor: surfaceRaised,
    disabledForegroundColor: textSecondary,
    minimumSize: const Size(minTouch, minTouch),
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
    shape: const RoundedRectangleBorder(borderRadius: borderRadius),
    textStyle: button,
    elevation: 0,
  );

  static final ButtonStyle secondaryButton = OutlinedButton.styleFrom(
    foregroundColor: textPrimary,
    backgroundColor: Colors.transparent,
    side: const BorderSide(color: border),
    minimumSize: const Size(minTouch, minTouch),
    // Tighter than the primary button so rows of secondary actions fit 360 dp.
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    shape: const RoundedRectangleBorder(borderRadius: borderRadius),
    textStyle: button,
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
      fontFamily: 'Inter',
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
        titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: textPrimary),
        titleSmall: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: textPrimary),
        bodyLarge: body,
        bodyMedium: body,
        bodySmall: caption,
        labelLarge: button,
        labelMedium: label,
        labelSmall: caption,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        foregroundColor: textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        toolbarHeight: 64,
        titleTextStyle: TextStyle(fontFamily: fontFamily, fontSize: 22, fontWeight: FontWeight.w600, color: textPrimary),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(style: primaryButton),
      outlinedButtonTheme: OutlinedButtonThemeData(style: secondaryButton),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: textPrimary,
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
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: outline,
        enabledBorder: outline,
        focusedBorder: outline.copyWith(borderSide: const BorderSide(color: textSecondary, width: 1.5)),
        hintStyle: const TextStyle(fontSize: 16, color: textFaint),
        labelStyle: const TextStyle(fontSize: 16, color: textSecondary),
        floatingLabelStyle: const TextStyle(color: textSecondary),
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
