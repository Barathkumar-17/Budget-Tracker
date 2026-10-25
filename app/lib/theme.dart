import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Station-board navy: the header band that carries the month.
const _navyLight = Color(0xFF12233F);
const _navyDark = Color(0xFF0A1220);

const _lightScheme = ColorScheme(
  brightness: Brightness.light,
  primary: Color(0xFF1B4BD2),
  onPrimary: Color(0xFFFFFFFF),
  primaryContainer: Color(0xFFDCE5FF),
  onPrimaryContainer: Color(0xFF0A1F66),
  secondary: Color(0xFF4A5B78),
  onSecondary: Color(0xFFFFFFFF),
  secondaryContainer: Color(0xFFDDE5F2),
  onSecondaryContainer: Color(0xFF16243D),
  tertiary: Color(0xFF8A4F00),
  onTertiary: Color(0xFFFFFFFF),
  tertiaryContainer: Color(0xFFFFE2B8),
  onTertiaryContainer: Color(0xFF3A2000),
  error: Color(0xFFB3261E),
  onError: Color(0xFFFFFFFF),
  errorContainer: Color(0xFFFFDAD5),
  onErrorContainer: Color(0xFF410002),
  surface: Color(0xFFF3F6FA),
  onSurface: Color(0xFF111B2B),
  onSurfaceVariant: Color(0xFF47546A),
  outline: Color(0xFF76839A),
  outlineVariant: Color(0xFFD3DBE8),
  surfaceContainerLowest: Color(0xFFFFFFFF),
  surfaceContainerLow: Color(0xFFEBF0F7),
  surfaceContainer: Color(0xFFE5EBF4),
  surfaceContainerHigh: Color(0xFFDFE6F0),
  surfaceContainerHighest: Color(0xFFD9E1ED),
  inverseSurface: Color(0xFF1F2B3F),
  onInverseSurface: Color(0xFFEFF3FA),
  inversePrimary: Color(0xFFB7C8FF),
  shadow: Color(0xFF000000),
  scrim: Color(0xFF000000),
);

const _darkScheme = ColorScheme(
  brightness: Brightness.dark,
  primary: Color(0xFFA9C0FF),
  onPrimary: Color(0xFF0B2470),
  primaryContainer: Color(0xFF1E3A99),
  onPrimaryContainer: Color(0xFFDCE5FF),
  secondary: Color(0xFFB4C4E0),
  onSecondary: Color(0xFF1A2A44),
  secondaryContainer: Color(0xFF2E3F5C),
  onSecondaryContainer: Color(0xFFDDE5F2),
  tertiary: Color(0xFFFFB95C),
  onTertiary: Color(0xFF4A2800),
  tertiaryContainer: Color(0xFF5C3600),
  onTertiaryContainer: Color(0xFFFFE2B8),
  error: Color(0xFFFFB4AB),
  onError: Color(0xFF690005),
  errorContainer: Color(0xFF93000A),
  onErrorContainer: Color(0xFFFFDAD5),
  surface: Color(0xFF0E141C),
  onSurface: Color(0xFFE4EAF3),
  onSurfaceVariant: Color(0xFFABB7CB),
  outline: Color(0xFF7C889D),
  outlineVariant: Color(0xFF2B3647),
  surfaceContainerLowest: Color(0xFF090E14),
  surfaceContainerLow: Color(0xFF131B25),
  surfaceContainer: Color(0xFF18212D),
  surfaceContainerHigh: Color(0xFF1F2A38),
  surfaceContainerHighest: Color(0xFF273343),
  inverseSurface: Color(0xFFE4EAF3),
  onInverseSurface: Color(0xFF1F2B3F),
  inversePrimary: Color(0xFF1B4BD2),
  shadow: Color(0xFF000000),
  scrim: Color(0xFF000000),
);

/// Category line colours. Deliberately no red: red only ever means over budget.
const _linesLight = <Color>[
  Color(0xFF2458D6), // blue
  Color(0xFF0F8A5F), // green
  Color(0xFFC77100), // amber
  Color(0xFF7A45C9), // violet
  Color(0xFF0E8CA0), // teal
  Color(0xFFB83280), // magenta
  Color(0xFF8A5A2B), // brown
  Color(0xFF4E6285), // slate
  Color(0xFF6B7F1A), // olive
];

const _linesDark = <Color>[
  Color(0xFF7FA2FF),
  Color(0xFF4CCB98),
  Color(0xFFFFB347),
  Color(0xFFB993F5),
  Color(0xFF4FC6DA),
  Color(0xFFF07DB8),
  Color(0xFFD4A06A),
  Color(0xFF9DB1D4),
  Color(0xFFB4C95A),
];

/// Common categories keep a fixed line colour; anything else hashes into the palette.
const _knownLines = <String, int>{
  'food': 2,
  'snacks': 2,
  'tea': 2,
  'transport': 0,
  'rent': 3,
  'fun': 5,
  'shopping': 4,
  'bills': 7,
  'health': 1,
  'subscriptions': 6,
  'netflix': 6,
  'gym': 8,
};

/// Stable colour for a category name (case-insensitive).
Color categoryColor(String name, Brightness b) {
  final key = name.trim().toLowerCase();
  final palette = b == Brightness.dark ? _linesDark : _linesLight;
  final known = _knownLines[key];
  if (known != null) return palette[known];
  var h = 5381;
  for (final c in key.codeUnits) {
    h = ((h * 33) ^ c) & 0x7fffffff;
  }
  return palette[h % palette.length];
}

