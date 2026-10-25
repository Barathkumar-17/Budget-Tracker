import 'package:flutter/material.dart';
import 'api.dart';
import 'common.dart';

class GoalsScreen extends StatelessWidget {
  const GoalsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Loader<List<dynamic>>(
      load: Api.goals,
      builder: (ctx, rows, reload) => Scaffold(
        body: rows.isEmpty
            ? const Center(child: Text('No savings goals yet'))
            : ListView(children: [
                for (final g in rows.cast<Map<String, dynamic>>())
                  ListTile(
                    title: Text(g['name'] as String),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        LinearProgressIndicator(value: (g['progress'] as num).toDouble()),
                        const SizedBox(height: 4),
                        Text('${money(g['saved'])} of ${money(g['target'])}'),
                      ]),
                    ),
                    onTap: () async {
                      final v = await promptFields(ctx, 'Add to "${g['name']}"',
                          [const Field('amount', 'Amount', numeric: true)]);
                      if (v == null) return;
                      final a = double.tryParse(v['amount']!);
                      if (a == null || a <= 0) {
                        if (ctx.mounted) snack(ctx, 'Enter a valid amount');
                        return;
                      }
                      try {
                        await Api.contribute(g['id'] as int, a);
                        await reload();
                      } catch (e) {
                        if (ctx.mounted) snack(ctx, '$e');
                      }
                    },
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        try {
                          await Api.deleteGoal(g['id'] as int);
                        } catch (e) {
                          if (ctx.mounted) snack(ctx, '$e');
                        }
                        await reload();
                      },
                    ),
                  ),
              ]),
        floatingActionButton: FloatingActionButton(
          child: const Icon(Icons.add),
          onPressed: () async {
            final v = await promptFields(ctx, 'New savings goal', [
              const Field('name', 'Name'),
              const Field('target', 'Target amount', numeric: true),
            ]);
            if (v == null) return;
            final t = double.tryParse(v['target']!);
            if (t == null || t <= 0 || v['name']!.isEmpty) {
              if (ctx.mounted) snack(ctx, 'Name and a valid target are required');
              return;
            }
            try {
              await Api.addGoal(v['name']!, t);
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
