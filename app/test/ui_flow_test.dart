// Hermetic UI tests: the real app talks to an in-memory stub of the API
// (package:http MockClient), so no backend is needed.
import 'dart:convert';

import 'package:budget_tracker/common.dart';
import 'package:budget_tracker/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

typedef Handler = http.Response Function(http.Request req);

http.Response json(Object body, [int status = 200]) => http.Response(
    jsonEncode(body), status,
    headers: {'content-type': 'application/json'});

final emptyDashboard = {
  'month': monthKey(DateTime.now()),
  'total_spent': 0,
  'categories': [],
  'trend': [],
  'balance': 1000.0,
  'low_balance_threshold': 0.0,
  'low_balance': false,
};

void uiTest(
  String name,
  Map<String, Handler> routes,
  Future<void> Function(WidgetTester t, List<http.Request> calls) body,
) {
  testWidgets(name, (t) async {
    final calls = <http.Request>[];
    final all = <String, Handler>{
      'GET /dashboard': (_) => json(emptyDashboard),
      'GET /expenses': (_) => json([]),
      'GET /budgets': (_) => json([]),
      'GET /recurring': (_) => json([]),
      'GET /goals': (_) => json([]),
      ...routes,
    };
    await http.runWithClient(() async {
      await t.binding.setSurfaceSize(const Size(500, 1000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(const BudgetApp());
      await settle(t);
      await body(t, calls);
    }, () => MockClient((req) async {
          calls.add(req);
          final h = all['${req.method} ${req.url.path}'];
          return h == null ? json({'detail': 'no stub for ${req.method} ${req.url.path}'}, 404) : h(req);
        }));
  });
}

Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 5; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> tab(WidgetTester t, String name) async {
  await t.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(name)));
  await settle(t);
}

Future<void> tapIcon(WidgetTester t, IconData icon) async {
  await t.tap(find.byIcon(icon));
  await settle(t);
}

/// Types into the dialog fields (by label) and presses Save.
Future<void> fillAndSave(WidgetTester t, Map<String, String> fields) async {
  for (final e in fields.entries) {
    await t.enterText(find.widgetWithText(TextField, e.key), e.value);
  }
  await t.tap(find.text('Save'));
  await settle(t);
}

Map<String, dynamic> bodyOf(http.Request r) => jsonDecode(r.body) as Map<String, dynamic>;
http.Request last(List<http.Request> calls, String method, String path) =>
    calls.lastWhere((c) => c.method == method && c.url.path == path);

