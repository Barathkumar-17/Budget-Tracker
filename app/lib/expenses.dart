import 'package:flutter/material.dart';

import 'api.dart';
import 'common.dart';
import 'theme.dart';
import 'ui.dart';

/// Opens the add-expense dialog (or the edit dialog when [existing] is given)
/// and reports the outcome (overspend / low balance).
Future<void> addExpense(BuildContext context,
    {Map<String, dynamic>? existing}) async {
  final app = AppScope.read(context);
  final r = await showDialog<Map<String, dynamic>>(
    context: context,
    builder: (_) => ExpenseDialog(existing: existing),
  );
  if (r == null || !context.mounted) return;
  app.changed();

  final e = r['expense'] as Map<String, dynamic>;
  final alert = r['alert'] as Map<String, dynamic>?;
  final parts = <String>[
    if (alert != null)
      'Over budget in ${alert['category']} by ${money(alert['over_by'] as num)}',
    if (r['low_balance'] == true)
      'Low balance: ${money(r['balance'] as num)} left, below your ${money(r['low_balance_threshold'] as num)} safety line',
  ];
  if (parts.isEmpty) {
    final month = (e['date'] as String).substring(0, 7);
    final where = month == app.key
        ? ''
        : ' to ${monthLabel(DateTime.parse('$month-01'))}';
    final verb = existing == null ? 'Added' : 'Updated';
    snack(context,
        '$verb ${titleCase(e['category'] as String)} ${money(e['amount'] as num)}$where');
  } else {
    snack(context, parts.join('\n'),
        tone: alert != null ? SnackTone.alert : SnackTone.warning, seconds: 6);
  }
}

class ExpenseDialog extends StatefulWidget {
  /// An expense to edit; null means a new one.
  final Map<String, dynamic>? existing;
  const ExpenseDialog({super.key, this.existing});

  @override
  State<ExpenseDialog> createState() => _ExpenseDialogState();
}

class _ExpenseDialogState extends State<ExpenseDialog> {
  static const _defaults = [
    'Food',
    'Transport',
    'Rent',
    'Fun',
    'Shopping',
    'Bills'
  ];

  final _amount = TextEditingController();
  final _category = TextEditingController();
  final _note = TextEditingController();
  DateTime _date = DateTime.now();
  List<String> _suggestions = _defaults;
  bool _busy = false;
  String? _amountError;
  String? _categoryError;
  String? _formError;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      final amount = (e['amount'] as num).toDouble();
      _amount.text = amount == amount.roundToDouble()
          ? amount.toInt().toString()
          : amount.toString();
      _category.text = titleCase(e['category'] as String);
      _note.text = e['note'] as String;
      _date = DateTime.tryParse(e['date'] as String) ?? _date;
    }
    _loadSuggestions();
  }

  @override
  void dispose() {
    _amount.dispose();
    _category.dispose();
    _note.dispose();
    super.dispose();
  }

  /// This month's categories first, then the usual ones.
  Future<void> _loadSuggestions() async {
    try {
      final d = await Api.dashboard(monthKey(DateTime.now()));
      final used = (d['categories'] as List)
          .map((c) => titleCase(c['category'] as String));
      final all = <String>{...used, ..._defaults}.toList();
      if (mounted) setState(() => _suggestions = all.take(10).toList());
    } catch (_) {
      // Suggestions are a convenience; the defaults stay.
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1, 12, 31),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _submit() async {
    if (_busy) return;
    final amount = double.tryParse(_amount.text.trim());
    final category = _category.text.trim();
    setState(() {
      _formError = null;
      _amountError = amountProblem(amount, 'Enter an amount above 0');
      _categoryError = category.isEmpty ? 'Pick or type a category' : null;
    });
    if (_amountError != null || _categoryError != null) return;
    setState(() => _busy = true);
    try {
      final existing = widget.existing;
      final r = existing == null
          ? await Api.addExpense(
              amount!, dateKey(_date), category, _note.text.trim())
          : await Api.updateExpense(existing['id'] as int, amount!,
              dateKey(_date), category, _note.text.trim());
      if (mounted) Navigator.pop(context, r);
    } on ApiException catch (e) {
      if (mounted) setState(() => _formError = e.message);
    } catch (e) {
      if (mounted) setState(() => _formError = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final k = context.tk;
    final t = Theme.of(context).textTheme;
    final typed = _category.text.trim().toLowerCase();
    return DialogShell(
      title: widget.existing == null ? 'Add expense' : 'Edit expense',
      actions: [
        Btn('Cancel',
            kind: BtnKind.ghost,
            onPressed: _busy ? null : () => Navigator.pop(context)),
        Btn('Save', busy: _busy, onPressed: _submit),
      ],
      children: [
        LabeledField('Amount', _amount,
            numeric: true,
            money: true,
            autofocus: true,
            fontSize: 24,
            error: _amountError,
            action: TextInputAction.next),
        const SizedBox(height: 14),
        LabeledField('Category', _category,
            maxLength: 60,
            error: _categoryError,
            capitalization: TextCapitalization.words,
            action: TextInputAction.next,
            onChanged: (_) => setState(() => _categoryError = null)),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final c in _suggestions)
            _Pill(
              c,
              selected: typed == c.toLowerCase(),
              onTap: () => setState(() {
                _category.text = c;
                _categoryError = null;
              }),
            ),
        ]),
        const SizedBox(height: 14),
        Text('Date', style: t.labelLarge!.copyWith(fontSize: 14.4)),
        const SizedBox(height: 6),
        Semantics(
          button: true,
          label:
              'Date, ${dayLabel(dateKey(_date))} ${shortDate(dateKey(_date))} ${_date.year}',
          excludeSemantics: true,
          onTap: _pickDate,
          child: InkWell(
            onTap: _pickDate,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              decoration: BoxDecoration(
                color: k.paper,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: k.line2, width: 1.5),
              ),
              child: Row(children: [
                Expanded(
                  child: Text(
                      '${dayLabel(dateKey(_date))} · ${shortDate(dateKey(_date))} ${_date.year}',
                      style: t.bodyLarge),
                ),
                Icon(Icons.calendar_today_outlined, size: 18, color: k.ink3),
              ]),
            ),
          ),
        ),
        const SizedBox(height: 14),
        LabeledField('Note (optional)', _note,
            maxLength: 500,
            capitalization: TextCapitalization.sentences,
            action: TextInputAction.done,
            onSubmitted: (_) => _submit()),
        if (_formError != null) ...[
          const SizedBox(height: 14),
          Alert(_formError!, icon: Icons.error_outline),
        ],
      ],
    );
  }
}

