// End-to-end test of the Dart API client against a running backend.
// Start it first: cd backend && BUDGET_DB=/tmp/t.db uvicorn main:app --port 8000
//
// Every run registers its own throwaway users, so it can be repeated on a
// database that already has data.
import 'dart:io';

import 'package:budget_tracker/api.dart';
import 'package:flutter_test/flutter_test.dart';

const _password = 'a long test password';

/// Registers a new user and makes them the current one; returns the username.
Future<String> newUser(String prefix) async {
  final name = '${prefix}_${DateTime.now().microsecondsSinceEpoch}';
  final session = await Api.register(name, _password);
  Api.token = session['token'] as String;
  return name;
}

Matcher apiError(int status) =>
    throwsA(isA<ApiException>().having((e) => e.status, 'status', status));

void main() {
  setUpAll(() => HttpOverrides.global = null); // allow real HTTP in tests
  tearDown(() => Api.token = null);

  test('accounts: register, log in, who am I, log out', () async {
    final name = await newUser('acct');
    expect((await Api.me())['username'], name);

    // log in again from scratch (usernames are case-insensitive)
    Api.token = null;
    final session = await Api.login(name.toUpperCase(), _password);
    expect(session['username'], name);
    Api.token = session['token'] as String;
    expect((await Api.me())['username'], name);

    await Api.logout();
    expect(() => Api.me(), apiError(401)); // the token is dead
  });

  test('accounts: duplicate usernames and wrong passwords are rejected',
      () async {
    final name = await newUser('dup');
    Api.token = null;
    expect(() => Api.register(name, _password), apiError(409));
    expect(() => Api.login(name, 'not the password'), apiError(401));
    expect(
        () => Api.login(
            'nobody_${DateTime.now().microsecondsSinceEpoch}', _password),
        apiError(401));
    expect(() => Api.register('ab', _password), apiError(422)); // too short
    expect(() => Api.register('fine_name', 'short'), apiError(422));
  });

  test('data calls need a login', () async {
    Api.token = null;
    expect(() => Api.dashboard('2031-03'), apiError(401));
    expect(() => Api.expenses('2031-03'), apiError(401));
    expect(() => Api.goals(), apiError(401));
    Api.token = 'not-a-real-token';
    expect(() => Api.account(), apiError(401));
  });

  test('users cannot see each other\'s data', () async {
    await newUser('iso_a');
    await Api.setAccount(5000, 500);
    await Api.setBudget('food', '2031-03', 100);
    final added = await Api.addExpense(60, '2031-03-02', 'Food', 'lunch');
    final id = (added['expense'] as Map)['id'] as int;
    await Api.addGoal('Private goal', 100);
    await Api.addRecurring(10, 'gym', '', 3);

    await newUser('iso_b'); // switches to a second user
    expect(await Api.expenses('2031-03'), isEmpty);
    expect(await Api.budgets('2031-03'), isEmpty);
    expect(await Api.goals(), isEmpty);
    expect(await Api.recurring(), isEmpty);
    expect((await Api.account())['balance'], 0);
    expect((await Api.dashboard('2031-03'))['total_spent'], 0);
    // and cannot change user A's expense by guessing its id
    expect(() => Api.deleteExpense(id), apiError(404));
    expect(
        () => Api.updateExpense(id, 1, '2031-03-02', 'x', ''), apiError(404));
  });

  test('full flow against live backend', () async {
    await newUser('flow');
    const m = '2031-03';

    await Api.setAccount(5000, 500);
    await Api.setBudget('food', m, 100);

    var r = await Api.addExpense(60, '$m-02', 'Food', 'lunch');
    expect(r['alert'], isNull);
    r = await Api.addExpense(55.5, '$m-03', 'food', '');
    expect(r['alert']['over_by'], 15.5);
    final lastId = r['expense']['id'] as int;

    final rows = await Api.expenses(m);
    expect(rows.length, 2);

    // editing an expense returns the same alert information
    r = await Api.updateExpense(lastId, 70, '$m-03', 'Food', 'edited');
    expect(r['expense']['amount'], 70);
    expect(r['expense']['note'], 'edited');
    expect(r['alert']['over_by'], 30);

    var d = await Api.dashboard(m);
    expect(d['total_spent'], 130);
    final food = (d['categories'] as List).first as Map<String, dynamic>;
    expect(food['over'], true);

    expect((await Api.budgets(m)).length, 1);

    // recurring: apply twice, second time must add nothing
    await Api.addRecurring(499, 'subscriptions', 'music', 5);
    expect(await Api.applyRecurring('2031-04'), 1);
    expect(await Api.applyRecurring('2031-04'), 0);
    final tmpl = (await Api.recurring()).first as Map<String, dynamic>;
    await Api.deleteRecurring(tmpl['id'] as int);
    expect(await Api.recurring(), isEmpty);

    // goals
    await Api.addGoal('Headphones', 500);
    final goal = (await Api.goals()).first as Map<String, dynamic>;
    await Api.contribute(goal['id'] as int, 100);
    final updated = (await Api.goals()).first as Map<String, dynamic>;
    expect(updated['saved'], 100);
    expect(updated['progress'], 0.2);
    await Api.deleteGoal(goal['id'] as int);

    await Api.deleteExpense(lastId);
    d = await Api.dashboard(m);
    expect(d['total_spent'], 60);
  });

  test('server errors surface as exceptions', () async {
    await newUser('err');
    expect(() => Api.deleteExpense(999999), apiError(404));
  });
}
