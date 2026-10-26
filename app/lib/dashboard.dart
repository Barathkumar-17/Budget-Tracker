import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'api.dart';
import 'auth.dart';
import 'common.dart';
import 'expenses.dart';
import 'theme.dart';
import 'ui.dart';

String _plain(num v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toString();

/// Opens the balance settings dialog (opening balance and safety line).
Future<void> editAccount(BuildContext context) async {
  final app = AppScope.read(context);
  final Map<String, dynamic> acc;
  try {
    acc = await Api.account();
  } catch (e) {
    if (context.mounted) snack(context, '$e', tone: SnackTone.alert);
    return;
  }
  if (!context.mounted) return;
  await showFormDialog(
    context,
    title: 'Balance settings',
    subtitle:
        'Balance = opening balance, minus every expense, minus money put into goals.',
    fields: [
      Field('opening', 'Opening balance',
          numeric: true,
          money: true,
          initial: _plain(acc['opening_balance'] as num)),
      Field('threshold', 'Safety line',
          numeric: true,
          money: true,
          initial: _plain(acc['low_balance_threshold'] as num),
          helper:
              'Warn me when the balance drops below this. 0 turns the warning off.'),
    ],
    onSubmit: (v) async {
      final opening = double.tryParse(v['opening']!);
      final threshold = double.tryParse(v['threshold']!);
      final errors = <String, String>{
        if (amountProblem(opening, 'Enter a number, for example 5000',
                zeroOk: true)
            case final p?)
          'opening': p,
        if (amountProblem(threshold, 'Enter a number, for example 1000 (or 0)',
                zeroOk: true)
            case final p?)
          'threshold': p,
      };
      if (errors.isNotEmpty) return errors;
      try {
        await Api.setAccount(opening!, threshold!);
        app.changed();
        return null;
      } on ApiException catch (e) {
        return {formError: e.message};
      }
    },
  );
}

class _DashData {
  final Map<String, dynamic> dash;
  final List<Map<String, dynamic>> expenses;
  final List<Map<String, dynamic>> goals;
  _DashData(this.dash, this.expenses, this.goals);
}

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final key = app.key;
    return Loader<_DashData>(
      resetKey: key,
      loadKey: app.tick,
      load: () async {
        final r = await Future.wait<dynamic>(
            [Api.dashboard(key), Api.expenses(key), Api.goals()]);
        return _DashData(
          r[0] as Map<String, dynamic>,
          (r[1] as List).cast<Map<String, dynamic>>(),
          (r[2] as List).cast<Map<String, dynamic>>(),
        );
      },
      builder: (ctx, d, reload) => RefreshIndicator(
        onRefresh: reload,
        child: _DashboardBody(d: d),
      ),
    );
  }
}

Color _barColor(BuildContext c, double ratio) {
  final k = c.tk;
  return ratio > 1 ? k.miss : (ratio >= 0.85 ? k.amber : k.link);
}

class _DashboardBody extends StatelessWidget {
  final _DashData d;
  const _DashboardBody({required this.d});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final auth = AuthScope.of(context);
    final k = context.tk;
    final wide = isWide(context);

    final dash = d.dash;
    final balance = (dash['balance'] as num).toDouble();
    final threshold = (dash['low_balance_threshold'] as num).toDouble();
    final spent = (dash['total_spent'] as num).toDouble();
    final low = dash['low_balance'] == true;
    final hasLine = threshold > 0;
    final cats = (dash['categories'] as List).cast<Map<String, dynamic>>();
    final capped = cats.where((c) => c['cap'] != null).toList()
      ..sort((a, b) {
        double ratio(Map<String, dynamic> c) {
          final cap = (c['cap'] as num).toDouble();
          return cap == 0 ? 99 : (c['spent'] as num).toDouble() / cap;
        }

        return ratio(b).compareTo(ratio(a));
      });
    final uncapped = cats.where((c) => c['cap'] == null).toList()
      ..sort((a, b) => (b['spent'] as num).compareTo(a['spent'] as num));
    final totalCap =
        capped.fold<double>(0, (a, c) => a + (c['cap'] as num).toDouble());
    final cappedSpent =
        capped.fold<double>(0, (a, c) => a + (c['spent'] as num).toDouble());
    final overCount = capped.where((c) => c['over'] == true).length;
    final used = totalCap <= 0 ? 0.0 : cappedSpent / totalCap;

