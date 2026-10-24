import 'package:flutter/material.dart';

/// The app's colors, split into two deliberately separate groups:
///
///  1. THEME / UI colors (brand orange, ink, surfaces, text, borders) —
///     page backgrounds, sidebar, app bar, buttons, table headers, etc.
///     Restyle these freely.
///  2. DATA colors (perf tiers, pitch types, spray outcomes, call/event
///     colors, [dataBlue]/[dataNavy]) — ported 1:1 from the R Shiny app's
///     PERF_COLORS / pitch & spray palettes. These must NEVER change just
///     because the UI theme does; the exact hex values are what make the
///     charts read the same as the Shiny app.
/// Single source of truth for the app's typeface. SKOUTAR uses Teko
/// everywhere (bundled in assets/fonts so it loads offline and never
/// depends on a network font request). To change the font app-wide, change
/// [family] here and the `fonts:` block in pubspec.yaml — nothing else.
///
/// Teko ships 300-700 upright weights only. Any heavier request (w800/w900,
/// used throughout the app) resolves to Bold (700); italics are the
/// engine's synthetic oblique of the upright face.
class AppFonts {
  static const String family = 'Teko';

  /// Teko's lowercase/x-height is small and its letterforms are narrow, so
  /// the whole app is scaled up slightly (applied once in MaterialApp.builder)
  /// to keep it as readable as the old font at the same nominal sizes.
  static const double textScale = 1.12;

  /// For canvas/chart text that does NOT inherit the theme (TextPainter,
  /// fl_chart tooltips): `TextStyle(fontFamily: AppFonts.family, ...)`.
  static const TextStyle base = TextStyle(fontFamily: family);
}

class AppColors {
  // Performance tiers (used to color-code stat boxes / tables)
  static const Color perfExcellent = Color(0xFF15803D);
  static const Color perfGood = Color(0xFF4ADE80);
  static const Color perfAverage = Color(0xFFFACC15);
  static const Color perfBelowAvg = Color(0xFFFB923C);
  static const Color perfPoor = Color(0xFFDC2626);

  /// The five graded tier colors, in one place so every colored cell can be
  /// recognised and styled the same way (see [ScaleStyle]).
  static const List<Color> perfTiers = [perfExcellent, perfGood, perfAverage, perfBelowAvg, perfPoor];

  // ── THEME / UI colors ────────────────────────────────────────
  // Brand palette (from the orange logo). Orange is an accent; the
  // chrome (sidebar, app bar, headers) is a warm near-black "ink" taken
  // from the logo's black outline so the orange pops instead of flooding.
  static const Color brandOrange = Color(0xFFED652A); // primary accent
  static const Color brandOrangeMid = Color(0xFFEF874B);
  static const Color brandOrangeSoft = Color(0xFFF2AD77);
  static const Color brandPeach = Color(0xFFF8D3AB);
  static const Color brandCream = Color(0xFFFFFBDF);

  /// Darker shade of [brandOrange] for filled buttons / selected fills that
  /// carry white text (white on [brandOrange] is only ~3.5:1; this is ~4.6:1).
  static const Color brandOrangeDeep = Color(0xFFC94F1B);

  /// Dark chrome: sidebar, app bar, login background, table header rows,
  /// and strong headings.
  static const Color ink = Color(0xFF26201C);

  /// Page background (a light tint of [brandCream]) and soft neutral fills
  /// for stat boxes / tiles that sit on white cards.
  static const Color pageBg = Color(0xFFFFFDF3);
  static const Color tint = Color(0xFFFDF1E4);
  static const Color surfaceAlt = Color(0xFFFBF7F0);

  // ── DATA colors: do not restyle with the theme ───────────────────
  // These two blues are NOT UI colors. They encode data: ball calls
  // ('b'), balls in play ('ip') and non-pitch events in the Game Input
  // call/event system, and the ERA line on Game Logs. Values are
  // identical to the old blueMid / blueDark.
  static const Color dataBlue = Color(0xFF3B82F6);
  static const Color dataNavy = Color(0xFF1E3A8A);

