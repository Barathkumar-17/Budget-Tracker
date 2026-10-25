import 'package:budget_tracker/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_fonts.dart';

void main() {
  setUpAll(loadAppFonts);

  testWidgets('with nobody logged in the app opens on the login screen',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(400, 800); // a phone
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const BudgetApp());
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Budget Tracker'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Username'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Password'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Log in'), findsOneWidget);
    expect(find.byType(NavigationBar),
        findsNothing); // the app is behind the login
  });
}
