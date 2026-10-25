import 'package:flutter/material.dart';
import 'api.dart';
import 'common.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  void _shift(int delta) =>
      setState(() => _month = DateTime(_month.year, _month.month + delta));

  Future<void> _editAccount(Future<void> Function() reload) async {
    final acc = await Api.account();
    if (!mounted) return;
    final v = await promptFields(context, 'Account', [
      Field('opening', 'Opening balance',
          numeric: true, initial: '${acc['opening_balance']}'),
      Field('threshold', 'Low-balance warning below',
          numeric: true, initial: '${acc['low_balance_threshold']}'),
    ]);
    if (v == null) return;
    final opening = double.tryParse(v['opening']!);
    final threshold = double.tryParse(v['threshold']!);
    if (opening == null || threshold == null) {
      if (mounted) snack(context, 'Enter valid numbers');
      return;
    }
    try {
      await Api.setAccount(opening, threshold);
      await reload();
    } catch (e) {
      if (mounted) snack(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final key = monthKey(_month);
    return Loader<Map<String, dynamic>>(
      key: ValueKey(key),
      load: () => Api.dashboard(key),
      builder: (ctx, d, reload) {
        final cats = (d['categories'] as List).cast<Map<String, dynamic>>();
        final trend = (d['trend'] as List).cast<Map<String, dynamic>>();
        return RefreshIndicator(
          onRefresh: reload,
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              IconButton(onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left)),
              Text(key, style: Theme.of(ctx).textTheme.titleLarge),
              IconButton(onPressed: () => _shift(1), icon: const Icon(Icons.chevron_right)),
            ]),
            Card(
              color: d['low_balance'] == true
                  ? Theme.of(ctx).colorScheme.errorContainer
                  : null,
              child: ListTile(
                title: Text('Balance ${money(d['balance'])}'),
                subtitle: Text(d['low_balance'] == true
                    ? 'Low balance — below ${money(d['low_balance_threshold'])}'
                    : 'Spent this month ${money(d['total_spent'])}'),
                trailing: IconButton(
                    icon: const Icon(Icons.settings), onPressed: () => _editAccount(reload)),
              ),
            ),
            const SizedBox(height: 8),
            Text('Spent vs budget', style: Theme.of(ctx).textTheme.titleMedium),
            if (cats.isEmpty) const Padding(
                padding: EdgeInsets.all(16), child: Text('No expenses or budgets this month')),
            for (final c in cats) _CategoryBar(c),
            const SizedBox(height: 16),
            Text('Daily spend', style: Theme.of(ctx).textTheme.titleMedium),
            SizedBox(
              height: 140,
              child: trend.isEmpty
                  ? const Center(child: Text('No data'))
                  : CustomPaint(
                      painter: _TrendPainter(
                          trend.map((t) => (t['total'] as num).toDouble()).toList(),
                          Theme.of(ctx).colorScheme.primary),
                      size: Size.infinite),
            ),
          ]),
        );
      },
    );
  }
}

class _CategoryBar extends StatelessWidget {
  final Map<String, dynamic> c;
  const _CategoryBar(this.c);

  @override
  Widget build(BuildContext context) {
    final spent = (c['spent'] as num).toDouble();
    final cap = c['cap'] == null ? null : (c['cap'] as num).toDouble();
    final over = c['over'] == true;
    final ratio = cap == null || cap == 0 ? 0.0 : (spent / cap).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(c['category'] as String),
          Text(cap == null ? money(spent) : '${money(spent)} / ${money(cap)}',
              style: TextStyle(color: over ? Colors.red : null)),
        ]),
        const SizedBox(height: 4),
        LinearProgressIndicator(
          value: cap == null ? null : ratio,
          color: over ? Colors.red : null,
        ),
        if (over) const Text('Over budget', style: TextStyle(color: Colors.red, fontSize: 12)),
      ]),
    );
  }
}

class _TrendPainter extends CustomPainter {
  final List<double> values;
  final Color color;
  _TrendPainter(this.values, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final maxV = values.reduce((a, b) => a > b ? a : b);
    final line = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final dot = Paint()..color = color;
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = values.length == 1 ? size.width / 2 : size.width * i / (values.length - 1);
      final y = maxV == 0 ? size.height : size.height - (values[i] / maxV) * (size.height - 8) - 4;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
      canvas.drawCircle(Offset(x, y), 3, dot);
    }
    canvas.drawPath(path, line);
  }

  @override
  bool shouldRepaint(covariant _TrendPainter old) =>
      old.values != values || old.color != color;
}
