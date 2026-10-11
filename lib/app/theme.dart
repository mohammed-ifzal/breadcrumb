import 'package:flutter/material.dart';

/// Design tokens as a [ThemeExtension], so widgets can read them with
/// `BreadcrumbTokens.of(context)`. The same values are also exposed as
/// constants on [BreadcrumbTheme] for `const` widgets and painters.
@immutable
class BreadcrumbTokens extends ThemeExtension<BreadcrumbTokens> {
  const BreadcrumbTokens({
    required this.bg,
    required this.surface1,
    required this.surface2,
    required this.surface3,
    required this.border,
    required this.borderActive,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.accent,
    required this.accentWalked,
    required this.recording,
    required this.offRoute,
    required this.success,
    required this.error,
    required this.simulated,
  });

  static const dark = BreadcrumbTokens(
    bg: BreadcrumbTheme.bg,
    surface1: BreadcrumbTheme.surface1,
    surface2: BreadcrumbTheme.surface2,
    surface3: BreadcrumbTheme.surface3,
    border: BreadcrumbTheme.border,
    borderActive: BreadcrumbTheme.borderActive,
    textPrimary: BreadcrumbTheme.textPrimary,
    textSecondary: BreadcrumbTheme.textSecondary,
    textMuted: BreadcrumbTheme.textMuted,
    accent: BreadcrumbTheme.accent,
    accentWalked: BreadcrumbTheme.accentWalked,
    recording: BreadcrumbTheme.recording,
    offRoute: BreadcrumbTheme.offRoute,
    success: BreadcrumbTheme.success,
    error: BreadcrumbTheme.error,
    simulated: BreadcrumbTheme.simulated,
  );

  final Color bg;
  final Color surface1;
  final Color surface2;
  final Color surface3;
  final Color border;
  final Color borderActive;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color accent;
  final Color accentWalked;
  final Color recording;
  final Color offRoute;
  final Color success;
  final Color error;
  final Color simulated;

  static BreadcrumbTokens of(BuildContext context) =>
      Theme.of(context).extension<BreadcrumbTokens>() ?? dark;

  @override
  BreadcrumbTokens copyWith({
    Color? bg,
    Color? surface1,
    Color? surface2,
    Color? surface3,
    Color? border,
    Color? borderActive,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? accent,
    Color? accentWalked,
    Color? recording,
    Color? offRoute,
    Color? success,
    Color? error,
    Color? simulated,
  }) {
    return BreadcrumbTokens(
      bg: bg ?? this.bg,
      surface1: surface1 ?? this.surface1,
      surface2: surface2 ?? this.surface2,
      surface3: surface3 ?? this.surface3,
      border: border ?? this.border,
      borderActive: borderActive ?? this.borderActive,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      accent: accent ?? this.accent,
      accentWalked: accentWalked ?? this.accentWalked,
      recording: recording ?? this.recording,
      offRoute: offRoute ?? this.offRoute,
      success: success ?? this.success,
      error: error ?? this.error,
      simulated: simulated ?? this.simulated,
    );
  }

  @override
  BreadcrumbTokens lerp(ThemeExtension<BreadcrumbTokens>? other, double t) {
    if (other is! BreadcrumbTokens) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return BreadcrumbTokens(
      bg: l(bg, other.bg),
      surface1: l(surface1, other.surface1),
      surface2: l(surface2, other.surface2),
      surface3: l(surface3, other.surface3),
      border: l(border, other.border),
      borderActive: l(borderActive, other.borderActive),
      textPrimary: l(textPrimary, other.textPrimary),
      textSecondary: l(textSecondary, other.textSecondary),
      textMuted: l(textMuted, other.textMuted),
      accent: l(accent, other.accent),
      accentWalked: l(accentWalked, other.accentWalked),
      recording: l(recording, other.recording),
      offRoute: l(offRoute, other.offRoute),
      success: l(success, other.success),
      error: l(error, other.error),
      simulated: l(simulated, other.simulated),
    );
  }
}

/// Breadcrumb's dark theme: colours, sizes, type scale and the app-wide
/// [ThemeData]. `main.dart` applies [BreadcrumbTheme.themeData], so every
/// screen inherits it. Inter is bundled (the demo runs offline).
///
/// Flat: 1 px borders, no shadows, no gradients, no blur.
class BreadcrumbTheme {
  BreadcrumbTheme._();

  static const String fontFamily = 'Inter';

  /// Tabular figures for numbers (e.g. step counts) so digits align and don't jitter.
  static const List<FontFeature> tabular = [FontFeature.tabularFigures()];
  static const TextStyle tabularFigures = TextStyle(
    fontFamily: fontFamily,
    fontFeatures: tabular,
  );

