import 'package:flutter/material.dart';
import 'api.dart';
import 'common.dart';

class RecurringScreen extends StatelessWidget {
  const RecurringScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Loader<List<dynamic>>(
      load: Api.recurring,
      builder: (ctx, rows, reload) => Scaffold(
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: FilledButton.icon(
              icon: const Icon(Icons.play_arrow),
              label: const Text('Apply to this month'),
              onPressed: () async {
                try {
                  final n = await Api.applyRecurring(monthKey(DateTime.now()));
                  if (ctx.mounted) snack(ctx, n == 0 ? 'Already applied' : 'Added $n expense(s)');
                } catch (e) {
                  if (ctx.mounted) snack(ctx, '$e');
                }
              },
            ),
          ),
          Expanded(
            child: rows.isEmpty
                ? const Center(child: Text('No recurring templates'))
                : ListView(children: [
                    for (final r in rows.cast<Map<String, dynamic>>())
                      ListTile(
                        title: Text('${r['category']}  ${money(r['amount'])}'),
                        subtitle: Text('Day ${r['day_of_month']}'
                            '${(r['note'] as String).isEmpty ? '' : ' · ${r['note']}'}'),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            try {
                              await Api.deleteRecurring(r['id'] as int);
                            } catch (e) {
                              if (ctx.mounted) snack(ctx, '$e');
                            }
                            await reload();
                          },
                        ),
                      ),
                  ]),
          ),
        ]),
        floatingActionButton: FloatingActionButton(
          child: const Icon(Icons.add),
          onPressed: () async {
            final v = await promptFields(ctx, 'New recurring expense', [
              const Field('amount', 'Amount', numeric: true),
              const Field('category', 'Category'),
              const Field('note', 'Note (optional)'),
              const Field('day', 'Day of month (1-28)', numeric: true),
            ]);
            if (v == null) return;
            final amount = double.tryParse(v['amount']!);
            final day = int.tryParse(v['day']!);
            if (amount == null || amount <= 0 || v['category']!.isEmpty ||
                day == null || day < 1 || day > 28) {
              if (ctx.mounted) snack(ctx, 'Check amount, category and day (1-28)');
              return;
            }
            try {
              await Api.addRecurring(amount, v['category']!, v['note']!, day);
              await reload();
            } catch (e) {
              if (ctx.mounted) snack(ctx, '$e');
            }
          },
        ),
      ),
    );
  }
}
