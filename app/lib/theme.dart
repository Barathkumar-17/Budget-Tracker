import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Design tokens: a midnight canvas with frosted-glass surfaces, cool blue-white
/// text that steps from headline to helper copy, hairline glass edges instead of
/// borders, one violet for the main action, and ember / teal for status only.
@immutable
class Tk extends ThemeExtension<Tk> {
  /// Page background, the deepest layer.
  final Color bg;

  /// A card: a barely visible frost tint above the canvas.
  final Color paper;

  /// Dialogs and the sign-in card: almost opaque midnight.
  final Color deep;

  /// Headline, body, muted, helper text.
  final Color ink, ink2, ink3, ink4;

  /// Hairline edge, and the stronger edge of a focused field.
  final Color line, line2;

  /// The accent (violet) and what sits on it.
  final Color cobalt, btn, btnHover, link;

  /// A bright frost for avatars and small highlights, and the text on it.
  final Color hl, onHl;

  /// Status: within budget (teal) and over budget / low balance (ember).
  final Color match, matchSoft, miss, missSoft, amber, amberSoft;

  /// Tags and soft fills.
  final Color purple, purpleSoft, cobaltSoft;

  /// Pill and field fill, empty bar track, selected tab.
  final Color surface2, track, strong, onStrong;

  const Tk({
    required this.bg,
    required this.paper,
    required this.deep,
    required this.ink,
    required this.ink2,
    required this.ink3,
    required this.ink4,
    required this.line,
    required this.line2,
    required this.cobalt,
    required this.btn,
    required this.btnHover,
    required this.link,
    required this.hl,
    required this.onHl,
    required this.match,
    required this.matchSoft,
    required this.miss,
    required this.missSoft,
    required this.amber,
    required this.amberSoft,
    required this.purple,
    required this.purpleSoft,
    required this.cobaltSoft,
    required this.surface2,
    required this.track,
    required this.strong,
    required this.onStrong,
  });

  static const midnight = Color(0xFF05060F);
  static const steel = Color(0xFF2F343E);
  static const fog = Color(0xFF9DA7BA);
  static const mist = Color(0xFFC7D3EA);
  static const frost = Color(0xFFD1E4FA);
  static const ice = Color(0xFFD8ECF8);
  static const iceDeep = Color(0xFF98C0EF);
  static const violet = Color(0xFF663AF3);
  static const blueprint = Color(0xFFB6D9FC);
  static const ember = Color(0xFFE46D4C);
  static const signal = Color(0xFF027DEA);
  static const teal = Color(0xFF269684);

  /// rgba(186, 215, 247, a): the frosted blue-white used for every hairline.
  static Color frostA(double a) => Color.fromRGBO(186, 215, 247, a);

  static final dark = Tk(
    bg: midnight,
    paper: frostA(0.03),
    // Opaque (the reference uses 97%): text behind a dialog must not ghost through.
    deep: const Color(0xFF070812),
    ink: ice,
    ink2: frost,
    ink3: mist,
    ink4: fog,
    line: frostA(0.12),
    line2: frostA(0.24),
    cobalt: violet,
    btn: violet,
    btnHover: const Color(0xFF7A55F5),
    link: blueprint,
    hl: frost,
    onHl: midnight,
    match: const Color(0xFF3FBFA8),
    matchSoft: teal.withValues(alpha: 0.16),
    miss: const Color(0xFFF08A6D),
    missSoft: ember.withValues(alpha: 0.14),
    amber: const Color(0xFFF08A6D),
    amberSoft: ember.withValues(alpha: 0.14),
    purple: blueprint,
    purpleSoft: const Color(0x1FC7D3EA),
    cobaltSoft: const Color(0x1FC7D3EA),
    surface2: Color.fromRGBO(186, 214, 247, 0.06),
    track: Color.fromRGBO(199, 211, 234, 0.12),
    strong: Color.fromRGBO(186, 214, 247, 0.14),
    onStrong: Colors.white,
  );

  @override
  Tk copyWith() => this;

  @override
  Tk lerp(ThemeExtension<Tk>? other, double t) =>
      t < 0.5 ? this : (other as Tk? ?? this);
}

extension TkContext on BuildContext {
  Tk get tk => Theme.of(this).extension<Tk>()!;
}

/// Body and interface (Inter stands in for Untitled Sans), display headings
/// (Space Grotesk for Aeonik) and the tracked all-caps labels (JetBrains Mono
/// for dotDigital).
const sans = 'UntitledSans';
const display = 'Aeonik';
const mono = 'DotDigital';