  // Backgrounds and borders.
  static const Color bg = Color(0xFF07090E);
  static const Color surface1 = Color(0xFF11141A);
  static const Color surface2 = Color(0xFF181D26);
  static const Color surface3 = Color(0xFF222834);
  static const Color border = Color(0xFF1F2633);
  static const Color borderActive = Color(0xFF323D4E);

  // Text. [textMuted] is below 4.5:1 on [bg]: decoration and disabled only.
  static const Color textPrimary = Color(0xFFF5F7FA);
  static const Color textSecondary = Color(0xFF94A1B2);
  static const Color textMuted = Color(0xFF5B6577);

  /// Route, primary button, arrow.
  static const Color accent = Color(0xFF2DE2C3);

  /// The walked part of the route: accent at 35%.
  static const Color accentWalked = Color(0x592DE2C3);
  static const Color onAccent = bg;

  // States.
  static const Color recording = Color(0xFFFF3366);

  /// Off route, walk back, turn to face the path. Its own colour, not amber.
  static const Color offRoute = Color(0xFFFF7A45);
  static const Color success = Color(0xFF10B981);
  static const Color error = Color(0xFFFF4D4F);

  /// Amber is ONLY for the SIMULATED label.
  static const Color simulated = Color(0xFFFFB020);

  // Older names kept so every screen compiles unchanged.
  static const Color background = bg;
  static const Color surface = surface1;
  static const Color surfaceRaised = surface2;
  static const Color warning = simulated;
  static const Color danger = error;
  static const Color textFaint = textMuted;
  static const Color textLight = textPrimary;
  static const Color surfaceBorder = border;

  // Radii.
  static const double radiusSm = 6;
  static const double radiusMd = 12;
  static const double radiusLg = 18;
  static const double radius = radiusMd;
  static const BorderRadius borderRadius = BorderRadius.all(Radius.circular(radiusMd));
  static const BorderRadius borderRadiusSm = BorderRadius.all(Radius.circular(radiusSm));
  static const BorderRadius borderRadiusLg = BorderRadius.all(Radius.circular(radiusLg));

  // Spacing.
  static const double space1 = 4;
  static const double space2 = 8;
  static const double space3 = 16;
  static const double space4 = 24;
  static const double space5 = 32;

  /// Buttons are 52 dp tall; every touch target is at least 48 dp.
  static const double minTouch = 52;
  static const double screenPadding = space3;

  // Motion.
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration medium = Duration(milliseconds: 250);
  static const Curve ease = Cubic(0.16, 1, 0.3, 1);
  static const double pressScale = 0.98;

