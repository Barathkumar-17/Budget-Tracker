import 'package:flutter/material.dart';
import 'api.dart';
import 'common.dart';

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});
  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  final DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  Future<void> _add(Future<void> Function() reload) async {
    final v = await promptFields(context, 'Add expense', [
      const Field('amount', 'Amount', numeric: true),
      const Field('category', 'Category'),
      const Field('note', 'Note (optional)'),
      Field('date', 'Date (YYYY-MM-DD)', initial: dateKey(DateTime.now())),
    ]);
    if (v == null) return;
    final amount = double.tryParse(v['amount']!);
    if (amount == null || amount <= 0 || v['category']!.isEmpty) {
      if (mounted) snack(context, 'Amount and category are required');
      return;
    }
    try {
      final r = await Api.addExpense(amount, v['date']!, v['category']!, v['note']!);
      if (mounted) {
        final alert = r['alert'];
        if (alert != null) {
          snack(context, 'Over budget in ${alert['category']} by ${money(alert['over_by'])}');
        } else if (r['low_balance'] == true) {
          snack(context, 'Low balance: ${money(r['balance'])}');
        }
      }
      await reload();
    } catch (e) {
      if (mounted) snack(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Loader<List<dynamic>>(
      load: () => Api.expenses(monthKey(_month)),
      builder: (ctx, rows, reload) => Scaffold(
        body: rows.isEmpty
            ? const Center(child: Text('No expenses this month'))
            : RefreshIndicator(
                onRefresh: reload,
                child: ListView.builder(
                  itemCount: rows.length,
                  itemBuilder: (_, i) {
                    final e = rows[i] as Map<String, dynamic>;
                    return Dismissible(
                      key: ValueKey(e['id']),
                      direction: DismissDirection.endToStart,
                      background: Container(
                          color: Colors.red,
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 16),
                          child: const Icon(Icons.delete, color: Colors.white)),
                      onDismissed: (_) async {
                        try {
                          await Api.deleteExpense(e['id'] as int);
                        } catch (err) {
                          if (context.mounted) snack(context, '$err');
                        }
                        await reload();
                      },
                      child: ListTile(
                        title: Text('${e['category']}  ${money(e['amount'])}'),
                        subtitle: Text(
                            '${e['date']}${(e['note'] as String).isEmpty ? '' : ' · ${e['note']}'}'),
                        trailing: e['recurring_id'] != null
                            ? const Icon(Icons.repeat, size: 18)
                            : null,
                      ),
                    );
                  },
                ),
              ),
        floatingActionButton:
            FloatingActionButton(onPressed: () => _add(reload), child: const Icon(Icons.add)),
      ),
    );
  }
}
