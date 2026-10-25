import 'package:flutter/material.dart';

import 'api.dart';
import 'common.dart';
import 'widgets.dart';

enum _GoalAction { addMoney, delete }

class GoalsScreen extends StatelessWidget {
  const GoalsScreen({super.key});

  Future<void> _add(BuildContext context) async {
    final app = AppScope.read(context);
    final saved = await showFormSheet(
      context,
      title: 'New savings goal',
      subtitle: 'Money you put towards a goal comes out of your balance.',
      fields: const [
        Field('name', 'Name'),
        Field('target', 'Target amount', numeric: true, money: true),
      ],
      onSubmit: (v) async {
        final target = double.tryParse(v['target']!);
        final errors = <String, String>{
          if (v['name']!.isEmpty) 'name': 'Name your goal, for example Laptop',
          if (target == null || target <= 0) 'target': 'Enter an amount above 0',
        };
        if (errors.isNotEmpty) return errors;
        try {
          await Api.addGoal(v['name']!, target!);
          return null;
        } on ApiException catch (e) {
          return {formError: e.message};
        }
      },
    );
    if (saved) app.changed();
  }

  Future<void> _contribute(BuildContext context, Map<String, dynamic> g) async {
    final app = AppScope.read(context);
    double? added;
    final saved = await showFormSheet(
      context,
      title: 'Add to ${g['name']}',
      subtitle: 'This comes out of your balance.',
      fields: const [Field('amount', 'Amount', numeric: true, money: true)],
      onSubmit: (v) async {
        final a = double.tryParse(v['amount']!);
        if (a == null || a <= 0) return {'amount': 'Enter an amount above 0'};
        try {
          await Api.contribute(g['id'] as int, a);
          added = a;
          return null;
        } on ApiException catch (e) {
          return {formError: e.message};
        }
      },
    );
    if (!saved) return;
    app.changed();
    if (context.mounted) snack(context, 'Added ${money(added!)} to ${g['name']}');
  }

  Future<void> _delete(BuildContext context, Map<String, dynamic> g) async {
    final app = AppScope.read(context);
    final ok = await confirm(
      context,
      'Delete ${g['name']}?',
      'The ${money(g['saved'] as num)} saved towards it goes back into your balance.',
      'Delete goal',
    );
    if (!ok) return;
    try {
      await Api.deleteGoal(g['id'] as int);
      app.changed();
    } catch (e) {
      if (context.mounted) snack(context, '$e', tone: SnackTone.alert);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Scaffold(
      body: Loader<List<dynamic>>(
        loadKey: app.tick,
        load: Api.goals,
        builder: (ctx, all, reload) {
          final rows = all.cast<Map<String, dynamic>>();
          if (rows.isEmpty) {
            return const EmptyState(
              icon: Icons.savings_outlined,
              title: 'No savings goals yet',
              message: 'Tap Add goal to set money aside for something you want. Contributions come out of your balance.',
            );
          }
          return RefreshIndicator(
            onRefresh: reload,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(0, 8, 0, 96),
              children: [
                for (final g in rows)
                  _GoalRow(
                    g,
                    onTap: () => _contribute(context, g),
                    onMenu: (a) => switch (a) {
                      _GoalAction.addMoney => _contribute(context, g),
                      _GoalAction.delete => _delete(context, g),
                    },
                  ),
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(context),
        icon: const Icon(Icons.add),
        label: const Text('Add goal'),
      ),
    );
  }
}

class _GoalRow extends StatelessWidget {
  final Map<String, dynamic> g;
  final VoidCallback onTap;
  final void Function(_GoalAction) onMenu;
  const _GoalRow(this.g, {required this.onTap, required this.onMenu});

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final saved = (g['saved'] as num).toDouble();
    final target = (g['target'] as num).toDouble();
    final reached = saved >= target;
    final percent = (saved / target * 100).floor();
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(left: 16, right: 4, top: 12, bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(g['name'] as String, style: t.titleSmall)),
            PopupMenuButton<_GoalAction>(
              tooltip: 'Options for ${g['name']}',
              onSelected: onMenu,
              itemBuilder: (_) => const [
                PopupMenuItem(value: _GoalAction.addMoney, child: Text('Add money')),
                PopupMenuItem(value: _GoalAction.delete, child: Text('Delete goal')),
              ],
            ),
          ]),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: RouteLine(fill: saved, total: target, station: target, color: s.primary),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Row(children: [
              if (reached) ...[
                Icon(Icons.check_circle, size: 16, color: s.primary),
                const SizedBox(width: 6),
                Flexible(
                  child: Text('Goal reached: ${money(saved)} of ${money(target)}',
                      style: t.bodySmall!.copyWith(color: s.primary, fontWeight: FontWeight.w600)),
                ),
              ] else
                Flexible(
                  child: Text('${money(saved)} of ${money(target)} · $percent% · ${money(target - saved)} to go',
                      style: t.bodySmall!.copyWith(color: s.onSurfaceVariant)),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}