  // Single orange used for every main-navigation icon, so the sidebar
  // reads as one consistent accent color rather than a rotating palette.
  static const Color navIconOrange = brandOrangeMid;

  // Text / borders
  static const Color colText = Color(0xFF1C1917);
  static const Color colMuted = Color(0xFF78716C);
  static const Color colBorder = Color(0xFFE7DCCF);
  static const Color colSuccess = Color(0xFF22C55E);
  static const Color colError = Color(0xFFEF4444);

  // Pitch type ring colors
  static const Map<String, Color> pitchColors = {
    'fb': Color(0xFF2563EB),
    'sl': Color(0xFF7C3AED),
    'cv': Color(0xFFDB2777),
    'ch': Color(0xFF14B8A6),
    'other': Color(0xFF6B7280),
  };

  // Spray-chart outcome fill colors
  static const Map<String, Color> sprayOutcomeColors = {
    '1b': Color(0xFF22C55E),
    '2b': Color(0xFF2563EB),
    '3b': Color(0xFF7C3AED),
    'hr': Color(0xFFF97316),
    'go': Color(0xFFDC2626),
    'fo': Color(0xFFDC2626),
    'lo': Color(0xFFDC2626),
    'dp': Color(0xFFDC2626),
    'e': Color(0xFFFACC15),
    'fc': Color(0xFF6B7280),
    'out': Color(0xFFDC2626),
  };

  // Fallback palette for custom/user-defined pitch types (e.g. "KN", "EP")
  // that aren't one of the built-in fb/sl/cv/ch codes. Picked deterministically
  // from the code so the same custom pitch always gets the same color.
  static const List<Color> _customPitchPalette = [
    Color(0xFFEA580C), // orange
    Color(0xFF059669), // emerald
    Color(0xFFCA8A04), // amber
    Color(0xFF9333EA), // purple
    Color(0xFFE11D48), // rose
    Color(0xFF0891B2), // cyan
    Color(0xFF65A30D), // lime
    Color(0xFFBE185D), // pink
  ];

  /// User-chosen colors for custom pitch types (set on Game Input when a
  /// new pitch is created — see [AppSession.addCustomPitchType]), keyed by
  /// the same lowercase, trimmed key used everywhere else a pitch type is
  /// looked up. Checked first so a color picked once is used consistently
  /// everywhere a pitch appears: the pitch button, the spray chart, pitch
  /// history, pitch breakdown, and every other pitch visualization.
  static final Map<String, Color> _customOverrides = {};

  /// Replaces the whole custom-color override table — called once on
  /// login/logout and whenever a custom pitch color is added, changed, or
  /// removed, so every screen reading [pitchColor] picks up the change
  /// immediately without needing its own copy of the data.
  static void setCustomPitchColors(Map<String, Color> colors) {
    _customOverrides
      ..clear()
      ..addAll(colors);
  }

  static Color pitchColor(String? pt) {
    if (pt == null || pt.trim().isEmpty) return pitchColors['other']!;
    final key = pt.toLowerCase().trim();
    if (_customOverrides.containsKey(key)) return _customOverrides[key]!;
    if (pitchColors.containsKey(key)) return pitchColors[key]!;
    final sum = key.codeUnits.fold<int>(0, (a, b) => a + b);
    return _customPitchPalette[sum % _customPitchPalette.length];
  }

  /// Preset swatches offered when creating a new pitch type — deliberately
  /// a fixed palette (no color-wheel dependency) so every custom pitch
  /// still reads as part of the same professional analytics look.
  static const List<Color> pitchColorPresets = [
    Color(0xFFEA580C), // orange
    Color(0xFF059669), // emerald
    Color(0xFFCA8A04), // amber
    Color(0xFF9333EA), // purple
    Color(0xFFE11D48), // rose
    Color(0xFF0891B2), // cyan
    Color(0xFF65A30D), // lime
    Color(0xFFBE185D), // pink
    Color(0xFF2563EB), // blue
    Color(0xFF475569), // slate
    Color(0xFFB45309), // brown
    Color(0xFF0D9488), // teal
  ];

