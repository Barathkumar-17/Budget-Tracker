import 'package:flutter/services.dart';

/// `flutter test` draws every glyph with a wide fallback font unless the app's
/// fonts are loaded, which makes layouts overflow that fit fine on a device.
/// Call from `setUpAll` in any test that renders real screens.
Future<void> loadAppFonts() async {
  const families = {
    'Barlow': [
      'assets/fonts/Barlow-Regular.ttf',
      'assets/fonts/Barlow-Medium.ttf',
      'assets/fonts/Barlow-SemiBold.ttf',
      'assets/fonts/Barlow-Bold.ttf',
    ],
    'BarlowSemiCondensed': [
      'assets/fonts/BarlowSemiCondensed-SemiBold.ttf',
      'assets/fonts/BarlowSemiCondensed-Bold.ttf',
    ],
  };
  for (final entry in families.entries) {
    final loader = FontLoader(entry.key);
    for (final path in entry.value) {
      loader.addFont(rootBundle.load(path));
    }
    await loader.load();
  }
}