  // Type scale: Inter.
  static const TextStyle display = TextStyle(
    fontFamily: fontFamily,
    fontSize: 32,
    fontWeight: FontWeight.w700,
    height: 1.15,
    letterSpacing: -0.5,
    color: textPrimary,
  );
  static const TextStyle headline = TextStyle(
    fontFamily: fontFamily,
    fontSize: 24,
    fontWeight: FontWeight.w600,
    height: 1.2,
    letterSpacing: -0.2,
    color: textPrimary,
  );
  static const TextStyle title = TextStyle(
    fontFamily: fontFamily,
    fontSize: 18,
    fontWeight: FontWeight.w600,
    height: 1.3,
    color: textPrimary,
  );
  static const TextStyle body = TextStyle(
    fontFamily: fontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 1.4,
    color: textPrimary,
  );
  static const TextStyle secondary = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.4,
    color: textSecondary,
  );

  /// 11/700 uppercase, letter-spacing 0.8. Pass the text already uppercased.
  static const TextStyle eyebrow = TextStyle(
    fontFamily: fontFamily,
    fontSize: 11,
    fontWeight: FontWeight.w700,
    height: 1.3,
    letterSpacing: 0.8,
    color: textSecondary,
    fontFeatures: tabular,
  );

  // Older names kept so every screen compiles unchanged.
  static const TextStyle liveInstruction = display;
  static const TextStyle heading = headline;
  static const TextStyle bodySecondary = TextStyle(
    fontFamily: fontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 1.4,
    color: textSecondary,
  );
  static const TextStyle caption = TextStyle(
    fontFamily: fontFamily,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.35,
    color: textSecondary,
    fontFeatures: tabular,
  );
  static const TextStyle label = TextStyle(
    fontFamily: fontFamily,
    fontSize: 13,
    fontWeight: FontWeight.w600,
    height: 1.35,
    letterSpacing: 0.2,
    color: textSecondary,
    fontFeatures: tabular,
  );
  static const TextStyle button = TextStyle(
    fontFamily: fontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w600,
  );

  // Button styles: 52 dp, radius 12, flat.
  static final ButtonStyle primaryButton = ElevatedButton.styleFrom(
    backgroundColor: accent,
    foregroundColor: onAccent,
    disabledBackgroundColor: surface2,
    disabledForegroundColor: textSecondary,
    minimumSize: const Size(minTouch, minTouch),
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
    shape: const RoundedRectangleBorder(borderRadius: borderRadius),
    textStyle: button,
    elevation: 0,
    shadowColor: Colors.transparent,
  );

  /// Outlined on surface2, same 52 dp as the primary button.
  static final ButtonStyle secondaryButton = OutlinedButton.styleFrom(
    foregroundColor: textPrimary,
    backgroundColor: surface2,
    disabledForegroundColor: textMuted,
    side: const BorderSide(color: borderActive),
    minimumSize: const Size(minTouch, minTouch),
    // Tighter than the primary button so rows of secondary actions fit 360 dp.
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    shape: const RoundedRectangleBorder(borderRadius: borderRadius),
    textStyle: button,
  );

  /// [secondaryButton] for an [ElevatedButton].
  static final ButtonStyle secondaryElevatedButton = ElevatedButton.styleFrom(
    backgroundColor: surface2,
    foregroundColor: textPrimary,
    disabledBackgroundColor: surface2,
    disabledForegroundColor: textMuted,
    shadowColor: Colors.transparent,
    side: const BorderSide(color: borderActive),
    minimumSize: const Size(minTouch, minTouch),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    shape: const RoundedRectangleBorder(borderRadius: borderRadius),
    textStyle: button,
    elevation: 0,
  );

  static ThemeData get themeData {
    const scheme = ColorScheme.dark(
      primary: accent,
      onPrimary: onAccent,
      secondary: accent,
      onSecondary: onAccent,
      surface: surface1,
      onSurface: textPrimary,
      onSurfaceVariant: textSecondary,
      surfaceContainerLowest: bg,
      surfaceContainerLow: surface1,
      surfaceContainer: surface1,
      surfaceContainerHigh: surface2,
      surfaceContainerHighest: surface3,
      outline: borderActive,
      outlineVariant: border,
      error: error,
      onError: onAccent,
      shadow: Colors.transparent,
    );

    final outline = OutlineInputBorder(
      borderRadius: borderRadius,
      borderSide: const BorderSide(color: border),
    );

    return ThemeData(
      fontFamily: fontFamily,
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      extensions: const [BreadcrumbTokens.dark],
      scaffoldBackgroundColor: bg,
      canvasColor: bg,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      splashFactory: InkRipple.splashFactory,
      textTheme: const TextTheme(
        displayLarge: display,
        displayMedium: display,
        headlineLarge: headline,
        headlineMedium: headline,
        headlineSmall: title,
        titleLarge: title,
        titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: textPrimary),
        titleSmall: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: textPrimary),
        bodyLarge: body,
        bodyMedium: body,
        bodySmall: secondary,
        labelLarge: button,
        labelMedium: label,
        labelSmall: caption,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: bg,
        foregroundColor: textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        toolbarHeight: 60,
        titleTextStyle: title,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(style: primaryButton),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: onAccent,
          disabledBackgroundColor: surface2,
          disabledForegroundColor: textSecondary,
          minimumSize: const Size(minTouch, minTouch),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: const RoundedRectangleBorder(borderRadius: borderRadius),
          textStyle: button,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(style: secondaryButton),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: textPrimary,
          minimumSize: const Size(minTouch, minTouch),
          shape: const RoundedRectangleBorder(borderRadius: borderRadius),
          textStyle: button,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: textPrimary,
          minimumSize: const Size(48, 48),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface2,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: outline,
        enabledBorder: outline,
        focusedBorder: outline.copyWith(borderSide: const BorderSide(color: accent, width: 1.5)),
        hintStyle: const TextStyle(fontSize: 16, color: textSecondary),
        labelStyle: const TextStyle(fontSize: 16, color: textSecondary),
        floatingLabelStyle: const TextStyle(color: textSecondary),
      ),
      cardTheme: const CardThemeData(
        color: surface1,
        elevation: 0,
        shadowColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: borderRadius,
          side: BorderSide(color: border),
        ),
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: surface1,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: borderRadiusLg,
          side: BorderSide(color: border),
        ),
        titleTextStyle: title,
        contentTextStyle: body,
      ),
      listTileTheme: const ListTileThemeData(
        minVerticalPadding: 12,
        iconColor: textSecondary,
        textColor: textPrimary,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surface1,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        showDragHandle: true,
        dragHandleColor: borderActive,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(radiusLg)),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: surface3,
        contentTextStyle: body,
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: borderRadius),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: accent,
        linearTrackColor: surface3,
        circularTrackColor: Colors.transparent,
      ),
      dividerTheme: const DividerThemeData(color: border, thickness: 1, space: 24),
      iconTheme: const IconThemeData(color: textPrimary, size: 24),
    );
  }
}