TextStyle _t(double size, FontWeight w, Color color,
        {String family = sans, double? height, double? ls}) =>
    TextStyle(
      fontFamily: family,
      fontFamilyFallback: const [sans],
      fontSize: size,
      fontWeight: w,
      color: color,
      height: height,
      letterSpacing: ls,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

TextTheme _textTheme(Tk k) => TextTheme(
      // the hero wordmark
      displayLarge: _t(48, FontWeight.w500, k.ink,
          family: display, height: 1.17, ls: -0.5),
      displayMedium:
          _t(44, FontWeight.w500, k.ink, family: display, height: 1.16),
      // page title
      headlineMedium:
          _t(28, FontWeight.w500, k.ink, family: display, height: 1.14),
      headlineSmall: _t(24, FontWeight.w500, k.ink,
          family: display, height: 1.17, ls: -0.24),
      titleLarge: _t(24, FontWeight.w500, k.ink,
          family: display, height: 1.17, ls: -0.24),
      // panel heading
      titleMedium:
          _t(18, FontWeight.w500, k.ink, family: display, height: 1.33),
      titleSmall: _t(14, FontWeight.w500, k.ink, height: 1.43),
      bodyLarge: _t(16, FontWeight.w400, k.ink2, height: 1.5, ls: -0.16),
      bodyMedium: _t(14, FontWeight.w400, k.ink2, height: 1.43),
      bodySmall: _t(14, FontWeight.w400, k.ink3, height: 1.43),
      labelLarge: _t(14, FontWeight.w500, k.ink, height: 1.43),
      labelMedium: _t(12, FontWeight.w500, k.ink3, height: 1.33),
      labelSmall: _t(12, FontWeight.w400, k.ink4, height: 1.33),
    );

/// The app is dark only: the design has no light palette.
ThemeData buildTheme() {
  final k = Tk.dark;
  final text = _textTheme(k);
  final radius6 = BorderRadius.circular(6);
  OutlineInputBorder border(Color c) => OutlineInputBorder(
      borderRadius: radius6, borderSide: BorderSide(color: c, width: 1));
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    extensions: [k],
    scaffoldBackgroundColor: Colors.transparent,
    canvasColor: k.bg,
    colorScheme: ColorScheme(
      brightness: Brightness.dark,
      primary: k.btn,
      onPrimary: Colors.white,
      secondary: k.cobalt,
      onSecondary: Colors.white,
      error: k.miss,
      onError: Colors.white,
      surface: k.bg,
      onSurface: k.ink,
      onSurfaceVariant: k.ink3,
      outline: k.line2,
      outlineVariant: k.line,
      surfaceContainerHighest: k.surface2,
      primaryContainer: k.cobaltSoft,
      onPrimaryContainer: k.ink2,
      errorContainer: k.missSoft,
      onErrorContainer: k.miss,
      secondaryContainer: k.cobaltSoft,
      onSecondaryContainer: k.ink2,
      tertiaryContainer: k.amberSoft,
      onTertiaryContainer: k.amber,
      tertiary: k.amber,
      inverseSurface: k.strong,
      onInverseSurface: k.onStrong,
      shadow: Colors.black,
      scrim: Colors.black,
    ),
    textTheme: text,
    primaryTextTheme: text,
    fontFamily: sans,
    splashFactory: InkRipple.splashFactory,
    splashColor: k.surface2,
    highlightColor: Colors.transparent,
    hoverColor: Tk.frostA(0.04),
    dividerTheme: DividerThemeData(color: k.line, space: 1, thickness: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color.fromRGBO(199, 211, 234, 0.06),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
      border: border(k.line),
      enabledBorder: border(k.line),
      focusedBorder: border(k.line2),
      errorBorder: border(k.miss),
      focusedErrorBorder: border(k.miss),
      disabledBorder: border(k.line),
      hintStyle: text.bodyLarge!
          .copyWith(color: const Color.fromRGBO(199, 211, 234, 0.6)),
      errorStyle:
          text.labelSmall!.copyWith(color: k.miss, fontWeight: FontWeight.w500),
      helperStyle: text.labelSmall!.copyWith(color: k.ink4),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: k.ink,
      selectionColor: k.cobalt.withValues(alpha: 0.5),
      selectionHandleColor: k.link,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xFF0B0D1A),
      contentTextStyle: text.bodyMedium!.copyWith(color: k.ink),
      actionTextColor: k.link,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: k.line2)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: k.deep,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: k.line)),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: k.deep,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: k.line)),
      textStyle: text.bodyMedium,
    ),
    datePickerTheme: DatePickerThemeData(
      backgroundColor: const Color(0xFF0B0D1A),
      surfaceTintColor: Colors.transparent,
      headerBackgroundColor: const Color(0xFF111426),
      headerForegroundColor: k.ink,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
          color: const Color(0xFF111426),
          border: Border.all(color: k.line2),
          borderRadius: BorderRadius.circular(6)),
      textStyle: text.labelMedium!.copyWith(color: k.ink),
    ),
    progressIndicatorTheme:
        ProgressIndicatorThemeData(color: k.link, linearTrackColor: k.track),
    appBarTheme:
        const AppBarTheme(systemOverlayStyle: SystemUiOverlayStyle.light),
  );
}

/// Category colours for the dot and tag next to a category name. The palette
/// has no extra hues, so categories are told apart by steps of cool blue-white.
const _cats = <Color>[
  Color(0xFFB6D9FC), // blueprint
  Color(0xFF3FBFA8), // teal
  Color(0xFF6FA8F2), // signal, lightened
  Color(0xFFD8ECF8), // ice
  Color(0xFF8E9BF5), // violet, lightened
  Color(0xFF9DA7BA), // fog
  Color(0xFF98C0EF), // ice deep
  Color(0xFF5FD0E0), // cyan
  Color(0xFFC7D3EA), // mist
];

const _knownCats = <String, int>{
  'food': 0,
  'snacks': 0,
  'tea': 0,
  'transport': 2,
  'rent': 4,
  'fun': 3,
  'shopping': 7,
  'bills': 5,
  'health': 1,
  'subscriptions': 6,
  'netflix': 6,
  'gym': 8,
};

Color categoryColor(String name, [Brightness? _]) {
  final key = name.trim().toLowerCase();
  final known = _knownCats[key];
  if (known != null) return _cats[known];
  var h = 5381;
  for (final c in key.codeUnits) {
    h = ((h * 33) ^ c) & 0x7fffffff;
  }
  return _cats[h % _cats.length];
}