/// Colour of an overrun line segment and its terminus ring. In dark mode the
/// text-safe pastel error colour is too close to the category lines, so the
/// line itself uses a more saturated red.
Color alertLineColor(Brightness b) =>
    b == Brightness.dark ? const Color(0xFFFF5D4D) : _lightScheme.error;

/// Header band colour, shared by the app bar and the navigation rail.
Color headerColor(Brightness b) =>
    b == Brightness.dark ? _navyDark : _navyLight;

const _tabular = [FontFeature.tabularFigures()];

/// Style for amounts: semi-condensed, tabular figures so columns line up.
TextStyle amountStyle(BuildContext context,
    {double size = 17, FontWeight weight = FontWeight.w600, Color? color}) {
  return TextStyle(
    fontFamily: 'BarlowSemiCondensed',
    fontSize: size,
    fontWeight: weight,
    color: color ?? Theme.of(context).colorScheme.onSurface,
    fontFeatures: _tabular,
    height: 1.2,
  );
}

TextTheme _textTheme(ColorScheme s) {
  TextStyle t(double size, FontWeight w, {double? height, double? ls}) =>
      TextStyle(
        fontFamily: 'Barlow',
        fontSize: size,
        fontWeight: w,
        height: height,
        letterSpacing: ls,
        color: s.onSurface,
        fontFeatures: _tabular,
      );
  return TextTheme(
    headlineMedium: t(30, FontWeight.w600, height: 1.15),
    headlineSmall: t(25, FontWeight.w600, height: 1.2),
    titleLarge: t(22, FontWeight.w600, height: 1.2),
    titleMedium: t(18, FontWeight.w600, height: 1.25),
    titleSmall: t(16, FontWeight.w600, height: 1.25),
    bodyLarge: t(17, FontWeight.w400, height: 1.35),
    bodyMedium: t(15, FontWeight.w400, height: 1.35),
    bodySmall: t(13, FontWeight.w400, height: 1.3),
    labelLarge: t(16, FontWeight.w600, height: 1.2, ls: 0.1),
    labelMedium: t(14, FontWeight.w500, height: 1.2, ls: 0.2),
    labelSmall: t(12, FontWeight.w500, height: 1.2, ls: 0.3),
  );
}

ThemeData buildTheme(Brightness brightness) {
  final s = brightness == Brightness.dark ? _darkScheme : _lightScheme;
  final text = _textTheme(s);
  final header = headerColor(brightness);
  final radius = BorderRadius.circular(12);
  return ThemeData(
    useMaterial3: true,
    colorScheme: s,
    scaffoldBackgroundColor: s.surface,
    textTheme: text,
    primaryTextTheme: text,
    fontFamily: 'Barlow',
    visualDensity: VisualDensity.standard,
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: AppBarTheme(
      backgroundColor: header,
      foregroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: text.titleLarge!.copyWith(color: Colors.white),
      systemOverlayStyle:
          SystemUiOverlayStyle.light.copyWith(statusBarColor: header),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: s.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      indicatorColor: s.primaryContainer,
      height: 72,
      labelTextStyle: WidgetStateProperty.resolveWith((states) =>
          text.labelMedium!.copyWith(
              fontSize: 13,
              color: states.contains(WidgetState.selected)
                  ? s.onSurface
                  : s.onSurfaceVariant,
              fontWeight: states.contains(WidgetState.selected)
                  ? FontWeight.w600
                  : FontWeight.w500)),
      iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
          size: 24,
          color: states.contains(WidgetState.selected)
              ? s.onPrimaryContainer
              : s.onSurfaceVariant)),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: s.surfaceContainer,
      indicatorColor: s.primaryContainer,
      selectedLabelTextStyle: text.labelMedium!
          .copyWith(color: s.onSurface, fontWeight: FontWeight.w600),
      unselectedLabelTextStyle:
          text.labelMedium!.copyWith(color: s.onSurfaceVariant),
      selectedIconTheme: IconThemeData(color: s.onPrimaryContainer),
      unselectedIconTheme: IconThemeData(color: s.onSurfaceVariant),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: s.primary,
      foregroundColor: s.onPrimary,
      elevation: 3,
      extendedTextStyle: text.labelLarge!.copyWith(color: s.onPrimary),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 48),
        textStyle: text.labelLarge,
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
          minimumSize: const Size(64, 48), textStyle: text.labelLarge),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: s.surfaceContainerLow,
      border: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: s.outlineVariant)),
      enabledBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: s.outlineVariant)),
      focusedBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: s.primary, width: 2)),
      errorBorder: OutlineInputBorder(
          borderRadius: radius, borderSide: BorderSide(color: s.error)),
      focusedErrorBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: s.error, width: 2)),
      labelStyle: text.bodyLarge!.copyWith(color: s.onSurfaceVariant),
      helperStyle: text.bodySmall!.copyWith(color: s.onSurfaceVariant),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: s.inverseSurface,
      contentTextStyle: text.bodyMedium!.copyWith(color: s.onInverseSurface),
      actionTextColor: s.inversePrimary,
      shape: RoundedRectangleBorder(borderRadius: radius),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: s.surfaceContainerLowest,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: s.surfaceContainerLowest,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    dividerTheme:
        DividerThemeData(color: s.outlineVariant, space: 1, thickness: 1),
    listTileTheme: ListTileThemeData(
      iconColor: s.onSurfaceVariant,
      minVerticalPadding: 8,
    ),
  );
}
