import 'package:flutter/material.dart';
import 'api.dart';
import 'common.dart';

class BudgetsScreen extends StatelessWidget {
  const BudgetsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final month = monthKey(DateTime.now());
    return Loader<List<dynamic>>(
      load: () => Api.budgets(month),
      builder: (ctx, rows, reload) => Scaffold(
        body: rows.isEmpty
            ? Center(child: Text('No budgets set for $month'))
            : ListView(children: [
                for (final b in rows.cast<Map<String, dynamic>>())
                  ListTile(
                    title: Text(b['category'] as String),
                    trailing: Text(money(b['cap'])),
                    onTap: () => _edit(ctx, month, reload, b['category'] as String, '${b['cap']}'),
                  ),
              ]),
        floatingActionButton: FloatingActionButton(
            onPressed: () => _edit(ctx, month, reload, '', ''), child: const Icon(Icons.add)),
      ),
    );
  }

  Future<void> _edit(BuildContext context, String month, Future<void> Function() reload,
      String category, String cap) async {
    final v = await promptFields(context, 'Budget for $month', [
      Field('category', 'Category', initial: category),
      Field('cap', 'Monthly cap', numeric: true, initial: cap),
    ]);
    if (v == null) return;
    final c = double.tryParse(v['cap']!);
    if (c == null || c < 0 || v['category']!.isEmpty) {
      if (context.mounted) snack(context, 'Category and a valid cap are required');
      return;
    }
    try {
      await Api.setBudget(v['category']!, month, c);
      await reload();
    } catch (e) {
      if (context.mounted) snack(context, '$e');
    }
  }
}
