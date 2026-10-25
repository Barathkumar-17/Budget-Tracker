import 'package:flutter/material.dart';

import 'api.dart';
import 'common.dart';
import 'theme.dart';
import 'widgets.dart';

class RecurringScreen extends StatelessWidget {
  const RecurringScreen({super.key});

  Future<void> _add(BuildContext context) async {
    final app = AppScope.read(context);
    final saved = await showFormSheet(
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
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: Loader<List<dynamic>>(
        loadKey: app.tick,
        load: Api.recurring,
        builder: (ctx, all, reload) {
          final rows = all.cast<Map<String, dynamic>>();
          if (rows.isEmpty) {
            return const EmptyState(
              icon: Icons.repeat,
              title: 'No recurring expenses',
              message:
                  'Tap Add template to set up rent or a subscription once, then add it to any month with one tap.',
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
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                        color: s.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(20)),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                              'Adds each template once, on its day. Safe to repeat: nothing is added twice.',
                              style: t.bodyMedium!
                                  .copyWith(color: s.onSurfaceVariant)),
                          const SizedBox(height: 12),
                          FilledButton.tonalIcon(
                            onPressed: () => _apply(context),
                            icon: const Icon(Icons.playlist_add_check),
                            label: Text('Apply to ${monthLabel(app.month)}'),
                          ),
                        ]),
                  ),
                ),
                const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: SectionHeading('Templates')),
                for (final r in rows)
                  ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 64),
                    child: Padding(
                      padding: const EdgeInsets.only(
                          left: 16, right: 4, top: 4, bottom: 4),
                      child: Row(children: [
                        CategoryDot(r['category'] as String),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(titleCase(r['category'] as String),
                                    style: t.titleSmall),
                                Text(
                                  'Day ${r['day_of_month']} of every month'
                                  '${(r['note'] as String).isEmpty ? '' : ' · ${r['note']}'}',
                                  style: t.bodySmall!
                                      .copyWith(color: s.onSurfaceVariant),
                                ),
                              ]),
                        ),
                        const SizedBox(width: 8),
                        Amount(money(r['amount'] as num),
                            style: amountStyle(context, size: 18)),
                        const SizedBox(width: 4),
                        IconButton(
                          tooltip:
                              'Delete ${titleCase(r['category'] as String)} template',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _delete(context, r),
                        ),
                      ]),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(context),
        icon: const Icon(Icons.add),
        label: const Text('Add template'),
      ),
    );
  }
}
