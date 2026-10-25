import 'package:flutter/material.dart';

import 'api.dart';
import 'common.dart';
import 'theme.dart';
import 'ui.dart';

class GoalsScreen extends StatelessWidget {
  const GoalsScreen({super.key});

  Future<void> _add(BuildContext context) async {
    final app = AppScope.read(context);
    final saved = await showFormDialog(
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
          if (target == null || target <= 0)
            'target': 'Enter an amount above 0',
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
    final saved = await showFormDialog(
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
    if (context.mounted) {
      snack(context, 'Added ${money(added!)} to ${g['name']}');
    }
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
    return Loader<List<dynamic>>(
      loadKey: app.tick,
      load: Api.goals,
      builder: (ctx, all, reload) => RefreshIndicator(
        onRefresh: reload,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(bottom: isWide(context) ? 48 : 112),
          children: _content(context, all.cast<Map<String, dynamic>>()),
        ),
      ),
    );
  }

  List<Widget> _content(BuildContext context, List<Map<String, dynamic>> rows) {
    final head = PageHead(
      eyebrow: 'Savings',
      title: 'Goals',
      subtitle:
          'Money you are setting aside. Contributions come out of your balance.',
      actions: [
        Btn('Add goal', icon: Icons.add, onPressed: () => _add(context))
      ],
    );
    if (rows.isEmpty) {
      return [
        head,
        EmptyPanel(
          title: 'No savings goals yet',
          message:
              'Set money aside for something you want. Contributions come out of your balance.',
          actionLabel: 'Add your first goal',
          onAction: () => _add(context),
        ),
      ];
    }
    final saved = rows.fold<double>(0, (a, g) => a + (g['saved'] as num));
    final target = rows.fold<double>(0, (a, g) => a + (g['target'] as num));
    final reached =
        rows.where((g) => (g['saved'] as num) >= (g['target'] as num)).length;
    final cols = isWide(context) ? 2 : 1;
    return [
      head,
      StatStrip([
        Stat(money(saved), 'Saved so far'),
        Stat(money(target), 'Total target'),
        Stat('${target == 0 ? 0 : (saved / target * 100).floor()}',
            'Overall progress',
            small: '%'),
        Stat('$reached', reached == 1 ? 'Goal reached' : 'Goals reached'),
      ]),
      const SizedBox(height: 20),
      LayoutBuilder(builder: (context, c) {
        final w = (c.maxWidth - (cols - 1) * 20) / cols;
        return Wrap(spacing: 20, runSpacing: 20, children: [
          for (final g in rows)
            SizedBox(
              width: w,
              child: _GoalPanel(
                g,
                onAdd: () => _contribute(context, g),
                onRemove: () => _delete(context, g),
              ),
            ),
        ]);
      }),
    ];
  }
}

class _GoalPanel extends StatelessWidget {
  final Map<String, dynamic> g;
  final VoidCallback onAdd;
  final VoidCallback onRemove;
  const _GoalPanel(this.g, {required this.onAdd, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final k = context.tk;
    final t = Theme.of(context).textTheme;
    final saved = (g['saved'] as num).toDouble();
    final target = (g['target'] as num).toDouble();
    final reached = saved >= target;
    final percent = (saved / target * 100).floor();
    final name = g['name'] as String;
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Ring(
            percent: saved / target * 100,
            size: 84,
            color: reached ? k.match : k.link,
            center: '$percent%',
          ),
          const SizedBox(width: 18),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name,
                  style: t.titleMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              Text('${money(saved)} of ${money(target)}',
                  style: t.bodyMedium!.copyWith(color: k.ink2)),
              const SizedBox(height: 8),
              reached
                  ? const Tag('Goal reached',
                      kind: TagKind.ok, icon: Icons.check_rounded)
                  : Tag('${money(target - saved)} to go', kind: TagKind.cobalt),
            ]),
          ),
        ]),
        const SizedBox(height: 18),
        Wrap(spacing: 8, runSpacing: 8, children: [
          Btn('Add money',
              small: true,
              semanticLabel: 'Add money to $name',
              onPressed: onAdd),
          Btn('Remove',
              kind: BtnKind.ghost,
              small: true,
              semanticLabel: 'Remove $name',
              onPressed: onRemove),
        ]),
      ]),
    );
  }
}
