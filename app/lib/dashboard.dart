import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'api.dart';
import 'common.dart';
import 'expenses.dart';
import 'theme.dart';
import 'widgets.dart';

String _plain(num v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

/// Opens the balance settings sheet (opening balance and safety line).
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
  await showFormSheet(
    context,
    title: 'Balance settings',
    subtitle: 'Balance = opening balance, minus every expense, minus money put into goals.',
    fields: [
      Field('opening', 'Opening balance',
          numeric: true, money: true, initial: _plain(acc['opening_balance'] as num)),
      Field('threshold', 'Safety line',
          numeric: true,
          money: true,
          initial: _plain(acc['low_balance_threshold'] as num),
          helper: 'Warn me when the balance drops below this. 0 turns the warning off.'),
    ],
    onSubmit: (v) async {
      final opening = double.tryParse(v['opening']!);
      final threshold = double.tryParse(v['threshold']!);
      final errors = <String, String>{
        if (opening == null) 'opening': 'Enter a number, for example 5000',
        if (threshold == null) 'threshold': 'Enter a number, for example 1000 (or 0)',
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

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final key = app.key;
    return Scaffold(
      body: Loader<Map<String, dynamic>>(
        resetKey: key,
        loadKey: app.tick,
        load: () => Api.dashboard(key),
        builder: (ctx, d, reload) => RefreshIndicator(
          onRefresh: reload,
          child: _DashboardBody(d: d, month: app.month),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => addExpense(context),
        icon: const Icon(Icons.add),
        label: const Text('Add expense'),
      ),
    );
  }
}

class _DashboardBody extends StatelessWidget {
  final Map<String, dynamic> d;
  final DateTime month;
  const _DashboardBody({required this.d, required this.month});

  @override
  Widget build(BuildContext context) {
    final cats = (d['categories'] as List).cast<Map<String, dynamic>>().toList()
      ..sort((a, b) {
        int rank(Map<String, dynamic> c) => c['over'] == true ? 0 : (c['cap'] != null ? 1 : 2);
        final r = rank(a).compareTo(rank(b));
        return r != 0 ? r : (b['spent'] as num).compareTo(a['spent'] as num);
      });
    final trend = (d['trend'] as List).cast<Map<String, dynamic>>();
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        _StatusPanel(d: d, month: month),
        const SectionHeading('Budgets this month'),
        if (cats.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Nothing spent or budgeted in ${monthLabel(month)} yet. Add an expense or set a budget.',
              style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
        for (final c in cats) _CategoryRow(c),
        const SectionHeading('Daily spend'),
        SpendColumns(trend: trend, month: month),
      ],
    );
  }
}

class _StatusPanel extends StatelessWidget {
  final Map<String, dynamic> d;
  final DateTime month;
  const _StatusPanel({required this.d, required this.month});

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final balance = (d['balance'] as num).toDouble();
    final threshold = (d['low_balance_threshold'] as num).toDouble();
    final spent = (d['total_spent'] as num).toDouble();
    final low = d['low_balance'] == true;
    final hasLine = threshold > 0;

    final headline = low
        ? '${money(balance)} left, ${money(threshold - balance)} below your safety line'
        : hasLine
            ? '${money(balance)} left, ${money(balance - threshold)} above your safety line'
            : '${money(balance)} left';
    final fg = low ? s.onTertiaryContainer : s.onSurface;
    final sub = low ? s.onTertiaryContainer : s.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      decoration: BoxDecoration(
        color: low ? s.tertiaryContainer : s.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (hasLine) ...[
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(low ? Icons.warning_amber_rounded : Icons.check_circle_outline,
                  color: low ? s.tertiary : s.primary),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(child: Text(headline, style: t.headlineSmall!.copyWith(color: fg))),
        ]),
        const SizedBox(height: 16),
        if (hasLine) ...[
          RouteLine(
            fill: math.max(balance, 0),
            total: math.max(balance, threshold) * 1.15,
            station: threshold,
            color: low ? s.tertiary : s.primary,
          ),
          const SizedBox(height: 8),
        ],
        if (hasLine)
          Wrap(spacing: 20, runSpacing: 4, children: [
            _LineKey(filled: true, color: low ? s.tertiary : s.primary, label: 'Balance ${money(balance)}', fg: sub),
            // Same colour rule as the station on the line: idle until the balance reaches it.
            _LineKey(
                filled: false,
                color: balance >= threshold ? s.primary : s.onSurfaceVariant,
                label: 'Safety line ${money(threshold)}',
                fg: sub),
          ]),
        if (hasLine) const SizedBox(height: 4),
        Text('Spent in ${monthLabel(month).split(' ').first}: ${money(spent)}',
            style: t.bodyMedium!.copyWith(color: sub)),
        if (!hasLine) ...[
          const SizedBox(height: 8),
          Text('Set a safety line to be warned when money runs low.',
              style: t.bodyMedium!.copyWith(color: s.onSurfaceVariant)),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(onPressed: () => editAccount(context), child: const Text('Set safety line')),
          ),
        ],
      ]),
    );
  }
}

/// Legend entry for the balance line: a dot for the travelled line, a ring for the station.
class _LineKey extends StatelessWidget {
  final bool filled;
  final Color color;
  final Color fg;
  final String label;
  const _LineKey({required this.filled, required this.color, required this.label, required this.fg});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      ExcludeSemantics(
        child: Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: filled ? color : Theme.of(context).colorScheme.surface,
            border: filled ? null : Border.all(color: color, width: 3),
          ),
        ),
      ),
      const SizedBox(width: 8),
      Text(label, style: Theme.of(context).textTheme.bodyMedium!.copyWith(color: fg)),
    ]);
  }
}

class _CategoryRow extends StatelessWidget {
  final Map<String, dynamic> c;
  const _CategoryRow(this.c);

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final name = c['category'] as String;
    final spent = (c['spent'] as num).toDouble();
    final cap = c['cap'] == null ? null : (c['cap'] as num).toDouble();
    final over = c['over'] == true;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CategoryDot(name),
          const SizedBox(width: 12),
          Expanded(child: Text(titleCase(name), style: t.titleSmall)),
          const SizedBox(width: 8),
          Amount(cap == null ? money(spent) : '${money(spent)} of ${money(cap)}',
              style: amountStyle(context, size: 18, color: over ? s.error : null)),
        ]),
        if (cap != null) ...[
          const SizedBox(height: 6),
          RouteLine(
            fill: spent,
            total: math.max(spent, cap),
            station: cap,
            color: categoryColor(name, Theme.of(context).brightness),
            overrun: over,
          ),
        ],
        if (over)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Row(children: [
              Icon(Icons.error_outline, size: 16, color: s.error),
              const SizedBox(width: 6),
              Text('${money(spent - cap!)} over budget',
                  style: t.bodySmall!.copyWith(color: s.error, fontWeight: FontWeight.w600)),
            ]),
          )
        else if (cap == null)
          Padding(
            padding: const EdgeInsets.only(left: 24),
            child: Text('No budget set', style: t.bodySmall!.copyWith(color: s.onSurfaceVariant)),
          ),
      ]),
    );
  }
}