  static Color sprayColor(String? outcome) {
    if (outcome == null) return const Color(0xFFDC2626);
    return sprayOutcomeColors[outcome.toLowerCase().trim()] ??
        const Color(0xFFDC2626);
  }
}

/// The app's ThemeData — white cards on a warm cream page, dark "ink"
/// chrome and brand-orange accents.
ThemeData buildAppTheme() {
  return ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: AppColors.pageBg,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.brandOrange,
      primary: AppColors.brandOrangeDeep,
      secondary: AppColors.brandOrange,
    ),
    fontFamily: AppFonts.family,
    cardTheme: CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.colBorder, width: 1.5),
      ),
      margin: const EdgeInsets.only(bottom: 8),
    ),
    // Gives dialogs a little more room on phones; no visible change on
    // desktop where dialogs are far narrower than the window.
    dialogTheme: const DialogThemeData(
      elevation: 10,
      shadowColor: Color(0xB3ED652A),
      insetPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 24),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.ink,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: false,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.brandOrangeDeep,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontFamily: AppFonts.family, fontWeight: FontWeight.w800, fontSize: 14),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.colBorder, width: 2),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.colBorder, width: 2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.brandOrange, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    ),
    // Applies to every hover/long-press tooltip in the app — plain Tooltip
    // widgets AND the `tooltip:` shorthand on IconButton etc. — so every
    // popup shares the same dark ink background with guaranteed-readable
    // white text, regardless of what's behind it.
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: AppColors.ink.withOpacity(0.96),
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(color: Color(0x33000000), blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      textStyle: const TextStyle(
        fontFamily: AppFonts.family,
        color: Colors.white,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        height: 1.3,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      margin: const EdgeInsets.all(8),
      preferBelow: true,
      waitDuration: const Duration(milliseconds: 400),
    ),
  );
}


/// One look for every color-scale CELL / BOX in the app (stat boxes, table
/// cells, heat-map blocks): a bright border in the tier's own color and a
/// duller (less saturated, slightly lighter) interior of the same color.
///
/// Progress bars deliberately do NOT use this - they keep their original
/// solid colors. Non-tier colors (neutral tints, pitch colors, etc.) pass
/// through unchanged.
class ScaleStyle {
  ScaleStyle._();

  static bool isTier(Color c) => AppColors.perfTiers.contains(c);

  /// Bright border color (the tier color itself).
  static Color border(Color c) => c;

  /// Duller interior of ANY color: same hue, noticeably less saturated, and a
  /// consistent mid-light value so dark text stays readable on every tier.
  static Color fillAny(Color c) {
    final hsl = HSLColor.fromColor(c);
    return hsl
        .withSaturation((hsl.saturation * 0.55).clamp(0.0, 1.0))
        .withLightness(0.80)
        .toColor();
  }

  /// Duller interior for tier colors; non-tier colors pass through.
  static Color fill(Color c) => isTier(c) ? fillAny(c) : c;

  /// Text color that stays readable on the duller interior (always dark).
  static Color textOn(Color tier) => AppColors.colText;

  /// Box decoration for a scale cell. [radius] 0 = square corners.
  static BoxDecoration box(Color c, {double radius = 0, double width = 2}) {
    if (!isTier(c)) {
      return BoxDecoration(color: c, borderRadius: radius > 0 ? BorderRadius.circular(radius) : null);
    }
    return BoxDecoration(
      color: fill(c),
      border: Border.all(color: border(c), width: width),
      borderRadius: radius > 0 ? BorderRadius.circular(radius) : null,
    );
  }
}
