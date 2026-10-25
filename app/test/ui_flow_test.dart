// Hermetic UI tests: the real app talks to an in-memory stub of the API
// (package:http MockClient), so no backend is needed.
import 'dart:convert';

import 'package:budget_tracker/common.dart';
import 'package:budget_tracker/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'test_fonts.dart';

typedef Handler = http.Response Function(http.Request req);

http.Response json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

final now = DateTime.now();
final today = dateKey(now);
final thisMonth = monthKey(now);
final monthName = monthLabel(now);

final emptyDashboard = {
  'month': thisMonth,
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
  Future<void> Function(WidgetTester t, List<http.Request> calls) body, {
  Size size = const Size(500, 1000),
}) {
  testWidgets(name, (t) async {
    final calls = <http.Request>[];
    final all = <String, Handler>{
      'GET /dashboard': (_) => json(emptyDashboard),
      'GET /expenses': (_) => json([]),
      'GET /recurring': (_) => json([]),
      'GET /goals': (_) => json([]),
      ...routes,
    };
    await http.runWithClient(() async {
      t.view.devicePixelRatio = 1.0; // logical size == the size given
      t.view.physicalSize = size;
      addTearDown(t.view.reset);
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
  for (var i = 0; i < 8; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> tab(WidgetTester t, String name) async {
  await t.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(name)));
  await settle(t);
}

Future<void> tapFab(WidgetTester t) async {
  await t.tap(find.byType(FloatingActionButton));
  await settle(t);
}

/// Types into fields (by label) and presses a button (default Save).
Future<void> fillAndSubmit(WidgetTester t, Map<String, String> fields, {String submit = 'Save'}) async {
  for (final e in fields.entries) {
    await t.enterText(find.widgetWithText(TextField, e.key), e.value);
  }
  await t.tap(find.widgetWithText(FilledButton, submit));
  await settle(t);
}

Map<String, dynamic> bodyOf(http.Request r) => jsonDecode(r.body) as Map<String, dynamic>;
http.Request last(List<http.Request> calls, String method, String path) =>
    calls.lastWhere((c) => c.method == method && c.url.path == path);
bool called(List<http.Request> calls, String method, String path) =>
    calls.any((c) => c.method == method && c.url.path == path);

final _budgetDashboard = {
  ...emptyDashboard,
  'balance': 450.0,
  'low_balance': true,
  'low_balance_threshold': 500.0,
  'total_spent': 550.0,
  'categories': [
    {'category': 'food', 'spent': 150.0, 'cap': 100.0, 'over': true},
    {'category': 'transport', 'spent': 40.0, 'cap': 400.0, 'over': false},
    {'category': 'rent', 'spent': 400.0, 'cap': null, 'over': false},
  ],
  'trend': [
    {'date': today, 'total': 150.0},
  ],
};

void main() {
  setUpAll(loadAppFonts);

  group('Expenses', () {
    uiTest('add expense over budget shows the overspend alert', {
      'POST /expenses': (_) => json({
            'expense': {'id': 1, 'amount': 150.0, 'category': 'food', 'date': today, 'note': 'lunch'},
            'alert': {'category': 'food', 'over_by': 50.0},
            'balance': 850.0,
            'low_balance_threshold': 0.0,
            'low_balance': false,
          }, 201),
    }, (t, calls) async {
      await tab(t, 'Expenses');
      expect(find.text('No expenses in $monthName'), findsOneWidget);
      await tapFab(t);
      expect(find.text('Add expense'), findsOneWidget); // the page title; the FAB is gone
      await fillAndSubmit(t, {'Amount': '150', 'Category': 'Food', 'Note (optional)': 'lunch'});

      expect(find.textContaining('Over budget in food by ₹50'), findsOneWidget);
      final sent = bodyOf(last(calls, 'POST', '/expenses'));
      expect(sent, {'amount': 150.0, 'date': today, 'category': 'Food', 'note': 'lunch'});
    });

    uiTest('low balance after adding shows a warning with the safety line', {
      'POST /expenses': (_) => json({
            'expense': {'id': 1, 'amount': 400.0, 'category': 'rent', 'date': today, 'note': ''},
            'alert': null,
            'balance': 450.0,
            'low_balance_threshold': 500.0,
            'low_balance': true,
          }, 201),
    }, (t, calls) async {
      await tab(t, 'Expenses');
      await tapFab(t);
      await fillAndSubmit(t, {'Amount': '400', 'Category': 'Rent'});
      expect(find.text('Low balance: ₹450 left, below your ₹500 safety line'), findsOneWidget);
    });

    uiTest('a plain add confirms with the category and amount', {
      'POST /expenses': (_) => json({
            'expense': {'id': 1, 'amount': 90.5, 'category': 'tea', 'date': today, 'note': ''},
            'alert': null,
            'balance': 900.0,
            'low_balance_threshold': 0.0,
            'low_balance': false,
          }, 201),
    }, (t, calls) async {
      await tab(t, 'Expenses');
      await tapFab(t);
      await fillAndSubmit(t, {'Amount': '90.5', 'Category': 'tea'});
      expect(find.text('Added Tea ₹90.50'), findsOneWidget);
    });

    uiTest('category chips fill the category field and show which one is chosen', {}, (t, calls) async {
      await tab(t, 'Expenses');
      await tapFab(t);
      expect(t.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Transport')).selected, isFalse);
      await t.tap(find.widgetWithText(ChoiceChip, 'Transport'));
      await settle(t);
      expect(find.widgetWithText(TextField, 'Transport'), findsOneWidget);
      expect(t.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Transport')).selected, isTrue);
      expect(t.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Food')).selected, isFalse);
    });

    uiTest('the add form validates before calling the server', {}, (t, calls) async {
      await tab(t, 'Expenses');
      await tapFab(t);
      await fillAndSubmit(t, {'Amount': '0'});
      expect(find.text('Enter an amount above 0'), findsOneWidget);
      expect(find.text('Pick or type a category'), findsOneWidget);
      expect(called(calls, 'POST', '/expenses'), isFalse);
    });

    uiTest('a server rejection is shown readably and the form stays open', {
      'POST /expenses': (_) => json({
            'detail': [
              {'loc': ['body', 'date'], 'msg': 'Input should be a valid date'}
            ]
          }, 422),
    }, (t, calls) async {
      await tab(t, 'Expenses');
      await tapFab(t);
      await fillAndSubmit(t, {'Amount': '5', 'Category': 'Food'});
      expect(find.text('date: Input should be a valid date'), findsOneWidget);
      expect(find.text('Add expense'), findsOneWidget); // still on the form
    });

    uiTest('amounts sit at the right edge of their rows', {
      'GET /expenses': (_) => json([
            {'id': 3, 'amount': 150.0, 'date': today, 'category': 'food', 'note': '', 'recurring_id': null},
          ]),
    }, (t, calls) async {
      await tab(t, 'Expenses');
      // 500dp wide, 16dp padding: the amount's right edge is at 484.
      expect(t.getTopRight(find.text('₹150').last).dx, closeTo(484, 1.0));
    });

    uiTest('long-press deletes without swiping, after confirmation', {
      'GET /expenses': (_) => json([
            {'id': 3, 'amount': 150.0, 'date': today, 'category': 'food', 'note': 'lunch', 'recurring_id': null},
          ]),
      'DELETE /expenses/3': (_) => http.Response('', 204),
    }, (t, calls) async {
      await tab(t, 'Expenses');
      await t.longPress(find.text('Food'));
      await settle(t);
      expect(find.text('Delete Food ₹150?'), findsOneWidget);
      expect(called(calls, 'DELETE', '/expenses/3'), isFalse);

      await t.tap(find.widgetWithText(TextButton, 'Cancel'));
      await settle(t);
      expect(called(calls, 'DELETE', '/expenses/3'), isFalse);

      await t.longPress(find.text('Food'));
      await settle(t);
      await t.tap(find.widgetWithText(TextButton, 'Delete'));
      await settle(t);
      expect(called(calls, 'DELETE', '/expenses/3'), isTrue);
      expect(find.text('Deleted Food ₹150'), findsOneWidget); // with Undo
    });

    uiTest('rows expose a Delete action to screen readers', {
      'GET /expenses': (_) => json([
            {'id': 3, 'amount': 150.0, 'date': today, 'category': 'food', 'note': '', 'recurring_id': null},
          ]),
    }, (t, calls) async {
      final handle = t.ensureSemantics();
      await tab(t, 'Expenses');
      final node = t.getSemantics(find.text('Food'));
      expect(node.getSemanticsData().customSemanticsActionIds, isNotNull);
      expect(node.getSemanticsData().customSemanticsActionIds!.isNotEmpty, isTrue);
      handle.dispose();
    });

    uiTest('rows are grouped by day; swipe deletes and Undo re-adds', {
      'GET /expenses': (_) => json([
            {'id': 3, 'amount': 150.0, 'date': today, 'category': 'food', 'note': 'lunch', 'recurring_id': null},
            {'id': 4, 'amount': 499.0, 'date': today, 'category': 'netflix', 'note': '', 'recurring_id': 9},
          ]),
      'DELETE /expenses/3': (_) => http.Response('', 204),
      'POST /expenses': (_) => json({'expense': {'id': 10}}, 201),
    }, (t, calls) async {
      await tab(t, 'Expenses');
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('2 expenses · ₹649'), findsOneWidget);
      expect(find.text('Food'), findsOneWidget);
      expect(find.text('lunch'), findsOneWidget);
      expect(find.descendant(of: find.byType(ListView), matching: find.text('Recurring')), findsOneWidget);

      await t.drag(find.text('Food'), const Offset(-500, 0));
      await t.pumpAndSettle();
      expect(called(calls, 'DELETE', '/expenses/3'), isTrue);
      expect(find.text('Deleted Food ₹150'), findsOneWidget);

      await t.tap(find.text('Undo'));
      await settle(t);
      expect(bodyOf(last(calls, 'POST', '/expenses')),
          {'amount': 150.0, 'date': today, 'category': 'food', 'note': 'lunch'});
    });
  });

  group('Dashboard', () {
    uiTest('shows the state sentence, over-budget lines and uncapped spending', {
      'GET /dashboard': (_) => json(_budgetDashboard),
    }, (t, calls) async {
      expect(find.text('₹450 left, ₹50 below your safety line'), findsOneWidget);
      expect(find.text('Safety line ₹500'), findsOneWidget);
      expect(find.text('Balance ₹450'), findsOneWidget); // legend for the filled line
      expect(find.text('Spent in ${monthName.split(' ').first}: ₹550'), findsOneWidget);
      expect(find.text('₹150 of ₹100'), findsOneWidget);
      expect(find.text('₹50 over budget'), findsOneWidget);
      expect(find.text('₹40 of ₹400'), findsOneWidget);
      expect(find.text('No budget set'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    });

    uiTest('the dashboard offers Add expense without switching tabs', {}, (t, calls) async {
      await tapFab(t);
      expect(find.text('Add expense'), findsOneWidget); // the add page's title
      expect(find.widgetWithText(TextField, 'Amount'), findsOneWidget);
    });

    uiTest('above the safety line reads as fine, with a check icon', {
      'GET /dashboard': (_) => json({..._budgetDashboard, 'balance': 1500.0, 'low_balance': false}),
    }, (t, calls) async {
      expect(find.text('₹1,500 left, ₹1,000 above your safety line'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    });

    uiTest('without a safety line it offers to set one', {}, (t, calls) async {
      expect(find.text('₹1,000 left'), findsOneWidget);
      expect(find.text('Set a safety line to be warned when money runs low.'), findsOneWidget);
    });

    uiTest('balance settings sheet saves opening balance and safety line', {
      'GET /account': (_) => json({'opening_balance': 1000.0, 'low_balance_threshold': 500.0}),
      'PUT /account': (_) => json({}),
    }, (t, calls) async {
      await t.tap(find.byTooltip('Balance settings'));
      await settle(t);
      expect(find.widgetWithText(TextField, 'Opening balance'), findsOneWidget);
      await fillAndSubmit(t, {'Opening balance': '2000', 'Safety line': '750'});
      expect(bodyOf(last(calls, 'PUT', '/account')), {'opening_balance': 2000.0, 'low_balance_threshold': 750.0});
      expect(find.text('Balance settings'), findsNothing); // sheet closed
    });

    uiTest('balance settings reject non-numbers inline and stay open', {
      'GET /account': (_) => json({'opening_balance': 0.0, 'low_balance_threshold': 0.0}),
    }, (t, calls) async {
      await t.tap(find.byTooltip('Balance settings'));
      await settle(t);
      await fillAndSubmit(t, {'Opening balance': 'abc'});
      expect(find.text('Enter a number, for example 5000'), findsOneWidget);
      expect(find.text('Balance settings'), findsOneWidget);
      expect(called(calls, 'PUT', '/account'), isFalse);
    });

    uiTest('month arrows load the other month and keep the header in sync', {}, (t, calls) async {
      final next = DateTime(now.year, now.month + 1);
      await t.tap(find.byTooltip('Next month'));
      await settle(t);
      expect(find.text(monthLabel(next)), findsOneWidget);
      expect(calls.where((c) => c.url.path == '/dashboard').last.url.queryParameters['month'], monthKey(next));
      await t.tap(find.byTooltip('Previous month'));
      await settle(t);
      expect(find.text(monthName), findsOneWidget);
    });

    uiTest('unreachable server shows retry and recovers', {
      'GET /dashboard': (() {
        var n = 0;
        return (http.Request _) => n++ == 0 ? throw http.ClientException('offline') : json(emptyDashboard);
      })(),
    }, (t, calls) async {
      expect(find.text('Could not reach the server'), findsOneWidget);
      await t.tap(find.text('Retry'));
      await settle(t);
      expect(find.text('Could not reach the server'), findsNothing);
      expect(find.text('₹1,000 left'), findsOneWidget);
    });
  });

  group('Budgets', () {
    uiTest('lists caps with spent and left, add sends month and cap', {
      'GET /dashboard': (_) => json(_budgetDashboard),
      'PUT /budgets': (_) => json({}),
    }, (t, calls) async {
      await tab(t, 'Budgets');
      expect(find.text('Food'), findsOneWidget);
      expect(find.text('₹150 spent, ₹50 over'), findsOneWidget);
      expect(find.text('₹40 spent, ₹360 left'), findsOneWidget);
      expect(find.text('Rent'), findsNothing); // no cap, so not a budget

      await tapFab(t);
      await fillAndSubmit(t, {'Category': 'Travel', 'Monthly cap': '250.5'});
      expect(bodyOf(last(calls, 'PUT', '/budgets')), {'category': 'Travel', 'month': thisMonth, 'cap': 250.5});
    });

    uiTest('editing keeps the category fixed and prefilled', {
      'GET /dashboard': (_) => json(_budgetDashboard),
      'PUT /budgets': (_) => json({}),
    }, (t, calls) async {
      await tab(t, 'Budgets');
      await t.tap(find.text('Transport'));
      await settle(t);
      expect(find.text('Change budget'), findsOneWidget);
      final category = t.widget<TextField>(find.widgetWithText(TextField, 'Category'));
      expect(category.readOnly, isTrue);
      await fillAndSubmit(t, {'Monthly cap': '500'});
      expect(bodyOf(last(calls, 'PUT', '/budgets')), {'category': 'Transport', 'month': thisMonth, 'cap': 500.0});
    });

    uiTest('blank category is rejected inline', {
      'GET /dashboard': (_) => json(_budgetDashboard),
    }, (t, calls) async {
      await tab(t, 'Budgets');
      await tapFab(t);
      await fillAndSubmit(t, {'Monthly cap': '50'});
      expect(find.text('Give the category a name, for example Food'), findsOneWidget);
      expect(called(calls, 'PUT', '/budgets'), isFalse);
    });
  });

  group('Recurring', () {
    uiTest('apply reports created, then already up to date', {
      'GET /recurring': (_) => json([
            {'id': 1, 'amount': 499.0, 'category': 'music', 'note': 'plan', 'day_of_month': 5}
          ]),
      'POST /recurring/apply': (() {
        var n = 0;
        return (http.Request _) => json({'month': thisMonth, 'created': n++ == 0 ? 1 : 0});
      })(),
    }, (t, calls) async {
      await tab(t, 'Recurring');
      expect(find.text('Music'), findsOneWidget);
      expect(find.text('Day 5 of every month · plan'), findsOneWidget);

      await t.tap(find.text('Apply to $monthName'));
      await settle(t);
      expect(find.text('Added 1 expense to $monthName'), findsOneWidget);
      expect(last(calls, 'POST', '/recurring/apply').url.queryParameters['month'], thisMonth);

      await t.pump(const Duration(seconds: 5));
      await t.tap(find.text('Apply to $monthName'));
      await settle(t);
      expect(find.text('Nothing to add: $monthName is already up to date.'), findsOneWidget);
    });

    uiTest('add validates the day inline, then sends the template', {
      'POST /recurring': (_) => json({}, 201),
    }, (t, calls) async {
      await tab(t, 'Recurring');
      expect(find.text('No recurring expenses'), findsOneWidget);
      await tapFab(t);
      await fillAndSubmit(t, {'Amount': '10', 'Category': 'Netflix', 'Day of month (1-28)': '31'});
      expect(find.text('Pick a day from 1 to 28'), findsOneWidget);
      expect(called(calls, 'POST', '/recurring'), isFalse);

      await fillAndSubmit(t, {'Day of month (1-28)': '5'});
      expect(bodyOf(last(calls, 'POST', '/recurring')),
          {'amount': 10.0, 'category': 'Netflix', 'note': '', 'day_of_month': 5});
    });

    uiTest('deleting a template can be undone', {
      'GET /recurring': (_) => json([
            {'id': 1, 'amount': 499.0, 'category': 'music', 'note': 'plan', 'day_of_month': 5}
          ]),
      'DELETE /recurring/1': (_) => http.Response('', 204),
      'POST /recurring': (_) => json({}, 201),
    }, (t, calls) async {
      await tab(t, 'Recurring');
      await t.tap(find.byTooltip('Delete Music template'));
      await settle(t);
      expect(called(calls, 'DELETE', '/recurring/1'), isTrue);
      await t.tap(find.text('Undo'));
      await settle(t);
      expect(bodyOf(last(calls, 'POST', '/recurring')),
          {'amount': 499.0, 'category': 'music', 'note': 'plan', 'day_of_month': 5});
    });
  });

  group('Goals', () {
    final goal = {'id': 7, 'name': 'Laptop', 'target': 1000.0, 'saved': 250.0, 'progress': 0.25};

    uiTest('lists progress; add and contribute send the right bodies', {
      'GET /goals': (_) => json([goal]),
      'POST /goals': (_) => json({}, 201),
      'POST /goals/7/contribute': (_) => json({}),
    }, (t, calls) async {
      await tab(t, 'Goals');
      expect(find.text('Laptop'), findsOneWidget);
      expect(find.text('₹250 of ₹1,000 · 25% · ₹750 to go'), findsOneWidget);

      await tapFab(t);
      await fillAndSubmit(t, {'Name': 'Phone', 'Target amount': '500'});
      expect(bodyOf(last(calls, 'POST', '/goals')), {'name': 'Phone', 'target': 500.0});

      await t.tap(find.text('Laptop'));
      await settle(t);
      expect(find.text('Add to Laptop'), findsOneWidget);
      await fillAndSubmit(t, {'Amount': '100'});
      expect(bodyOf(last(calls, 'POST', '/goals/7/contribute')), {'amount': 100.0});
      expect(find.text('Added ₹100 to Laptop'), findsOneWidget);
    });

    uiTest('a reached goal says so', {
      'GET /goals': (_) => json([
            {...goal, 'saved': 1000.0, 'progress': 1.0}
          ]),
    }, (t, calls) async {
      await tab(t, 'Goals');
      expect(find.text('Goal reached: ₹1,000 of ₹1,000'), findsOneWidget);
    });

    uiTest('delete goal asks first, then calls the API', {
      'GET /goals': (_) => json([goal]),
      'DELETE /goals/7': (_) => http.Response('', 204),
    }, (t, calls) async {
      await tab(t, 'Goals');
      await t.tap(find.byTooltip('Options for Laptop'));
      await settle(t);
      await t.tap(find.text('Delete goal'));
      await settle(t);
      expect(find.text('Delete Laptop?'), findsOneWidget);
      expect(called(calls, 'DELETE', '/goals/7'), isFalse); // not yet

      await t.tap(find.widgetWithText(TextButton, 'Cancel'));
      await settle(t);
      expect(called(calls, 'DELETE', '/goals/7'), isFalse);

      await t.tap(find.byTooltip('Options for Laptop'));
      await settle(t);
      await t.tap(find.text('Delete goal'));
      await settle(t);
      await t.tap(find.widgetWithText(TextButton, 'Delete goal'));
      await settle(t);
      expect(called(calls, 'DELETE', '/goals/7'), isTrue);
    });

    uiTest('invalid contribution is rejected inline', {
      'GET /goals': (_) => json([goal]),
    }, (t, calls) async {
      await tab(t, 'Goals');
      await t.tap(find.text('Laptop'));
      await settle(t);
      await fillAndSubmit(t, {'Amount': '0'});
      expect(find.text('Enter an amount above 0'), findsOneWidget);
      expect(called(calls, 'POST', '/goals/7/contribute'), isFalse);
    });
  });

  group('Shell', () {
    uiTest('empty states explain the screen', {}, (t, calls) async {
      await tab(t, 'Expenses');
      expect(find.text('No expenses in $monthName'), findsOneWidget);
      await tab(t, 'Budgets');
      expect(find.text('No budgets for $monthName'), findsOneWidget);
      await tab(t, 'Recurring');
      expect(find.text('No recurring expenses'), findsOneWidget);
      await tab(t, 'Goals');
      expect(find.text('No savings goals yet'), findsOneWidget);
    });

    uiTest('system Back from another tab returns to the dashboard', {}, (t, calls) async {
      await tab(t, 'Goals');
      expect(find.text('No savings goals yet'), findsOneWidget);
      await t.binding.handlePopRoute();
      await settle(t);
      expect(find.text('₹1,000 left'), findsOneWidget);
    });

    uiTest('large system text does not overflow or clip any screen', {
      'GET /dashboard': (_) => json(_budgetDashboard),
      'GET /expenses': (_) => json([
            {'id': 3, 'amount': 150000.0, 'date': today, 'category': 'eating out with the whole team', 'note': 'a very long note about a team dinner that keeps going', 'recurring_id': null},
            {'id': 4, 'amount': 499.0, 'date': today, 'category': 'netflix', 'note': '', 'recurring_id': 9},
          ]),
      'GET /recurring': (_) => json([
            {'id': 1, 'amount': 12345678.0, 'category': 'subscriptions and memberships', 'note': 'plan with a long name', 'day_of_month': 5}
          ]),
      'GET /goals': (_) => json([
            {'id': 7, 'name': 'A laptop good enough for the whole of college', 'target': 100000.0, 'saved': 25000.0, 'progress': 0.25}
          ]),
    }, (t, calls) async {
      // Layout overflows are reported as test failures by the framework.
      t.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      await settle(t);
      for (final name in ['Dashboard', 'Expenses', 'Budgets', 'Recurring', 'Goals']) {
        await tab(t, name);
      }
    }, size: const Size(360, 740));

    uiTest('wide windows get a navigation rail instead of the bottom bar', {}, (t, calls) async {
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.text('₹1,000 left'), findsOneWidget);
    }, size: const Size(1000, 800));
  });
}
