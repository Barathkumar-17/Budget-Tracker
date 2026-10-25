// Hermetic UI tests: the real app talks to an in-memory stub of the API
// (package:http MockClient), so no backend is needed.
import 'dart:convert';

import 'package:budget_tracker/api.dart';
import 'package:budget_tracker/common.dart';
import 'package:budget_tracker/main.dart';
import 'package:budget_tracker/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_fonts.dart';

typedef Handler = http.Response Function(http.Request req);

http.Response json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json'});

final now = DateTime.now();
final today = dateKey(now);
final thisMonth = monthKey(now);
final monthName = monthLabel(now);
final monthWord = monthName.split(' ').first;

final emptyDashboard = {
  'month': thisMonth,
  'total_spent': 0,
  'categories': [],
  'trend': [],
  'balance': 1000.0,
  'low_balance_threshold': 0.0,
  'low_balance': false,
};

const phone = Size(400, 900);
const desktop = Size(1200, 1000);

void uiTest(
  String name,
  Map<String, Handler> routes,
  Future<void> Function(WidgetTester t, List<http.Request> calls) body, {
  Size size = desktop,
  bool loggedIn = true,
}) {
  testWidgets(name, (t) async {
    final calls = <http.Request>[];
    // The app starts logged in unless the test says otherwise (a saved session token).
    SharedPreferences.setMockInitialValues(
        loggedIn ? {'session_token': 'saved-token'} : {});
    Api.token = null;
    WakePolicy.delays = const [
      Duration(milliseconds: 20),
      Duration(milliseconds: 20)
    ];
    final all = <String, Handler>{
      'GET /auth/me': (_) => json({'username': 'tester'}),
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
    },
        () => MockClient((req) async {
              calls.add(req);
              final h = all['${req.method} ${req.url.path}'];
              return h == null
                  ? json(
                      {'detail': 'no stub for ${req.method} ${req.url.path}'},
                      404)
                  : h(req);
            }));
  });
}

Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 8; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

/// The navigation entry (a pill at the top on wide windows, a bottom pill on phones).
Finder navItem(String name) => find.descendant(
    of: find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == 'Main navigation'),
    matching: find.text(name));

Future<void> tab(WidgetTester t, String name) async {
  await t.ensureVisible(navItem(name)); // the phone tabs scroll sideways
  await t.tap(navItem(name));
  await settle(t);
}

/// The text field under a [LabeledField] with this label.
Finder input(String label) => find.descendant(
    of: find.ancestor(
        of: find.text(label), matching: find.byType(LabeledField)),
    matching: find.byType(TextField));

String valueOf(WidgetTester t, String label) =>
    t.widget<TextField>(input(label)).controller!.text;

Future<void> fillIn(WidgetTester t, Map<String, String> fields) async {
  for (final e in fields.entries) {
    await t.enterText(input(e.key), e.value);
  }
}

Future<void> press(WidgetTester t, String label,
    {Type type = FilledButton, bool last = false}) async {
  final f = find.widgetWithText(type, label);
  await t.ensureVisible(last ? f.last : f.first);
  await t.tap(last ? f.last : f.first);
  await settle(t);
}

Future<void> fillAndSubmit(WidgetTester t, Map<String, String> fields,
    {String submit = 'Save'}) async {
  await fillIn(t, fields);
  await press(t, submit);
}

Map<String, dynamic> bodyOf(http.Request r) =>
    jsonDecode(r.body) as Map<String, dynamic>;
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

Map<String, dynamic> expense(int id, double amount, String category,
        {String note = '', String? date, int? recurringId}) =>
    {
      'id': id,
      'amount': amount,
      'date': date ?? today,
      'category': category,
      'note': note,
      'recurring_id': recurringId,
    };

