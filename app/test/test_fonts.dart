import 'package:flutter/services.dart';

/// `flutter test` draws every glyph with a wide fallback font unless the app's
/// fonts are loaded, which makes layouts overflow that fit fine on a device.
/// Call from `setUpAll` in any test that renders real screens.
Future<void> loadAppFonts() async {
  const families = {
    'UntitledSans': [
      'assets/fonts/Inter-Regular.ttf',
      'assets/fonts/Inter-Medium.ttf',
      'assets/fonts/Inter-SemiBold.ttf',
      'assets/fonts/Inter-Bold.ttf',
    ],
    'Aeonik': [
      'assets/fonts/SpaceGrotesk-Regular.ttf',
      'assets/fonts/SpaceGrotesk-Medium.ttf',
    ],
    'DotDigital': ['assets/fonts/JetBrainsMono-Regular.ttf'],
  };
  for (final entry in families.entries) {
    final loader = FontLoader(entry.key);
    for (final path in entry.value) {
      loader.addFont(rootBundle.load(path));
    }
    await loader.load();
  }
}