    final subtitle = low
        ? 'You have ${money(balance)} left, ${money(threshold - balance)} below your safety line.'
        : hasLine
            ? 'You have ${money(balance)} left, ${money(balance - threshold)} above your safety line.'
            : 'You have ${money(balance)} left. Set a safety line to be warned when money runs low.';

    final left = <Widget>[
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          PanelTitle('Budgets this month',
              trailing: Btn('Manage',
                  kind: BtnKind.ghost,
                  small: true,
                  onPressed: () => app.goTo(2))),
          if (capped.isEmpty)
            Text(
                'No budgets are set for ${monthLabel(app.month)} yet. Give a category a monthly cap to see how much of it you have used.',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium!
                    .copyWith(color: k.ink2)),
          for (var i = 0; i < capped.length; i++) ...[
            if (i > 0) const SizedBox(height: 18),
            _budgetRow(context, capped[i]),
          ],
          if (capped.isEmpty) ...[
            const SizedBox(height: 14),
            Btn('Set a budget', small: true, onPressed: () => app.goTo(2)),
          ],
          if (uncapped.isNotEmpty) ...[
            const SizedBox(height: 22),
            Text('Spending without a budget',
                style: Theme.of(context)
                    .textTheme
                    .labelLarge!
                    .copyWith(color: k.ink3)),
            const SizedBox(height: 6),
            for (final c in uncapped)
              _ListRow(
                first: c == uncapped.first,
                left: CategoryTag(c['category'] as String),
                right: money(c['spent'] as num),
              ),
          ],
        ]),
      ),
      const SizedBox(height: 20),
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const PanelTitle('Daily spend'),
          DailyChart(
              trend: (dash['trend'] as List).cast<Map<String, dynamic>>(),
              month: app.month),
        ]),
      ),
    ];

    final right = <Widget>[
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const PanelTitle('Budget used'),
          if (capped.isEmpty)
            Text('Set budgets to see how much of them you have used.',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium!
                    .copyWith(color: k.ink2))
          else
            Row(children: [
              Ring(
                percent: used * 100,
                size: 112,
                color: used > 1 ? k.miss : (used >= 0.85 ? k.amber : k.match),
                center: '${(used * 100).round()}%',
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${money(cappedSpent)} of ${money(totalCap)}',
                          style: Theme.of(context)
                              .textTheme
                              .bodyLarge!
                              .copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text('spent in budgeted categories',
                          style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: 10),
                      Tag(
                          overCount > 0
                              ? '$overCount over budget'
                              : (used >= 0.85
                                  ? 'Close to the limit'
                                  : 'On track'),
                          kind: overCount > 0
                              ? TagKind.no
                              : (used >= 0.85 ? TagKind.warn : TagKind.ok)),
                    ]),
              ),
            ]),
        ]),
      ),
      const SizedBox(height: 20),
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          PanelTitle('Recent expenses',
              trailing: Btn('View all',
                  kind: BtnKind.ghost,
                  small: true,
                  onPressed: () => app.goTo(1))),
          if (d.expenses.isEmpty)
            Text('Nothing spent in ${monthLabel(app.month)} yet.',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium!
                    .copyWith(color: k.ink2)),
          for (final e in d.expenses.take(5))
            _ListRow(
              first: e == d.expenses.first,
              left: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CategoryTag(e['category'] as String),
                    const SizedBox(height: 4),
                    Text(
                        '${dayLabel(e['date'] as String)}${(e['note'] as String).isEmpty ? '' : ' · ${e['note']}'}',
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall),
                  ]),
              right: money(e['amount'] as num),
            ),
        ]),
      ),
      const SizedBox(height: 20),
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          PanelTitle('Savings goals',
              trailing: Btn(d.goals.isEmpty ? 'Add a goal' : 'View all',
                  kind: BtnKind.ghost,
                  small: true,
                  onPressed: () => app.goTo(4))),
          if (d.goals.isEmpty)
            Text(
                'Set money aside for something you want. Contributions come out of your balance.',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium!
                    .copyWith(color: k.ink2)),
          for (var i = 0; i < math.min(3, d.goals.length); i++) ...[
            if (i > 0) const SizedBox(height: 16),
            _goalRow(context, d.goals[i]),
          ],
        ]),
      ),
    ];

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.only(bottom: isWide(context) ? 48 : 112),
      children: [
        PageHead(
          eyebrow: 'Overview',
          title: 'Hi, ${titleCase(auth.username ?? '')}',
          subtitle: subtitle,
          actions: [
            const MonthSwitcher(),
            IconBtn(
                icon: Icons.tune,
                tooltip: 'Balance settings',
                outlined: true,
                size: 44,
                onPressed: () => editAccount(context)),
            Btn('Add expense',
                icon: Icons.add, onPressed: () => addExpense(context)),
          ],
        ),
        if (low) ...[
          Banner2(
              'Low balance: ${money(balance)} left, ${money(threshold - balance)} below your ${money(threshold)} safety line.'),
          const SizedBox(height: 20),
        ],
        StatStrip([
          Stat(money(balance), 'Balance', color: low ? k.miss : null),
          Stat(money(spent),
              'Spent in ${monthLabel(app.month).split(' ').first}'),
          Stat(money(totalCap), 'Budgeted this month'),
          Stat('$overCount', 'Categories over budget',
              color: overCount > 0 ? k.miss : null),
        ]),
        const SizedBox(height: 20),
        if (wide)
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 3, child: Column(children: left)),
            const SizedBox(width: 20),
            Expanded(flex: 2, child: Column(children: right)),
          ])
        else ...[...left, const SizedBox(height: 20), ...right],
      ],
    );
  }

  Widget _budgetRow(BuildContext context, Map<String, dynamic> c) {
    final k = context.tk;
    final name = c['category'] as String;
    final spent = (c['spent'] as num).toDouble();
    final cap = (c['cap'] as num).toDouble();
    final ratio = cap == 0 ? 2.0 : spent / cap;
    final over = c['over'] == true;
    return BarRow(
      label: titleCase(name),
      trailing: '${money(spent)} of ${money(cap)}',
      fraction: ratio,
      color: _barColor(context, ratio),
      why: over
          ? '${money(spent - cap)} over budget'
          : '${money(cap - spent)} left',
      whyColor: over ? k.miss : null,
    );
  }

  Widget _goalRow(BuildContext context, Map<String, dynamic> g) {
    final k = context.tk;
    final saved = (g['saved'] as num).toDouble();
    final target = (g['target'] as num).toDouble();
    return BarRow(
      label: g['name'] as String,
      trailing: '${money(saved)} of ${money(target)}',
      fraction: target == 0 ? 0 : saved / target,
      color: saved >= target ? k.match : k.link,
    );
  }
}

class _ListRow extends StatelessWidget {
  final bool first;
  final Widget left;
  final String right;
  const _ListRow(
      {required this.first, required this.left, required this.right});

  @override
  Widget build(BuildContext context) {
    final k = context.tk;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(
          border: first ? null : Border(top: BorderSide(color: k.line))),
      child: Row(children: [
        Expanded(child: Align(alignment: Alignment.centerLeft, child: left)),
        const SizedBox(width: 12),
        Text(right,
            style: Theme.of(context)
                .textTheme
                .bodyLarge!
                .copyWith(fontWeight: FontWeight.w700)),
      ]),
    );
  }
}
