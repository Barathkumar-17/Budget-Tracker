import 'package:budget_tracker/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_fonts.dart';

void main() {
  setUpAll(loadAppFonts);

  testWidgets('shell renders and switches tabs', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(400, 800); // a phone: bottom navigation bar
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const BudgetApp());
    expect(find.byType(NavigationBar), findsOneWidget);
    // Title + nav label both read "Dashboard".
    expect(find.text('Dashboard'), findsNWidgets(2));

    for (final tab in ['Expenses', 'Budgets', 'Recurring', 'Goals']) {
      await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(tab)));
      await tester.pump();
      expect(find.text(tab), findsNWidgets(2));
    }
  });
}
