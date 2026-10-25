import 'package:flutter/material.dart';

import 'api.dart';
import 'common.dart';
import 'theme.dart';
import 'ui.dart';

class RecurringScreen extends StatelessWidget {
  const RecurringScreen({super.key});

  Future<void> _add(BuildContext context) async {
    final app = AppScope.read(context);
    final saved = await showFormDialog(
      context,
      title: 'New recurring expense',
      subtitle:
          'Repeats on the same day every month, for example rent or a subscription.',
      fields: const [
        Field('amount', 'Amount', numeric: true, money: true),
        Field('category', 'Category'),
        Field('note', 'Note (optional)'),
        Field('day', 'Day of month (1-28)', numeric: true),
      ],
      onSubmit: (v) async {
        final amount = double.tryParse(v['amount']!);
        final day = int.tryParse(v['day']!);
        final errors = <String, String>{
          if (amount == null || amount <= 0)
            'amount': 'Enter an amount above 0',
          if (v['category']!.isEmpty)
            'category': 'Give it a category, for example Rent',
          if (day == null || day < 1 || day > 28)
            'day': 'Pick a day from 1 to 28',
        };
        if (errors.isNotEmpty) return errors;
        try {
          await Api.addRecurring(amount!, v['category']!, v['note']!, day!);
          return null;
        } on ApiException catch (e) {
          return {formError: e.message};
        }
      },
    );
    if (saved) app.changed();
  }

  Future<void> _apply(BuildContext context) async {
    final app = AppScope.read(context);
    try {
      final n = await Api.applyRecurring(app.key);
      if (!context.mounted) return;
      if (n == 0) {
        snack(context,
            'Nothing to add: ${monthLabel(app.month)} is already up to date.');
      } else {
        app.changed();
        snack(context,
            'Added $n ${n == 1 ? 'expense' : 'expenses'} to ${monthLabel(app.month)}');
      }
    } catch (e) {
      if (context.mounted) snack(context, '$e', tone: SnackTone.alert);
    }
  }

