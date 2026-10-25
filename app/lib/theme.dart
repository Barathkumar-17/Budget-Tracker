import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Design tokens. The values are the ones in the ResumeMatch stylesheet
/// (ink navy, cobalt, highlighter yellow, green / amber / red states), in
/// light and dark.
@immutable
class Tk extends ThemeExtension<Tk> {
  final Color bg, paper, ink, ink2, ink3, line, line2;
  final Color cobalt, cobaltDark, cobaltSoft, btn, btnHover, link;
  final Color hl, onHl;
  final Color match, matchSoft, miss, missSoft, amber, amberSoft;
  final Color purple, purpleSoft;
  final Color surface2, track, strong, onStrong;

  const Tk({
    required this.bg,
    required this.paper,
    required this.ink,
    required this.ink2,
    required this.ink3,
    required this.line,
    required this.line2,
    required this.cobalt,
    required this.cobaltDark,
    required this.cobaltSoft,
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
    required this.surface2,
    required this.track,
    required this.strong,
    required this.onStrong,
  });

  static const light = Tk(
    bg: Color(0xFFEDF0F4),
    paper: Color(0xFFFFFFFF),
    ink: Color(0xFF18223D),
    ink2: Color(0xFF4A5470),
    ink3: Color(0xFF5F6985),
    line: Color(0xFFD9DEE7),
    line2: Color(0xFF858EA6),
    cobalt: Color(0xFF2F4FD8),
    cobaltDark: Color(0xFF2340B8),
    cobaltSoft: Color(0xFFE6EBFD),
    btn: Color(0xFF2F4FD8),
    btnHover: Color(0xFF2340B8),
    link: Color(0xFF2F4FD8),
    hl: Color(0xFFFFE45C),
    onHl: Color(0xFF18223D),
    match: Color(0xFF0F7A4F),
    matchSoft: Color(0xFFDDF3E9),
    miss: Color(0xFFB5332D),
    missSoft: Color(0xFFFBE6E4),
    amber: Color(0xFF8F5F00),
    amberSoft: Color(0xFFFCF1D6),
    purple: Color(0xFF5B3CC4),
    purpleSoft: Color(0xFFEEE8FB),
    surface2: Color(0xFFF4F6FA),
    track: Color(0xFFE3E7EF),
    strong: Color(0xFF18223D),
    onStrong: Color(0xFFFFFFFF),
  );

