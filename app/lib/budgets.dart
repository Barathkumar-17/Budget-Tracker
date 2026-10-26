import 'package:flutter/material.dart';

import 'api.dart';
import 'common.dart';
import 'theme.dart';
import 'ui.dart';

String _plain(num v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toString();

class BudgetsScreen extends StatelessWidget {
  const BudgetsScreen({super.key});

  Future<void> _edit(BuildContext context,
      {String category = '', num? cap}) async {
    final app = AppScope.read(context);
    final editing = category.isNotEmpty;
    final saved = await showFormDialog(
      context,
      title: editing ? 'Change budget' : 'New budget',
      subtitle: 'For ${monthLabel(app.month)}',
      fields: [
        Field('category', 'Category',
            initial: titleCase(category), readOnly: editing, maxLength: 60),
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
          if (amountProblem(amount, 'Enter an amount, 0 or more', zeroOk: true)
              case final p?)
            'cap': p,
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
    return Loader<Map<String, dynamic>>(
      resetKey: key,
      loadKey: app.tick,
      load: () => Api.dashboard(key),
      builder: (ctx, d, reload) {
        final rows = (d['categories'] as List)
            .cast<Map<String, dynamic>>()
            .where((c) => c['cap'] != null)
            .toList()
          ..sort((a, b) {
            double ratio(Map<String, dynamic> c) {
              final cap = (c['cap'] as num).toDouble();
              return cap == 0 ? 99 : (c['spent'] as num).toDouble() / cap;
            }

            return ratio(b).compareTo(ratio(a));
          });
        return RefreshIndicator(
          onRefresh: reload,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.only(bottom: isWide(context) ? 48 : 112),
            children: _content(context, rows),
          ),
        );
      },
    );
  }

  List<Widget> _content(BuildContext context, List<Map<String, dynamic>> rows) {
    final app = AppScope.of(context);
    final k = context.tk;
    final head = PageHead(
      eyebrow: 'Monthly caps',
      title: 'Budgets',
      subtitle:
          'A monthly cap per category. The bar shows how much of each you have used.',
      actions: [
        const MonthSwitcher(),
        Btn('Add budget', icon: Icons.add, onPressed: () => _edit(context)),
      ],
    );
    if (rows.isEmpty) {
      return [
        head,
        EmptyPanel(
          title: 'No budgets for ${monthLabel(app.month)}',
          message:
              'Set a monthly cap per category and get warned the moment you pass it.',
          actionLabel: 'Set your first budget',
          onAction: () => _edit(context),
        ),
      ];
    }
    final totalCap =
        rows.fold<double>(0, (a, c) => a + (c['cap'] as num).toDouble());
    final totalSpent =
        rows.fold<double>(0, (a, c) => a + (c['spent'] as num).toDouble());
    final over = rows.where((c) => c['over'] == true).length;
    return [
      head,
      StatStrip([
        Stat(money(totalCap), 'Budgeted'),
        Stat(money(totalSpent), 'Spent in these categories'),
        Stat(money(totalCap - totalSpent), 'Left to spend',
            color: totalCap - totalSpent < 0 ? k.miss : null),
        Stat('$over', 'Over budget', color: over > 0 ? k.miss : null),
      ]),
      const SizedBox(height: 20),
      Panel(
        child: Column(children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(color: k.line, height: 36),
            _BudgetRow(
              rows[i],
              onEdit: () => _edit(context,
                  category: rows[i]['category'] as String,
                  cap: rows[i]['cap'] as num),
            ),
          ],
        ]),
      ),
    ];
  }
}

class _BudgetRow extends StatelessWidget {
  final Map<String, dynamic> c;
  final VoidCallback onEdit;
  const _BudgetRow(this.c, {required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final k = context.tk;
    final name = c['category'] as String;
    final spent = (c['spent'] as num).toDouble();
    final cap = (c['cap'] as num).toDouble();
    final ratio = cap == 0 ? 2.0 : spent / cap;
    final over = c['over'] == true;
    final (kind, label) = ratio > 1
        ? (TagKind.no, 'Over budget')
        : (ratio >= 0.85
            ? (TagKind.warn, 'Close to limit')
            : (TagKind.ok, 'Within budget'));
    return InkWell(
      onTap: onEdit,
      borderRadius: BorderRadius.circular(10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CategoryTag(name),
          const SizedBox(width: 8),
          Tag(label, kind: kind),
          const Spacer(),
          Btn('Change',
              kind: BtnKind.ghost,
              small: true,
              semanticLabel: 'Change ${titleCase(name)} budget',
              onPressed: onEdit),
        ]),
        const SizedBox(height: 12),
        BarRow(
          label: '${money(spent)} spent',
          trailing: 'of ${money(cap)}',
          fraction: ratio,
          color: ratio > 1 ? k.miss : (ratio >= 0.85 ? k.amber : k.link),
          why: over
              ? '${money(spent - cap)} over budget'
              : '${money(cap - spent)} left',
          whyColor: over ? k.miss : null,
        ),
      ]),
    );
  }
}