/// A suggestion pill; the chosen one is filled.
class _Pill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Pill(this.label, {required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final k = context.tk;
    final c = categoryColor(label, Theme.of(context).brightness);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 6, 13, 6),
          decoration: BoxDecoration(
            color: selected ? k.strong : k.surface2,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: selected ? k.line2 : k.line),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
            const SizedBox(width: 7),
            Text(label,
                style: TextStyle(
                    fontFamily: sans,
                    fontSize: 13.6,
                    fontWeight: FontWeight.w500,
                    color: selected ? Colors.white : k.ink2)),
          ]),
        ),
      ),
    );
  }
}

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  /// Rows removed by the user: hidden at once, before the list reloads.
  final _hidden = <int>{};
  String? _category; // null = all

  Future<void> _delete(Map<String, dynamic> e) async {
    final app = AppScope.read(context);
    final id = e['id'] as int;
    setState(() => _hidden.add(id));
    try {
      await Api.deleteExpense(id);
    } catch (err) {
      if (mounted) {
        setState(() => _hidden.remove(id));
        snack(context, '$err', tone: SnackTone.alert);
      }
      return;
    }
    app.changed();
    if (!mounted) return;
    snack(
      context,
      'Deleted ${titleCase(e['category'] as String)} ${money(e['amount'] as num)}',
      action: 'Undo',
      onAction: () async {
        try {
          await Api.addExpense(
              (e['amount'] as num).toDouble(),
              e['date'] as String,
              e['category'] as String,
              e['note'] as String);
          app.changed();
        } catch (err) {
          if (mounted) snack(context, '$err', tone: SnackTone.alert);
        }
      },
      seconds: 6,
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final key = app.key;
    return Loader<List<dynamic>>(
      resetKey: key,
      loadKey: app.tick,
      load: () => Api.expenses(key),
      builder: (ctx, all, reload) {
        final rows = all
            .cast<Map<String, dynamic>>()
            .where((e) => !_hidden.contains(e['id']))
            .toList();
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
    final wide = isWide(context);
    final head = PageHead(
      eyebrow: 'Ledger',
      title: 'Expenses',
      subtitle: rows.isEmpty
          ? 'Everything you spend in ${monthLabel(app.month)} will be listed here.'
          : 'Everything you spent in ${monthLabel(app.month)}. ${isWide(context) ? 'Click' : 'Tap'} a row to edit it.',
      actions: [
        const MonthSwitcher(),
        Btn('Add expense',
            icon: Icons.add, onPressed: () => addExpense(context)),
      ],
    );
    if (rows.isEmpty) {
      return [
        head,
        EmptyPanel(
          title: 'No expenses in ${monthLabel(app.month)}',
          message:
              'Add what you spend as you spend it. You are warned the moment a purchase goes over a budget.',
          actionLabel: 'Add an expense',
          onAction: () => addExpense(context),
        ),
      ];
    }

    // category totals, biggest first
    final totals = <String, double>{};
    final counts = <String, int>{};
    for (final e in rows) {
      final c = e['category'] as String;
      totals[c] = (totals[c] ?? 0) + (e['amount'] as num);
      counts[c] = (counts[c] ?? 0) + 1;
    }
    final order = totals.keys.toList()
      ..sort((a, b) => totals[b]!.compareTo(totals[a]!));
    final category = order.contains(_category) ? _category : null;
    final shown = category == null
        ? rows
        : rows.where((e) => e['category'] == category).toList();

    final total = rows.fold<double>(0, (a, e) => a + (e['amount'] as num));
    final now = DateTime.now();
    final daysInMonth = DateTime(app.month.year, app.month.month + 1, 0).day;
    final elapsed = (app.month.year == now.year && app.month.month == now.month)
        ? now.day
        : daysInMonth;
    final tabLabels = [
      'All (${rows.length})',
      for (final c in order) '${titleCase(c)} (${counts[c]})',
    ];

    final table = Panel(
      padding: wide
          ? const EdgeInsets.fromLTRB(24, 16, 24, 8)
          : const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(children: [
        if (wide) const _Head(),
        for (var i = 0; i < shown.length; i++)
          _ExpenseRow(
            shown[i],
            first: i == 0,
            wide: wide,
            onEdit: () => addExpense(context, existing: shown[i]),
            onDelete: () => _delete(shown[i]),
          ),
      ]),
    );

    return [
      head,
      StatStrip([
        Stat(
            money(total), 'Spent in ${monthLabel(app.month).split(' ').first}'),
        Stat('${rows.length}', rows.length == 1 ? 'Expense' : 'Expenses'),
        Stat(titleCase(order.first), 'Biggest category'),
        Stat(money(total / elapsed), 'Average per day'),
      ]),
      const SizedBox(height: 20),
      SegTabs(
        labels: tabLabels,
        selected: category == null ? 0 : order.indexOf(category) + 1,
        onChanged: (i) =>
            setState(() => _category = i == 0 ? null : order[i - 1]),
      ),
      const SizedBox(height: 16),
      table,
      if (shown.length != rows.length)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(
              '${shown.length} of ${rows.length} expenses, ${money(shown.fold<double>(0, (a, e) => a + (e['amount'] as num)))} in ${titleCase(category!)}',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall!
                  .copyWith(color: k.ink2)),
        ),
    ];
  }
}

const _colDate = 84.0;
const _colCategory = 160.0;
const _colAmount = 120.0;
const _colActions = 168.0;

class _Head extends StatelessWidget {
  const _Head();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final k = context.tk;
    TextStyle s = t.labelMedium!.copyWith(color: k.ink3);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        SizedBox(width: _colDate, child: Text('Date', style: s)),
        SizedBox(width: _colCategory, child: Text('Category', style: s)),
        Expanded(child: Text('Note', style: s)),
        SizedBox(
            width: _colAmount,
            child: Text('Amount', textAlign: TextAlign.end, style: s)),
        const SizedBox(width: _colActions),
      ]),
    );
  }
}