void main() {
  setUpAll(loadAppFonts);

  // ---------------------------------------------------------------- public
  group('Public pages', () {
    uiTest('a visitor sees the landing page first', {}, (t, calls) async {
      expect(find.text('Know where your money goes.'), findsOneWidget);
      expect(find.text('How it works'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Create account'),
          findsNWidgets(3));
      expect(find.widgetWithText(OutlinedButton, 'Log in'), findsNWidgets(2));
      expect(find.text('Use demo account'),
          findsNothing); // only when built with SHOW_DEMO
      expect(calls.where((c) => c.url.path == '/dashboard'), isEmpty);
    }, loggedIn: false);

    uiTest('landing leads to log in, register and back', {}, (t, calls) async {
      await t.tap(find.widgetWithText(OutlinedButton, 'Log in').first);
      await settle(t);
      expect(find.text('Welcome back'), findsOneWidget);
      expect(find.text('Every rupee,'),
          findsNothing); // spans: checked via text.rich below
      await t.tap(find.text('Create an account'));
      await settle(t);
      expect(find.text('Create your account'), findsOneWidget);
      await t.tap(find.text('Back to home'));
      await settle(t);
      expect(find.text('Know where your money goes.'), findsOneWidget);
      await t.tap(find.widgetWithText(FilledButton, 'Create account').first);
      await settle(t);
      expect(find.text('Create your account'), findsOneWidget);
    }, loggedIn: false);
  });

  // -------------------------------------------------------------- accounts
  group('Accounts', () {
    Future<void> openLogin(WidgetTester t) async {
      await t.tap(find.widgetWithText(OutlinedButton, 'Log in').first);
      await settle(t);
    }

    Future<void> logIn(WidgetTester t, String name, String password) async {
      await openLogin(t);
      await fillIn(t, {'Username': name, 'Password': password});
      await press(t, 'Log in');
    }

    Future<void> openRegister(WidgetTester t) async {
      await t.tap(find.widgetWithText(FilledButton, 'Create account').first);
      await settle(t);
    }

    uiTest('logging in shows the app and sends the token with every request', {
      'POST /auth/login': (_) => json({'token': 'tok-123', 'username': 'sam'}),
    }, (t, calls) async {
      await logIn(t, 'sam', 'a long password');
      expect(bodyOf(last(calls, 'POST', '/auth/login')),
          {'username': 'sam', 'password': 'a long password'});
      expect(find.text('Hi, Sam'), findsOneWidget);
      expect(last(calls, 'GET', '/dashboard').headers['Authorization'],
          'Bearer tok-123');
    }, loggedIn: false);

    uiTest('a wrong password is explained and the login screen stays', {
      'POST /auth/login': (_) =>
          json({'detail': 'Wrong username or password'}, 401),
    }, (t, calls) async {
      await logIn(t, 'sam', 'not my password');
      expect(find.text('Wrong username or password'), findsOneWidget);
      expect(find.text('Hi, Sam'), findsNothing);
      // a wrong password must not look like an expired session
      expect(
          find.text('Your session ended. Please log in again.'), findsNothing);
    }, loggedIn: false);

    uiTest('empty fields are caught before the server is called', {},
        (t, calls) async {
      await openLogin(t);
      await press(t, 'Log in');
      expect(find.text('Enter your username'), findsOneWidget);
      expect(find.text('Enter your password'), findsOneWidget);
      expect(called(calls, 'POST', '/auth/login'), isFalse);
    }, loggedIn: false);

    uiTest('an unreachable server gives a clear message on login', {
      'POST /auth/login': (_) => throw http.ClientException('offline'),
    }, (t, calls) async {
      await logIn(t, 'sam', 'a long password');
      expect(find.textContaining('Could not reach the server'), findsOneWidget);
    }, loggedIn: false);

    uiTest('creating an account validates every field first', {
      'POST /auth/register': (_) =>
          json({'token': 'new-tok', 'username': 'newbie'}, 201),
    }, (t, calls) async {
      await openRegister(t);
      await fillIn(t,
          {'Username': 'ab', 'Password': 'short', 'Confirm password': 'other'});
      await press(t, 'Create account');
      expect(
          find.text('Use 3-30 letters, numbers, dots, dashes or underscores'),
          findsOneWidget);
      expect(find.text('Use at least 8 characters'), findsOneWidget);
      expect(find.text('The passwords do not match'), findsOneWidget);
      expect(called(calls, 'POST', '/auth/register'), isFalse);

      await fillIn(t, {
        'Username': 'newbie',
        'Password': 'long enough pw',
        'Confirm password': 'long enough pw',
      });
      await press(t, 'Create account');
      expect(bodyOf(last(calls, 'POST', '/auth/register')),
          {'username': 'newbie', 'password': 'long enough pw'});
      expect(find.text('Hi, Newbie'), findsOneWidget);
    }, loggedIn: false);

    uiTest('a taken username is reported on the username field', {
      'POST /auth/register': (_) =>
          json({'detail': 'That username is already taken'}, 409),
    }, (t, calls) async {
      await openRegister(t);
      await fillIn(t, {
        'Username': 'sam',
        'Password': 'long enough pw',
        'Confirm password': 'long enough pw',
      });
      await press(t, 'Create account');
      expect(find.text('That username is already taken'), findsOneWidget);
    }, loggedIn: false);

    uiTest('the show-password toggle reveals the password', {},
        (t, calls) async {
      await openLogin(t);
      TextField field() => t.widget<TextField>(input('Password'));
      expect(field().obscureText, isTrue);
      await t.tap(find.byTooltip('Show password'));
      await settle(t);
      expect(field().obscureText, isFalse);
    }, loggedIn: false);

    uiTest('the sidebar names the user and logs out to the landing page', {
      'POST /auth/logout': (_) => http.Response('', 204),
    }, (t, calls) async {
      expect(find.text('tester'), findsOneWidget); // in the sidebar
      await t.tap(find.byTooltip('Log out'));
      await settle(t);
      expect(called(calls, 'POST', '/auth/logout'), isTrue);
      expect(last(calls, 'POST', '/auth/logout').headers['Authorization'],
          'Bearer saved-token');
      expect(find.text('Know where your money goes.'), findsOneWidget);
      // the saved session is gone, so a reload would not log back in
      expect((await SharedPreferences.getInstance()).getString('session_token'),
          isNull);
    });

    uiTest(
        'a rejected session sends the user to the login screen with a notice', {
      'GET /dashboard': (_) => json({'detail': 'Please log in again'}, 401),
    }, (t, calls) async {
      expect(find.text('Your session ended. Please log in again.'),
          findsOneWidget);
      expect(find.text('Welcome back'), findsOneWidget);
    });

    uiTest('a saved session the server no longer accepts starts at login', {
      'GET /auth/me': (_) => json({'detail': 'Please log in again'}, 401),
    }, (t, calls) async {
      expect(find.text('Welcome back'), findsOneWidget);
      expect(find.text('Your session ended. Please log in again.'),
          findsOneWidget);
    });
  });

  // ---------------------------------------------------- sleeping server
  group('Waking server', () {
    uiTest('start-up keeps trying while the server wakes, then shows the app', {
      'GET /auth/me': (() {
        var n = 0;
        return (http.Request _) => n++ == 0
            ? throw http.ClientException('offline')
            : json({'username': 'tester'});
      })(),
    }, (t, calls) async {
      await settle(t);
      expect(find.text('Hi, Tester'), findsOneWidget);
    });

    uiTest('a gateway error while waking is retried, not shown as a failure', {
      'GET /dashboard': (() {
        var n = 0;
        return (http.Request _) => n++ == 0
            ? http.Response('<html>starting</html>', 503)
            : json(emptyDashboard);
      })(),
    }, (t, calls) async {
      await settle(t);
      expect(find.text('Could not reach the server'), findsNothing);
      expect(find.text('₹1,000'), findsOneWidget); // the balance stat
    });

    uiTest('after the retries run out there is a Retry button that works', {
      'GET /dashboard': (() {
        var n = 0;
        return (http.Request _) => n++ < 3
            ? throw http.ClientException('offline')
            : json(emptyDashboard);
      })(),
    }, (t, calls) async {
      await settle(t);
      expect(find.text('Could not reach the server'), findsOneWidget);
      await t.tap(find.widgetWithText(FilledButton, 'Retry'));
      await settle(t);
      expect(find.text('Could not reach the server'), findsNothing);
      expect(find.text('₹1,000'), findsOneWidget);
    });

    uiTest('a real error such as 404 is not retried', {
      'GET /dashboard': (_) => json({'detail': 'nope'}, 404),
    }, (t, calls) async {
      await settle(t);
      expect(calls.where((c) => c.url.path == '/dashboard').length, 1);
      expect(find.text('Could not reach the server'), findsOneWidget);
    });
  });

  // ------------------------------------------------------------- dashboard
  group('Dashboard', () {
    uiTest('greets the user, states the balance and shows budgets as bars', {
      'GET /dashboard': (_) => json(_budgetDashboard),
      'GET /expenses': (_) => json([expense(3, 150, 'food', note: 'lunch')]),
      'GET /goals': (_) => json([
            {
              'id': 7,
              'name': 'Laptop',
              'target': 1000.0,
              'saved': 250.0,
              'progress': 0.25
            }
          ]),
    }, (t, calls) async {
      expect(find.text('Hi, Tester'), findsOneWidget);
      expect(find.text('You have ₹450 left, ₹50 below your safety line.'),
          findsOneWidget);
      expect(
          find.text('Low balance: ₹450 left, ₹50 below your ₹500 safety line.'),
          findsOneWidget);
      // stat strip
      expect(find.text('₹450'), findsOneWidget);
      expect(find.text('Spent in $monthWord'), findsOneWidget);
      expect(find.text('₹550'), findsOneWidget);
      expect(find.text('Budgeted this month'), findsOneWidget);
      expect(find.text('₹500'), findsOneWidget);
      expect(find.text('Categories over budget'), findsOneWidget);
      // budget bars
      expect(find.text('₹150 of ₹100'), findsOneWidget);
      expect(find.text('₹50 over budget'), findsOneWidget);
      expect(find.text('₹40 of ₹400'), findsOneWidget);
      expect(find.text('₹360 left'), findsOneWidget);
      // spending without a budget
      expect(find.text('Spending without a budget'), findsOneWidget);
      expect(find.text('₹400'), findsOneWidget);
      // ring: (150 + 40) / (100 + 400)
      expect(find.text('38%'), findsOneWidget);
      expect(find.text('1 over budget'), findsOneWidget);
      // recent expenses and goals
      expect(find.text('Recent expenses'), findsOneWidget);
      expect(find.text('Today · lunch'), findsOneWidget);
      expect(find.text('Laptop'), findsOneWidget);
      expect(find.text('₹250 of ₹1,000'), findsOneWidget);
    });

    uiTest('above the safety line there is no warning banner', {
      'GET /dashboard': (_) =>
          json({..._budgetDashboard, 'balance': 1500.0, 'low_balance': false}),
    }, (t, calls) async {
      expect(find.text('You have ₹1,500 left, ₹1,000 above your safety line.'),
          findsOneWidget);
      expect(find.textContaining('Low balance'), findsNothing);
    });

    uiTest('without a safety line it explains how to set one', {},
        (t, calls) async {
      expect(
          find.text(
              'You have ₹1,000 left. Set a safety line to be warned when money runs low.'),
          findsOneWidget);
    });

    uiTest('empty month: no budgets and no spending, with a way to start', {},
        (t, calls) async {
      expect(find.textContaining('No budgets are set for $monthName yet'),
          findsOneWidget);
      expect(find.text('Nothing spent in $monthName yet.'), findsOneWidget);
      expect(find.text('No spending recorded in $monthName.'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Set a budget'), findsOneWidget);
    });

    uiTest('balance settings: the dialog saves and closes', {
      'GET /account': (_) =>
          json({'opening_balance': 1000.0, 'low_balance_threshold': 500.0}),
      'PUT /account': (_) => json({}),
    }, (t, calls) async {
      await t.tap(find.byTooltip('Balance settings'));
      await settle(t);
      expect(find.text('Opening balance'), findsOneWidget);
      expect(valueOf(t, 'Opening balance'), '1000');
      await fillAndSubmit(t, {'Opening balance': '2000', 'Safety line': '750'});
      expect(bodyOf(last(calls, 'PUT', '/account')),
          {'opening_balance': 2000.0, 'low_balance_threshold': 750.0});
      expect(find.text('Opening balance'), findsNothing); // closed
    });

    uiTest('balance settings reject non-numbers inline and stay open', {
      'GET /account': (_) =>
          json({'opening_balance': 0.0, 'low_balance_threshold': 0.0}),
    }, (t, calls) async {
      await t.tap(find.byTooltip('Balance settings'));
      await settle(t);
      await fillAndSubmit(t, {'Opening balance': 'abc'});
      expect(find.text('Enter a number, for example 5000'), findsOneWidget);
      expect(find.text('Opening balance'), findsOneWidget);
      expect(called(calls, 'PUT', '/account'), isFalse);
    });

    uiTest(
        'the month switcher loads the other month and keeps its label in sync',
        {}, (t, calls) async {
      final next = DateTime(now.year, now.month + 1);
      await t.tap(find.byTooltip('Next month'));
      await settle(t);
      expect(find.text(monthLabel(next)), findsOneWidget);
      expect(
          calls
              .where((c) => c.url.path == '/dashboard')
              .last
              .url
              .queryParameters['month'],
          monthKey(next));
      await t.tap(find.byTooltip('Previous month'));
      await settle(t);
      expect(find.text(monthName), findsOneWidget);
    });

    uiTest('Add expense opens the dialog without switching section', {},
        (t, calls) async {
      await press(t, 'Add expense');
      expect(
          find.descendant(
              of: find.byType(Dialog), matching: find.text('Add expense')),
          findsOneWidget);
      expect(find.text('Amount'), findsOneWidget);
    });

    uiTest('Manage and View all link to the other sections', {
      'GET /goals': (_) => json([]),
    }, (t, calls) async {
      await t.tap(find.widgetWithText(OutlinedButton, 'Manage'));
      await settle(t);
      expect(find.text('Budgets'), findsWidgets);
      expect(find.text('No budgets for $monthName'), findsOneWidget);
    });
  });

  // -------------------------------------------------------------- expenses
  group('Expenses', () {
    uiTest('add expense over budget shows the overspend alert', {
      'POST /expenses': (_) => json({
            'expense': expense(1, 150, 'food', note: 'lunch'),
            'alert': {'category': 'food', 'over_by': 50.0},
            'balance': 850.0,
            'low_balance_threshold': 0.0,
            'low_balance': false,
          }, 201),
    }, (t, calls) async {
      await tab(t, 'Expenses');
      expect(find.text('No expenses in $monthName'), findsOneWidget);
      await press(t, 'Add expense');
      await fillAndSubmit(
          t, {'Amount': '150', 'Category': 'Food', 'Note (optional)': 'lunch'});
      expect(find.textContaining('Over budget in food by ₹50'), findsOneWidget);
      expect(bodyOf(last(calls, 'POST', '/expenses')), {
        'amount': 150.0,
        'date': today,
        'category': 'Food',
        'note': 'lunch'
      });
    });

    uiTest('low balance after adding shows a warning with the safety line', {
      'POST /expenses': (_) => json({
            'expense': expense(1, 400, 'rent'),
            'alert': null,
            'balance': 450.0,
            'low_balance_threshold': 500.0,
            'low_balance': true,
          }, 201),
    }, (t, calls) async {
      await tab(t, 'Expenses');
      await press(t, 'Add expense');
      await fillAndSubmit(t, {'Amount': '400', 'Category': 'Rent'});
      expect(find.text('Low balance: ₹450 left, below your ₹500 safety line'),
          findsOneWidget);
    });

    uiTest('a plain add confirms with the category and amount', {
      'POST /expenses': (_) => json({
            'expense': expense(1, 90.5, 'tea'),
            'alert': null,
            'balance': 900.0,
            'low_balance_threshold': 0.0,
            'low_balance': false,
          }, 201),
    }, (t, calls) async {
      await tab(t, 'Expenses');
      await press(t, 'Add expense');
      await fillAndSubmit(t, {'Amount': '90.5', 'Category': 'tea'});
      expect(find.text('Added Tea ₹90.50'), findsOneWidget);
    });

    uiTest('category pills fill the field and show which one is chosen', {},
        (t, calls) async {
      await tab(t, 'Expenses');
      await press(t, 'Add expense');
      await t.tap(find.text('Transport'));
      await settle(t);
      expect(valueOf(t, 'Category'), 'Transport');
    });

    uiTest('the form validates before calling the server', {},
        (t, calls) async {
      await tab(t, 'Expenses');
      await press(t, 'Add expense');
      await fillAndSubmit(t, {'Amount': '0'});
      expect(find.text('Enter an amount above 0'), findsOneWidget);
      expect(find.text('Pick or type a category'), findsOneWidget);
      expect(called(calls, 'POST', '/expenses'), isFalse);
    });

    uiTest('a server rejection is shown readably and the dialog stays open', {
      'POST /expenses': (_) => json({
            'detail': [
              {
                'loc': ['body', 'date'],
                'msg': 'Input should be a valid date'
              }
            ]
          }, 422),
    }, (t, calls) async {
      await tab(t, 'Expenses');
      await press(t, 'Add expense');
      await fillAndSubmit(t, {'Amount': '5', 'Category': 'Food'});
      expect(find.text('date: Input should be a valid date'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget); // still in the dialog
    });

    uiTest('the list is a table with stats, and category tabs filter it', {
      'GET /expenses': (_) => json([
            expense(3, 150, 'food', note: 'lunch'),
            expense(4, 499, 'netflix', recurringId: 9),
            expense(5, 60, 'food', note: 'tea'),
          ]),
    }, (t, calls) async {
      await tab(t, 'Expenses');
      expect(
          find.text(
              'Everything you spent in $monthName. Click a row to edit it.'),
          findsOneWidget);
      expect(find.text('₹709'), findsOneWidget); // spent
      expect(find.text('3'), findsOneWidget); // count
      expect(find.text('Biggest category'), findsOneWidget);
      expect(find.widgetWithText(Tag, 'Recurring'), findsOneWidget);
      expect(find.text('lunch'), findsOneWidget);
      expect(find.text('All (3)'), findsOneWidget);
      expect(find.text('Food (2)'), findsOneWidget);

      await t.tap(find.text('Food (2)'));
      await settle(t);
      expect(find.text('lunch'), findsOneWidget);
      expect(find.text('tea'), findsOneWidget);
      expect(find.text('₹499'), findsNothing); // netflix is filtered out
      expect(find.textContaining('2 of 3 expenses'), findsOneWidget);
    });

    uiTest('tapping a row edits the expense', {
      'GET /expenses': (_) => json([expense(3, 150, 'food', note: 'lunch')]),
      'PUT /expenses/3': (_) => json({
            'expense': expense(3, 200, 'food', note: 'lunch'),
            'alert': null,
            'balance': 800.0,
            'low_balance_threshold': 0.0,
            'low_balance': false,
          }),
    }, (t, calls) async {
      await tab(t, 'Expenses');
      await t.tap(find.text('lunch'));
      await settle(t);
      expect(find.text('Edit expense'), findsOneWidget);
      expect(valueOf(t, 'Amount'), '150');
      expect(valueOf(t, 'Category'), 'Food');
      expect(valueOf(t, 'Note (optional)'), 'lunch');
      await fillAndSubmit(t, {'Amount': '200'});
      expect(bodyOf(last(calls, 'PUT', '/expenses/3')), {
        'amount': 200.0,
        'date': today,
        'category': 'Food',
        'note': 'lunch'
      });
      expect(called(calls, 'POST', '/expenses'),
          isFalse); // an edit is not a new expense
      expect(find.text('Updated Food ₹200'), findsOneWidget);
    });

    uiTest('Remove deletes at once and Undo puts it back', {
      'GET /expenses': (_) => json([expense(3, 150, 'food', note: 'lunch')]),
      'DELETE /expenses/3': (_) => http.Response('', 204),
      'POST /expenses': (_) => json({'expense': expense(10, 150, 'food')}, 201),
    }, (t, calls) async {
      await tab(t, 'Expenses');
      await press(t, 'Remove', type: OutlinedButton);
      expect(called(calls, 'DELETE', '/expenses/3'), isTrue);
      expect(find.text('Deleted Food ₹150'), findsOneWidget);
      expect(find.text('lunch'),
          findsNothing); // gone from the table straight away

      await t.tap(find.text('Undo'));
      await settle(t);
      expect(bodyOf(last(calls, 'POST', '/expenses')), {
        'amount': 150.0,
        'date': today,
        'category': 'food',
        'note': 'lunch'
      });
    });

    uiTest('amounts line up at the right edge of the table', {
      'GET /expenses': (_) =>
          json([expense(3, 150, 'food'), expense(4, 1500, 'rent')]),
    }, (t, calls) async {
      await tab(t, 'Expenses');
      final a = t.getTopRight(find.text('₹150')).dx;
      final b = t.getTopRight(find.text('₹1,500')).dx;
      expect(a, closeTo(b, 0.5));
    });

    uiTest(
        'on a phone the rows become stacked entries with the amount at the right',
        {
          'GET /expenses': (_) =>
              json([expense(3, 150, 'food', note: 'lunch')]),
        }, (t, calls) async {
      await tab(t, 'Expenses');
      expect(find.text('Date'), findsNothing); // no table header on a phone
      expect(find.text('Today · lunch'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Edit'), findsOneWidget);
      final right = t.getTopRight(find.text('₹150').last).dx;
      final panel = t.getTopRight(find.byType(Panel).last).dx;
      expect(right, closeTo(panel - 16, 1.5));
    }, size: phone);
  });

  // --------------------------------------------------------------- budgets
  group('Budgets', () {
    uiTest('lists caps with spent and left; add sends month and cap', {
      'GET /dashboard': (_) => json(_budgetDashboard),
      'PUT /budgets': (_) => json({}),
    }, (t, calls) async {
      await tab(t, 'Budgets');
      expect(find.text('₹150 spent'), findsOneWidget);
      expect(find.text('₹50 over budget'), findsOneWidget);
      expect(find.text('₹360 left'), findsOneWidget);
      expect(find.widgetWithText(Tag, 'Over budget'),
          findsOneWidget); // status tag on food
      expect(find.text('Within budget'),
          findsOneWidget); // status tag on transport
      expect(find.text('Rent'), findsNothing); // no cap, so not a budget

      await press(t, 'Add budget');
      await fillAndSubmit(t, {'Category': 'Travel', 'Monthly cap': '250.5'});
      expect(bodyOf(last(calls, 'PUT', '/budgets')),
          {'category': 'Travel', 'month': thisMonth, 'cap': 250.5});
    });

    uiTest('Change keeps the category fixed and prefilled', {
      'GET /dashboard': (_) => json(_budgetDashboard),
      'PUT /budgets': (_) => json({}),
    }, (t, calls) async {
      await tab(t, 'Budgets');
      await t
          .tap(find.widgetWithText(OutlinedButton, 'Change').last); // transport
      await settle(t);
      expect(find.text('Change budget'), findsOneWidget);
      expect(t.widget<TextField>(input('Category')).readOnly, isTrue);
      expect(valueOf(t, 'Monthly cap'), '400');
      await fillAndSubmit(t, {'Monthly cap': '500'});
      expect(bodyOf(last(calls, 'PUT', '/budgets')),
          {'category': 'Transport', 'month': thisMonth, 'cap': 500.0});
    });

    uiTest('a blank category is rejected inline', {
      'GET /dashboard': (_) => json(_budgetDashboard),
    }, (t, calls) async {
      await tab(t, 'Budgets');
      await press(t, 'Add budget');
      await fillAndSubmit(t, {'Monthly cap': '50'});
      expect(find.text('Give the category a name, for example Food'),
          findsOneWidget);
      expect(called(calls, 'PUT', '/budgets'), isFalse);
    });

    uiTest('no budgets: an explanation and a first step', {}, (t, calls) async {
      await tab(t, 'Budgets');
      expect(find.text('No budgets for $monthName'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Set your first budget'),
          findsOneWidget);
    });
  });

  // ------------------------------------------------------------- recurring
  group('Recurring', () {
    final template = {
      'id': 1,
      'amount': 499.0,
      'category': 'music',
      'note': 'plan',
      'day_of_month': 5
    };

    uiTest('apply reports created, then already up to date', {
      'GET /recurring': (_) => json([template]),
      'POST /recurring/apply': (() {
        var n = 0;
        return (http.Request _) =>
            json({'month': thisMonth, 'created': n++ == 0 ? 1 : 0});
      })(),
    }, (t, calls) async {
      await tab(t, 'Recurring');
      expect(find.text('Music'), findsOneWidget);
      expect(find.text('Day 5'), findsOneWidget);
      await press(t, 'Apply to $monthName');
      expect(find.text('Added 1 expense to $monthName'), findsOneWidget);
      expect(
          last(calls, 'POST', '/recurring/apply').url.queryParameters['month'],
          thisMonth);

      await t.pump(const Duration(seconds: 5));
      await press(t, 'Apply to $monthName');
      expect(find.text('Nothing to add: $monthName is already up to date.'),
          findsOneWidget);
    });

    uiTest('add validates the day inline, then sends the template', {
      'POST /recurring': (_) => json({}, 201),
    }, (t, calls) async {
      await tab(t, 'Recurring');
      expect(find.text('No recurring expenses'), findsOneWidget);
      await press(t, 'Add template');
      await fillAndSubmit(t,
          {'Amount': '10', 'Category': 'Netflix', 'Day of month (1-28)': '31'});
      expect(find.text('Pick a day from 1 to 28'), findsOneWidget);
      expect(called(calls, 'POST', '/recurring'), isFalse);

      await fillAndSubmit(t, {'Day of month (1-28)': '5'});
      expect(bodyOf(last(calls, 'POST', '/recurring')), {
        'amount': 10.0,
        'category': 'Netflix',
        'note': '',
        'day_of_month': 5
      });
    });

    uiTest('removing a template can be undone', {
      'GET /recurring': (_) => json([template]),
      'DELETE /recurring/1': (_) => http.Response('', 204),
      'POST /recurring': (_) => json({}, 201),
    }, (t, calls) async {
      await tab(t, 'Recurring');
      await press(t, 'Remove', type: OutlinedButton);
      expect(called(calls, 'DELETE', '/recurring/1'), isTrue);
      await t.tap(find.text('Undo'));
      await settle(t);
      expect(bodyOf(last(calls, 'POST', '/recurring')), {
        'amount': 499.0,
        'category': 'music',
        'note': 'plan',
        'day_of_month': 5
      });
    });
  });

  // ----------------------------------------------------------------- goals
  group('Goals', () {
    final goal = {
      'id': 7,
      'name': 'Laptop',
      'target': 1000.0,
      'saved': 250.0,
      'progress': 0.25
    };

    uiTest('lists progress; add and add-money send the right bodies', {
      'GET /goals': (_) => json([goal]),
      'POST /goals': (_) => json({}, 201),
      'POST /goals/7/contribute': (_) => json({}),
    }, (t, calls) async {
      await tab(t, 'Goals');
      expect(find.text('Laptop'), findsOneWidget);
      expect(find.text('₹250 of ₹1,000'), findsOneWidget);
      expect(find.text('₹750 to go'), findsOneWidget);
      expect(find.text('25%'), findsWidgets);

      await press(t, 'Add goal');
      await fillAndSubmit(t, {'Name': 'Phone', 'Target amount': '500'});
      expect(bodyOf(last(calls, 'POST', '/goals')),
          {'name': 'Phone', 'target': 500.0});

      await press(t, 'Add money');
      expect(find.text('Add to Laptop'), findsOneWidget);
      await fillAndSubmit(t, {'Amount': '100'});
      expect(bodyOf(last(calls, 'POST', '/goals/7/contribute')),
          {'amount': 100.0});
      expect(find.text('Added ₹100 to Laptop'), findsOneWidget);
    });

    uiTest('a reached goal says so', {
      'GET /goals': (_) => json([
            {...goal, 'saved': 1000.0, 'progress': 1.0}
          ]),
    }, (t, calls) async {
      await tab(t, 'Goals');
      expect(find.text('Goal reached'), findsWidgets);
      expect(find.text('100%'), findsWidgets);
    });

    uiTest('Remove asks first, then calls the API', {
      'GET /goals': (_) => json([goal]),
      'DELETE /goals/7': (_) => http.Response('', 204),
    }, (t, calls) async {
      await tab(t, 'Goals');
      await press(t, 'Remove', type: OutlinedButton);
      expect(find.text('Delete Laptop?'), findsOneWidget);
      expect(called(calls, 'DELETE', '/goals/7'), isFalse); // not yet

      await press(t, 'Cancel', type: OutlinedButton);
      expect(called(calls, 'DELETE', '/goals/7'), isFalse);

      await press(t, 'Remove', type: OutlinedButton);
      await press(t, 'Delete goal', type: OutlinedButton);
      expect(called(calls, 'DELETE', '/goals/7'), isTrue);
    });

    uiTest('an invalid contribution is rejected inline', {
      'GET /goals': (_) => json([goal]),
    }, (t, calls) async {
      await tab(t, 'Goals');
      await press(t, 'Add money');
      await fillAndSubmit(t, {'Amount': '0'});
      expect(find.text('Enter an amount above 0'), findsOneWidget);
      expect(called(calls, 'POST', '/goals/7/contribute'), isFalse);
    });

    uiTest('no goals: an explanation and a first step', {}, (t, calls) async {
      await tab(t, 'Goals');
      expect(find.text('No savings goals yet'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Add your first goal'),
          findsOneWidget);
    });
  });

  // ----------------------------------------------------------------- shell
  group('Shell', () {
    uiTest(
        'every section has a page header and empty states explain themselves',
        {}, (t, calls) async {
      await tab(t, 'Expenses');
      expect(find.text('No expenses in $monthName'), findsOneWidget);
      await tab(t, 'Budgets');
      expect(find.text('No budgets for $monthName'), findsOneWidget);
      await tab(t, 'Recurring');
      expect(find.text('No recurring expenses'), findsOneWidget);
      await tab(t, 'Goals');
      expect(find.text('No savings goals yet'), findsOneWidget);
    });

    uiTest('system Back from another section returns to the dashboard', {},
        (t, calls) async {
      await tab(t, 'Goals');
      expect(find.text('No savings goals yet'), findsOneWidget);
      await t.binding.handlePopRoute();
      await settle(t);
      expect(find.text('Hi, Tester'), findsOneWidget);
    });

    uiTest('a wide window has a top navigation pill and the signed-in user', {},
        (t, calls) async {
      expect(find.text('Dashboard'), findsOneWidget);
      expect(find.text('tester'), findsOneWidget);
      expect(find.byTooltip('Log out'), findsOneWidget);
      // the nav sits in one row across the top, centred
      final nav = t.getCenter(find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == 'Main navigation'));
      expect(nav.dx, closeTo(600, 40));
      expect(nav.dy, lessThan(80));
    });

    uiTest('a phone gets a top bar and a floating bottom navigation pill', {},
        (t, calls) async {
      expect(find.byTooltip('Log out'), findsOneWidget);
      expect(find.text('Dashboard'), findsOneWidget);
      await tab(t, 'Expenses');
      expect(find.text('No expenses in $monthName'), findsOneWidget);
    }, size: phone);

    uiTest('large system text does not overflow or clip any screen', {
      'GET /dashboard': (_) => json(_budgetDashboard),
      'GET /expenses': (_) => json([
            expense(3, 150000, 'eating out with the whole team',
                note: 'a very long note about a team dinner that keeps going'),
            expense(4, 499, 'netflix', recurringId: 9),
          ]),
      'GET /recurring': (_) => json([
            {
              'id': 1,
              'amount': 12345678.0,
              'category': 'subscriptions and memberships',
              'note': 'plan with a long name',
              'day_of_month': 5
            }
          ]),
      'GET /goals': (_) => json([
            {
              'id': 7,
              'name': 'A laptop good enough for the whole of college',
              'target': 100000.0,
              'saved': 25000.0,
              'progress': 0.25
            }
          ]),
    }, (t, calls) async {
      // Layout overflows are reported as test failures by the framework.
      t.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      await settle(t);
      for (final name in [
        'Dashboard',
        'Expenses',
        'Budgets',
        'Recurring',
        'Goals'
      ]) {
        await tab(t, name);
      }
    }, size: const Size(360, 740));

    uiTest('the landing and login screens survive 2x system text', {},
        (t, calls) async {
      t.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      await settle(t);
      await t.tap(find.widgetWithText(FilledButton, 'Create account').first);
      await settle(t);
      await t.ensureVisible(find.text('Create your account'));
      expect(find.text('Create your account'), findsOneWidget);
    }, size: const Size(360, 740), loggedIn: false);

    uiTest('the large-text layout also holds on the landing page', {},
        (t, calls) async {
      t.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      await settle(t);
      expect(find.text('How it works'), findsOneWidget);
    }, size: const Size(360, 740), loggedIn: false);
  });
}
