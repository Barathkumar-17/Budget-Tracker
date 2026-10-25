// End-to-end test of the Dart API client against a running backend.
// Start it first: cd backend && BUDGET_DB=/tmp/t.db uvicorn main:app --port 8000
import 'dart:io';

import 'package:budget_tracker/api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() => HttpOverrides.global = null); // allow real HTTP in tests

  test('full flow against live backend', () async {
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

    var d = await Api.dashboard(m);
    expect(d['total_spent'], 115.5);
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

    // cleanup of the April recurring expense keeps the run repeatable
    for (final e in await Api.expenses('2031-04')) {
      await Api.deleteExpense((e as Map<String, dynamic>)['id'] as int);
    }
  });

  test('server errors surface as exceptions', () async {
    expect(() => Api.deleteExpense(999999), throwsException);
  });
}