class _ExpenseRow extends StatelessWidget {
  final Map<String, dynamic> e;
  final bool first;
  final bool wide;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _ExpenseRow(this.e,
      {required this.first,
      required this.wide,
      required this.onEdit,
      required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final k = context.tk;
    final t = Theme.of(context).textTheme;
    final category = e['category'] as String;
    final note = e['note'] as String;
    final recurring = e['recurring_id'] != null;
    final amount = money(e['amount'] as num);
    final what = '${titleCase(category)} $amount';
    final noteWidget = Row(children: [
      if (recurring) ...[
        const Tag('Recurring',
            kind: TagKind.purple, icon: Icons.autorenew_rounded),
        const SizedBox(width: 8),
      ],
      Flexible(
        child: Text(note,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.bodyMedium!.copyWith(color: k.ink2)),
      ),
    ]);
    final actions = Row(mainAxisSize: MainAxisSize.min, children: [
      Btn('Edit',
          kind: BtnKind.ghost,
          small: true,
          semanticLabel: 'Edit $what',
          onPressed: onEdit),
      const SizedBox(width: 6),
      Btn('Remove',
          kind: BtnKind.ghost,
          small: true,
          semanticLabel: 'Remove $what',
          onPressed: onDelete),
    ]);
    return Container(
      decoration: BoxDecoration(
          border: first ? null : Border(top: BorderSide(color: k.line))),
      child: InkWell(
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: wide
              ? Row(children: [
                  SizedBox(
                      width: _colDate,
                      child: Text(shortDate(e['date'] as String),
                          style: t.bodyMedium!.copyWith(color: k.ink2))),
                  SizedBox(
                      width: _colCategory,
                      child: Align(
                          alignment: Alignment.centerLeft,
                          child: CategoryTag(category))),
                  Expanded(child: noteWidget),
                  SizedBox(
                      width: _colAmount,
                      child: Text(amount,
                          textAlign: TextAlign.end,
                          style: t.bodyLarge!
                              .copyWith(fontWeight: FontWeight.w700))),
                  SizedBox(
                      width: _colActions,
                      child: Align(
                          alignment: Alignment.centerRight, child: actions)),
                ])
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                        child: Align(
                            alignment: Alignment.centerLeft,
                            child: CategoryTag(category))),
                    Text(amount,
                        style:
                            t.bodyLarge!.copyWith(fontWeight: FontWeight.w700)),
                  ]),
                  const SizedBox(height: 6),
                  Text(
                      '${dayLabel(e['date'] as String)}${note.isEmpty ? '' : ' · $note'}${recurring ? ' · Recurring' : ''}',
                      style: t.bodySmall),
                  const SizedBox(height: 10),
                  actions,
                ]),
        ),
      ),
    );
  }
}