  Future<void> _delete(BuildContext context, Map<String, dynamic> r) async {
    final app = AppScope.read(context);
    try {
      await Api.deleteRecurring(r['id'] as int);
    } catch (e) {
      if (context.mounted) snack(context, '$e', tone: SnackTone.alert);
      return;
    }
    app.changed();
    if (!context.mounted) return;
    snack(
      context,
      'Deleted ${titleCase(r['category'] as String)} ${money(r['amount'] as num)} template',
      action: 'Undo',
      seconds: 6,
      onAction: () async {
        try {
          await Api.addRecurring(
              (r['amount'] as num).toDouble(),
              r['category'] as String,
              r['note'] as String,
              r['day_of_month'] as int);
          app.changed();
        } catch (e) {
          if (context.mounted) snack(context, '$e', tone: SnackTone.alert);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Loader<List<dynamic>>(
      loadKey: app.tick,
      load: Api.recurring,
      builder: (ctx, all, reload) => RefreshIndicator(
        onRefresh: reload,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 48),
          children: _content(context, all.cast<Map<String, dynamic>>()),
        ),
      ),
    );
  }

  List<Widget> _content(BuildContext context, List<Map<String, dynamic>> rows) {
    final app = AppScope.of(context);
    final k = context.tk;
    final t = Theme.of(context).textTheme;
    final wide = isWide(context);
    final head = PageHead(
      title: 'Recurring',
      subtitle:
          'Bills and subscriptions that repeat every month. Add them to any month with one click.',
      actions: [
        const MonthSwitcher(),
        Btn('Add template', icon: Icons.add, onPressed: () => _add(context)),
      ],
    );
    if (rows.isEmpty) {
      return [
        head,
        EmptyPanel(
          title: 'No recurring expenses',
          message:
              'Set up rent or a subscription once, then add it to any month with one click.',
          actionLabel: 'Add your first template',
          onAction: () => _add(context),
        ),
      ];
    }
    final total = rows.fold<double>(0, (a, r) => a + (r['amount'] as num));
    final apply =
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Semantics(
          header: true,
          container: true,
          child: Text('Add to ${monthLabel(app.month)}', style: t.titleMedium)),
      const SizedBox(height: 4),
      Text(
          'Adds each template once, on its day. Safe to repeat: nothing is added twice.',
          style: t.bodyMedium!.copyWith(color: k.ink2)),
    ]);
    final applyBtn = Btn('Apply to ${monthLabel(app.month)}',
        icon: Icons.playlist_add_check, onPressed: () => _apply(context));
    return [
      head,
      StatStrip([
        Stat('${rows.length}', rows.length == 1 ? 'Template' : 'Templates'),
        Stat(money(total), 'Added each month'),
        Stat(
            money(rows
                .map((r) => (r['amount'] as num).toDouble())
                .reduce((a, b) => a > b ? a : b)),
            'Largest template'),
      ]),
      const SizedBox(height: 20),
      Panel(
        child: wide
            ? Row(children: [
                Expanded(child: apply),
                const SizedBox(width: 20),
                applyBtn
              ])
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                apply,
                const SizedBox(height: 16),
                applyBtn,
              ]),
      ),
      const SizedBox(height: 20),
      Panel(
        padding: wide
            ? const EdgeInsets.fromLTRB(24, 20, 24, 8)
            : const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const PanelTitle('Templates'),
          if (wide)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(children: [
                SizedBox(
                    width: 160,
                    child: Text('Category',
                        style: t.labelMedium!.copyWith(color: k.ink3))),
                Expanded(
                    child: Text('Note',
                        style: t.labelMedium!.copyWith(color: k.ink3))),
                SizedBox(
                    width: 120,
                    child: Text('Repeats on',
                        style: t.labelMedium!.copyWith(color: k.ink3))),
                SizedBox(
                    width: 120,
                    child: Text('Amount',
                        textAlign: TextAlign.end,
                        style: t.labelMedium!.copyWith(color: k.ink3))),
                const SizedBox(width: 110),
              ]),
            ),
          for (var i = 0; i < rows.length; i++)
            _Row(rows[i],
                first: i == 0,
                wide: wide,
                onDelete: () => _delete(context, rows[i])),
        ]),
      ),
    ];
  }
}

class _Row extends StatelessWidget {
  final Map<String, dynamic> r;
  final bool first;
  final bool wide;
  final VoidCallback onDelete;
  const _Row(this.r,
      {required this.first, required this.wide, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final k = context.tk;
    final t = Theme.of(context).textTheme;
    final category = r['category'] as String;
    final note = r['note'] as String;
    final day = 'Day ${r['day_of_month']} of every month';
    final amount = money(r['amount'] as num);
    final remove = Btn('Remove',
        kind: BtnKind.ghost,
        small: true,
        semanticLabel: 'Remove ${titleCase(category)} template',
        onPressed: onDelete);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
          border: first ? null : Border(top: BorderSide(color: k.line))),
      child: wide
          ? Row(children: [
              SizedBox(
                  width: 160,
                  child: Align(
                      alignment: Alignment.centerLeft,
                      child: CategoryTag(category))),
              Expanded(
                  child: Text(note,
                      overflow: TextOverflow.ellipsis,
                      style: t.bodyMedium!.copyWith(color: k.ink2))),
              SizedBox(
                  width: 120,
                  child: Text('Day ${r['day_of_month']}',
                      style: t.bodyMedium!.copyWith(color: k.ink2))),
              SizedBox(
                  width: 120,
                  child: Text(amount,
                      textAlign: TextAlign.end,
                      style:
                          t.bodyLarge!.copyWith(fontWeight: FontWeight.w700))),
              SizedBox(
                  width: 110,
                  child:
                      Align(alignment: Alignment.centerRight, child: remove)),
            ])
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                    child: Align(
                        alignment: Alignment.centerLeft,
                        child: CategoryTag(category))),
                Text(amount,
                    style: t.bodyLarge!.copyWith(fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: 6),
              Text('$day${note.isEmpty ? '' : ' · $note'}', style: t.bodySmall),
              const SizedBox(height: 10),
              remove,
            ]),
    );
  }
}
