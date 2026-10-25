import 'package:flutter/services.dart';

/// `flutter test` draws every glyph with a wide fallback font unless the app's
/// fonts are loaded, which makes layouts overflow that fit fine on a device.
/// Call from `setUpAll` in any test that renders real screens.
Future<void> loadAppFonts() async {
  const families = {
    'Bricolage': [
      'assets/fonts/Bricolage-Regular.ttf',
      'assets/fonts/Bricolage-Medium.ttf',
      'assets/fonts/Bricolage-SemiBold.ttf',
      'assets/fonts/Bricolage-Bold.ttf',
    ],
    'BricolageDisplay': [
      'assets/fonts/BricolageDisplay-Bold.ttf',
      'assets/fonts/BricolageDisplay-ExtraBold.ttf',
    ],
    'SourceSerif': [
      'assets/fonts/SourceSerif4-Regular.ttf',
      'assets/fonts/SourceSerif4-SemiBold.ttf',
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
