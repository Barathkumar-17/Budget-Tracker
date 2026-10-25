import 'package:budget_tracker/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_fonts.dart';

void main() {
  setUpAll(loadAppFonts);

  testWidgets('with nobody logged in the app opens on the landing page',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(400, 800); // a phone
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const BudgetApp());
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Know where your money goes.'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Create account'), findsWidgets);
    expect(find.widgetWithText(OutlinedButton, 'Log in'), findsWidgets);
    // the app itself is behind the login
    expect(find.text('Dashboard'), findsNothing);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('Log in opens the login form', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(400, 800);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const BudgetApp());
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.widgetWithText(OutlinedButton, 'Log in').first);
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
  });
}