  static const dark = Tk(
    bg: Color(0xFF0D1322),
    paper: Color(0xFF141B2F),
    ink: Color(0xFFE7EBF7),
    ink2: Color(0xFFAEB7D1),
    ink3: Color(0xFF8993B0),
    line: Color(0xFF2A3453),
    line2: Color(0xFF6A759A),
    cobalt: Color(0xFF4F6FF0),
    cobaltDark: Color(0xFFA9BBFF),
    cobaltSoft: Color(0xFF1E2A56),
    btn: Color(0xFF3B58D6),
    btnHover: Color(0xFF3250CC),
    link: Color(0xFF8FA5FF),
    hl: Color(0xFFFFE45C),
    onHl: Color(0xFF18223D),
    match: Color(0xFF4CCB93),
    matchSoft: Color(0xFF12382B),
    miss: Color(0xFFFF7B73),
    missSoft: Color(0xFF3F1F1E),
    amber: Color(0xFFE8AE45),
    amberSoft: Color(0xFF3A2D10),
    purple: Color(0xFFB7A5FF),
    purpleSoft: Color(0xFF2A2352),
    surface2: Color(0xFF1B2440),
    track: Color(0xFF27304D),
    strong: Color(0xFF2B3A72),
    onStrong: Color(0xFFFFFFFF),
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

const sans = 'Bricolage';
const display = 'BricolageDisplay';
const serif = 'SourceSerif';

TextStyle _t(double size, FontWeight w, Color color,
        {String family = sans, double? height, double? ls}) =>
    TextStyle(
      fontFamily: family,
      fontSize: size,
      fontWeight: w,
      color: color,
      height: height,
      letterSpacing: ls,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

TextTheme _textTheme(Tk k) => TextTheme(
      // hero headline
      displayLarge: _t(64, FontWeight.w800, k.ink,
          family: display, height: 1.02, ls: -2.2),
      displayMedium: _t(44, FontWeight.w800, k.ink,
          family: display, height: 1.04, ls: -1.5),
      // page title
      headlineMedium: _t(33, FontWeight.w800, k.ink,
          family: display, height: 1.15, ls: -0.4),
      headlineSmall: _t(27, FontWeight.w800, k.ink,
          family: display, height: 1.15, ls: -0.3),
      titleLarge: _t(22, FontWeight.w800, k.ink,
          family: display, height: 1.2, ls: -0.3),
      // panel heading
      titleMedium:
          _t(17.6, FontWeight.w700, k.ink, family: display, height: 1.2),
      titleSmall: _t(15, FontWeight.w700, k.ink, height: 1.25),
      bodyLarge: _t(16, FontWeight.w400, k.ink, height: 1.5),
      bodyMedium: _t(15, FontWeight.w400, k.ink, height: 1.5),
      bodySmall: _t(14, FontWeight.w400, k.ink2, height: 1.45),
      labelLarge: _t(15.2, FontWeight.w600, k.ink, height: 1.2),
      labelMedium: _t(13.6, FontWeight.w600, k.ink2, height: 1.2),
      labelSmall: _t(12.5, FontWeight.w600, k.ink3, height: 1.2),
    );

ThemeData buildTheme(Brightness brightness) {
  final k = brightness == Brightness.dark ? Tk.dark : Tk.light;
  final text = _textTheme(k);
  final radius10 = BorderRadius.circular(10);
  OutlineInputBorder border(Color c, [double w = 1.5]) => OutlineInputBorder(
      borderRadius: radius10, borderSide: BorderSide(color: c, width: w));
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    extensions: [k],
    scaffoldBackgroundColor: k.bg,
    colorScheme: ColorScheme(
      brightness: brightness,
      primary: k.btn,
      onPrimary: Colors.white,
      secondary: k.cobalt,
      onSecondary: Colors.white,
      error: k.miss,
      onError: Colors.white,
      surface: k.paper,
      onSurface: k.ink,
      onSurfaceVariant: k.ink2,
      outline: k.line2,
      outlineVariant: k.line,
      surfaceContainerHighest: k.surface2,
      primaryContainer: k.cobaltSoft,
      onPrimaryContainer: k.cobaltDark,
      errorContainer: k.missSoft,
      onErrorContainer: k.miss,
      secondaryContainer: k.cobaltSoft,
      onSecondaryContainer: k.cobaltDark,
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
    dividerTheme: DividerThemeData(color: k.line, space: 1, thickness: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: k.paper,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      border: border(k.line2),
      enabledBorder: border(k.line2),
      focusedBorder: border(k.cobalt),
      errorBorder: border(k.miss),
      focusedErrorBorder: border(k.miss),
      disabledBorder: border(k.line),
      hintStyle: text.bodyLarge!.copyWith(color: k.ink3),
      errorStyle:
          text.labelSmall!.copyWith(color: k.miss, fontWeight: FontWeight.w500),
      helperStyle:
          text.labelSmall!.copyWith(color: k.ink3, fontWeight: FontWeight.w400),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: k.link,
      selectionColor: k.hl.withValues(alpha: 0.6),
      selectionHandleColor: k.cobalt,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: k.strong,
      contentTextStyle: text.bodyMedium!.copyWith(color: k.onStrong),
      actionTextColor: k.hl,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      width: 560,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: k.paper,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: k.line)),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: k.paper,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: k.line)),
      textStyle: text.bodyMedium,
    ),
    datePickerTheme: DatePickerThemeData(
      backgroundColor: k.paper,
      surfaceTintColor: Colors.transparent,
      headerBackgroundColor: k.strong,
      headerForegroundColor: k.onStrong,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
          color: k.strong, borderRadius: BorderRadius.circular(8)),
      textStyle: text.labelMedium!.copyWith(color: k.onStrong),
    ),
    progressIndicatorTheme:
        ProgressIndicatorThemeData(color: k.cobalt, linearTrackColor: k.track),
    appBarTheme: AppBarTheme(
      systemOverlayStyle: brightness == Brightness.dark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
    ),
  );
}

/// Light / dark / follow the system. The choice is remembered (see auth.dart).
class ThemeController extends ChangeNotifier {
  static const _key = 'theme';
  ThemeMode mode = ThemeMode.system;

  Future<void> restore() async {
    try {
      final v = (await SharedPreferences.getInstance()).getString(_key);
      mode = switch (v) {
        'dark' => ThemeMode.dark,
        'light' => ThemeMode.light,
        _ => ThemeMode.system,
      };
      notifyListeners();
    } catch (_) {}
  }

  Future<void> set(ThemeMode m) async {
    mode = m;
    notifyListeners();
    try {
      await (await SharedPreferences.getInstance()).setString(_key, m.name);
    } catch (_) {}
  }
}

class ThemeScope extends InheritedNotifier<ThemeController> {
  const ThemeScope(
      {super.key, required ThemeController controller, required super.child})
      : super(notifier: controller);

  static ThemeController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ThemeScope>()!.notifier!;
}

/// Category colours for the dot and tag next to a category name.
const _catLight = <Color>[
  Color(0xFF2F4FD8), // cobalt
  Color(0xFF0F7A4F), // green
  Color(0xFF8F5F00), // amber
  Color(0xFF5B3CC4), // purple
  Color(0xFF0E7C8C), // teal
  Color(0xFFB1306F), // magenta
  Color(0xFF7A4B20), // brown
  Color(0xFF4A5470), // slate
  Color(0xFF5E7A12), // olive
];
const _catDark = <Color>[
  Color(0xFF8FA5FF),
  Color(0xFF4CCB93),
  Color(0xFFE8AE45),
  Color(0xFFB7A5FF),
  Color(0xFF4FC6DA),
  Color(0xFFF07DB8),
  Color(0xFFD4A06A),
  Color(0xFFAEB7D1),
  Color(0xFFB4C95A),
];

const _knownCats = <String, int>{
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

Color categoryColor(String name, Brightness b) {
  final key = name.trim().toLowerCase();
  final palette = b == Brightness.dark ? _catDark : _catLight;
  final known = _knownCats[key];
  if (known != null) return palette[known];
  var h = 5381;
  for (final c in key.codeUnits) {
    h = ((h * 33) ^ c) & 0x7fffffff;
  }
  return palette[h % palette.length];
}
