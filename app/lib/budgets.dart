import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'api.dart';
import 'common.dart';
import 'theme.dart';
import 'widgets.dart';

String _plain(num v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toString();

class BudgetsScreen extends StatelessWidget {
  const BudgetsScreen({super.key});

  Future<void> _edit(BuildContext context,
      {String category = '', num? cap}) async {
    final app = AppScope.read(context);
    final editing = category.isNotEmpty;
    final saved = await showFormSheet(
      context,
      title: editing ? 'Change budget' : 'New budget',
      subtitle: 'For ${monthLabel(app.month)}',
      fields: [
        Field('category', 'Category',
            initial: titleCase(category), readOnly: editing),
        Field('cap', 'Monthly cap',
            numeric: true,
            money: true,
            initial: cap == null ? '' : _plain(cap)),
      ],
      onSubmit: (v) async {
        final amount = double.tryParse(v['cap']!);
        final errors = <String, String>{
          if (v['category']!.isEmpty)
            'category': 'Give the category a name, for example Food',
          if (amount == null || amount < 0) 'cap': 'Enter an amount, 0 or more',
        };
        if (errors.isNotEmpty) return errors;
        try {
          await Api.setBudget(v['category']!, app.key, amount!);
          return null;
        } on ApiException catch (e) {
          return {formError: e.message};
        }
      },
    );
    if (saved) app.changed();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final key = app.key;
    return Scaffold(
      body: Loader<Map<String, dynamic>>(
        resetKey: key,
        loadKey: app.tick,
        load: () => Api.dashboard(key),
        builder: (ctx, d, reload) {
          final rows = (d['categories'] as List)
              .cast<Map<String, dynamic>>()
              .where((c) => c['cap'] != null)
              .toList()
            ..sort((a, b) {
              final r = ((a['over'] == true) ? 0 : 1)
                  .compareTo((b['over'] == true) ? 0 : 1);
              return r != 0
                  ? r
                  : (a['category'] as String)
                      .compareTo(b['category'] as String);
            });
          if (rows.isEmpty) {
            return EmptyState(
              icon: Icons.pie_chart_outline,
              title: 'No budgets for ${monthLabel(app.month)}',
              message:
                  'Tap Add budget to set a monthly cap per category and get warned the moment you pass it.',
            );
          }
          return RefreshIndicator(
            onRefresh: reload,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(0, 16, 0, 96),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text('Tap a budget to change its cap.',
                      style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant)),
                ),
                const SizedBox(height: 8),
                for (final c in rows)
                  _BudgetRow(
                    c,
                    onTap: () => _edit(context,
                        category: c['category'] as String,
                        cap: c['cap'] as num),
                  ),
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context),
        icon: const Icon(Icons.add),
        label: const Text('Add budget'),
      ),
    );
  }
}

class _BudgetRow extends StatelessWidget {
  final Map<String, dynamic> c;
  final VoidCallback onTap;
  const _BudgetRow(this.c, {required this.onTap});

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final name = c['category'] as String;
    final spent = (c['spent'] as num).toDouble();
    final cap = (c['cap'] as num).toDouble();
    final over = c['over'] == true;
    final left = cap - spent;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 72),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              CategoryDot(name),
              const SizedBox(width: 12),
              Expanded(child: Text(titleCase(name), style: t.titleSmall)),
              const SizedBox(width: 8),
              Amount(money(cap), style: amountStyle(context, size: 18)),
            ]),
            const SizedBox(height: 6),
            RouteLine(
              fill: spent,
              total: math.max(spent, cap),
              station: cap,
              color: categoryColor(name, Theme.of(context).brightness),
              overrun: over,
            ),
            const SizedBox(height: 2),
            Row(children: [
              if (over) ...[
                Icon(Icons.error_outline, size: 16, color: s.error),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  over
                      ? '${money(spent)} spent, ${money(-left)} over'
                      : '${money(spent)} spent, ${money(left)} left',
                  style: t.bodySmall!.copyWith(
                      color: over ? s.error : s.onSurfaceVariant,
                      fontWeight: over ? FontWeight.w600 : null),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}