void main() {
  uiTest('add expense over budget shows the overspend alert', {
    'POST /expenses': (_) => json({
          'expense': {'id': 1},
          'alert': {'category': 'food', 'over_by': 50.0},
          'balance': 850.0,
          'low_balance': false,
        }, 201),
  }, (t, calls) async {
    await tab(t, 'Expenses');
    expect(find.text('No expenses this month'), findsOneWidget);
    await tapIcon(t, Icons.add);
    await fillAndSave(t, {'Amount': '150', 'Category': 'Food', 'Note (optional)': 'lunch'});

    expect(find.text('Over budget in food by ₹50.00'), findsOneWidget);
    final sent = bodyOf(last(calls, 'POST', '/expenses'));
    expect(sent['amount'], 150.0);
    expect(sent['category'], 'Food');
    expect(sent['note'], 'lunch');
    expect(sent['date'], dateKey(DateTime.now()));
  });

  uiTest('add expense that drops balance below threshold shows low-balance alert', {
    'POST /expenses': (_) => json({
          'expense': {'id': 1},
          'alert': null,
          'balance': 450.0,
          'low_balance': true,
        }, 201),
  }, (t, calls) async {
    await tab(t, 'Expenses');
    await tapIcon(t, Icons.add);
    await fillAndSave(t, {'Amount': '400', 'Category': 'Rent'});
    expect(find.text('Low balance: ₹450.00'), findsOneWidget);
  });

  uiTest('expense form validates before calling the server', {}, (t, calls) async {
    await tab(t, 'Expenses');
    await tapIcon(t, Icons.add);
    await fillAndSave(t, {'Amount': '0', 'Category': 'Food'});
    expect(find.text('Amount and category are required'), findsOneWidget);
    expect(calls.where((c) => c.method == 'POST'), isEmpty);
  });

  uiTest('server validation errors are shown readably', {
    'POST /expenses': (_) => json({
          'detail': [
            {'loc': ['body', 'date'], 'msg': 'Input should be a valid date'}
          ]
        }, 422),
  }, (t, calls) async {
    await tab(t, 'Expenses');
    await tapIcon(t, Icons.add);
    await fillAndSave(t, {'Amount': '5', 'Category': 'Food', 'Date (YYYY-MM-DD)': 'garbage'});
    expect(find.text('date: Input should be a valid date'), findsOneWidget);
  });

  uiTest('expenses list shows rows and swipe-to-delete calls the API', {
    'GET /expenses': (_) => json([
          {'id': 3, 'amount': 150.0, 'date': '2026-10-04', 'category': 'food', 'note': 'lunch', 'recurring_id': null},
          {'id': 4, 'amount': 499.0, 'date': '2026-10-05', 'category': 'music', 'note': '', 'recurring_id': 9},
        ]),
    'DELETE /expenses/3': (_) => http.Response('', 204),
  }, (t, calls) async {
    await tab(t, 'Expenses');
    expect(find.text('food  ₹150.00'), findsOneWidget);
    expect(find.text('2026-10-04 · lunch'), findsOneWidget);
    expect(find.byIcon(Icons.repeat), findsNWidgets(2)); // 1 nav icon + 1 recurring row
    await t.drag(find.text('food  ₹150.00'), const Offset(-500, 0));
    await t.pumpAndSettle(); // Dismissible fires onDismissed after its slide animation
    expect(calls.any((c) => c.method == 'DELETE' && c.url.path == '/expenses/3'), isTrue);
  });

  uiTest('dashboard shows over-budget bar and low-balance card; account dialog saves', {
    'GET /dashboard': (_) => json({
          ...emptyDashboard,
          'balance': 450.0,
          'low_balance': true,
          'low_balance_threshold': 500.0,
          'total_spent': 550.0,
          'categories': [
            {'category': 'food', 'spent': 150.0, 'cap': 100.0, 'over': true},
            {'category': 'rent', 'spent': 400.0, 'cap': null, 'over': false},
          ],
          'trend': [
            {'date': '2026-10-04', 'total': 150.0},
            {'date': '2026-10-05', 'total': 400.0},
          ],
        }),
    'GET /account': (_) => json({'opening_balance': 1000.0, 'low_balance_threshold': 500.0}),
    'PUT /account': (_) => json({}),
  }, (t, calls) async {
    expect(find.text('Balance ₹450.00'), findsOneWidget);
    expect(find.text('Low balance — below ₹500.00'), findsOneWidget);
    expect(find.text('₹150.00 / ₹100.00'), findsOneWidget);
    expect(find.text('Over budget'), findsOneWidget);
    expect(find.text('₹400.00'), findsOneWidget); // uncapped category

    await tapIcon(t, Icons.settings);
    await fillAndSave(t, {'Opening balance': '2000', 'Low-balance warning below': '750'});
    final sent = bodyOf(last(calls, 'PUT', '/account'));
    expect(sent['opening_balance'], 2000.0);
    expect(sent['low_balance_threshold'], 750.0);
  });

  uiTest('dashboard rejects non-numeric account input', {
    'GET /account': (_) => json({'opening_balance': 0.0, 'low_balance_threshold': 0.0}),
  }, (t, calls) async {
    await tapIcon(t, Icons.settings);
    await fillAndSave(t, {'Opening balance': 'abc'});
    expect(find.text('Enter valid numbers'), findsOneWidget);
    expect(calls.where((c) => c.method == 'PUT'), isEmpty);
  });

  uiTest('budgets: list, add and validation', {
    'GET /budgets': (_) => json([
          {'category': 'food', 'month': monthKey(DateTime.now()), 'cap': 100.0}
        ]),
    'PUT /budgets': (_) => json({}),
  }, (t, calls) async {
    await tab(t, 'Budgets');
    expect(find.text('food'), findsOneWidget);
    expect(find.text('₹100.00'), findsOneWidget);

    await tapIcon(t, Icons.add);
    await fillAndSave(t, {'Category': 'Travel', 'Monthly cap': '250.5'});
    final sent = bodyOf(last(calls, 'PUT', '/budgets'));
    expect(sent, {'category': 'Travel', 'month': monthKey(DateTime.now()), 'cap': 250.5});

    await tapIcon(t, Icons.add);
    await fillAndSave(t, {'Category': '', 'Monthly cap': '5'});
    expect(find.text('Category and a valid cap are required'), findsOneWidget);
  });

  uiTest('recurring: apply reports created then already applied', {
    'GET /recurring': (_) => json([
          {'id': 1, 'amount': 499.0, 'category': 'music', 'note': 'plan', 'day_of_month': 5}
        ]),
    'POST /recurring/apply': (() {
      var n = 0;
      return (http.Request _) => json({'month': monthKey(DateTime.now()), 'created': n++ == 0 ? 1 : 0});
    })(),
  }, (t, calls) async {
    await tab(t, 'Recurring');
    expect(find.text('music  ₹499.00'), findsOneWidget);
    expect(find.text('Day 5 · plan'), findsOneWidget);

    await t.tap(find.text('Apply to this month'));
    await settle(t);
    expect(find.text('Added 1 expense(s)'), findsOneWidget);
    expect(last(calls, 'POST', '/recurring/apply').url.queryParameters['month'], monthKey(DateTime.now()));

    ScaffoldMessenger.of(t.element(find.byType(Scaffold).first)).clearSnackBars();
    await settle(t);
    await t.pump(const Duration(seconds: 1));
    await t.tap(find.text('Apply to this month'));
    await settle(t);
    expect(find.text('Already applied'), findsOneWidget);
  });

  uiTest('recurring: add validates day and sends template', {
    'POST /recurring': (_) => json({}, 201),
  }, (t, calls) async {
    await tab(t, 'Recurring');
    expect(find.text('No recurring templates'), findsOneWidget);
    await tapIcon(t, Icons.add);
    await fillAndSave(t, {'Amount': '10', 'Category': 'Netflix', 'Day of month (1-28)': '31'});
    expect(find.text('Check amount, category and day (1-28)'), findsOneWidget);
    expect(calls.where((c) => c.method == 'POST'), isEmpty);

    ScaffoldMessenger.of(t.element(find.byType(Scaffold).first)).clearSnackBars();
    await settle(t);
    await t.pump(const Duration(seconds: 1));
    await tapIcon(t, Icons.add);
    await fillAndSave(t, {'Amount': '10', 'Category': 'Netflix', 'Day of month (1-28)': '5'});
    expect(bodyOf(last(calls, 'POST', '/recurring')),
        {'amount': 10.0, 'category': 'Netflix', 'note': '', 'day_of_month': 5});
  });

  uiTest('goals: add, contribute and progress text', {
    'GET /goals': (() {
      var saved = 0.0;
      return (http.Request _) => json([
            {'id': 7, 'name': 'Laptop', 'target': 1000.0, 'saved': saved += 0, 'progress': saved / 1000}
          ]);
    })(),
    'POST /goals': (_) => json({}, 201),
    'POST /goals/7/contribute': (_) => json({}),
  }, (t, calls) async {
    await tab(t, 'Goals');
    expect(find.text('Laptop'), findsOneWidget);
    expect(find.text('₹0.00 of ₹1000.00'), findsOneWidget);

    await tapIcon(t, Icons.add);
    await fillAndSave(t, {'Name': 'Phone', 'Target amount': '500'});
    expect(bodyOf(last(calls, 'POST', '/goals')), {'name': 'Phone', 'target': 500.0});

    await t.tap(find.text('Laptop'));
    await settle(t);
    await fillAndSave(t, {'Amount': '250'});
    expect(bodyOf(last(calls, 'POST', '/goals/7/contribute')), {'amount': 250.0});
  });

  uiTest('goal delete calls the API', {
    'GET /goals': (_) => json([
          {'id': 7, 'name': 'Laptop', 'target': 1000.0, 'saved': 100.0, 'progress': 0.1}
        ]),
    'DELETE /goals/7': (_) => http.Response('', 204),
  }, (t, calls) async {
    await tab(t, 'Goals');
    await tapIcon(t, Icons.delete_outline);
    expect(calls.any((c) => c.method == 'DELETE' && c.url.path == '/goals/7'), isTrue);
  });

  uiTest('unreachable server shows retry and recovers', {
    'GET /dashboard': (() {
      var n = 0;
      return (http.Request _) => n++ == 0 ? throw http.ClientException('offline') : json(emptyDashboard);
    })(),
  }, (t, calls) async {
    // The first dashboard load (during app start) failed.
    expect(find.text('Could not reach the server'), findsOneWidget);
    await t.tap(find.text('Retry'));
    await settle(t);
    expect(find.text('Could not reach the server'), findsNothing);
    expect(find.text('Balance ₹1000.00'), findsOneWidget);
  });
}
