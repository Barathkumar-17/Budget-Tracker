import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'common.dart';
import 'theme.dart';
import 'widgets.dart';

/// Opens the add-expense page and reports the outcome (overspend / low balance).
Future<void> addExpense(BuildContext context) async {
  final app = AppScope.read(context);
  final r = await Navigator.of(context).push<Map<String, dynamic>>(
    MaterialPageRoute(
        fullscreenDialog: true, builder: (_) => const AddExpensePage()),
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
    snack(context,
        'Added ${titleCase(e['category'] as String)} ${money(e['amount'] as num)}$where');
  } else {
    snack(context, parts.join('\n'),
        tone: alert != null ? SnackTone.alert : SnackTone.warning, seconds: 6);
  }
}

class AddExpensePage extends StatefulWidget {
  const AddExpensePage({super.key});

  @override
  State<AddExpensePage> createState() => _AddExpensePageState();
}

class _AddExpensePageState extends State<AddExpensePage> {
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
    final amount = double.tryParse(_amount.text.trim());
    final category = _category.text.trim();
    setState(() {
      _formError = null;
      _amountError =
          (amount == null || amount <= 0) ? 'Enter an amount above 0' : null;
      _categoryError = category.isEmpty ? 'Pick or type a category' : null;
    });
    if (_amountError != null || _categoryError != null) return;
    setState(() => _busy = true);
    try {
      final r = await Api.addExpense(
          amount!, dateKey(_date), category, _note.text.trim());
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
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
          title: const Text('Add expense'), leading: const CloseButton()),
      body: Column(children: [
        Expanded(
          child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
              children: [
                TextField(
                  controller: _amount,
                  autofocus: true,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
                  ],
                  textInputAction: TextInputAction.next,
                  style:
                      amountStyle(context, size: 32, weight: FontWeight.w700),
                  decoration: InputDecoration(
                    labelText: 'Amount',
                    prefixText: '₹ ',
                    prefixStyle: amountStyle(context,
                        size: 32,
                        weight: FontWeight.w700,
                        color: s.onSurfaceVariant),
                    errorText: _amountError,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _category,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                      labelText: 'Category', errorText: _categoryError),
                  onChanged: (_) => setState(() => _categoryError = null),
                ),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 0, children: [
                  for (final c in _suggestions)
                    ChoiceChip(
                      label: Text(c),
                      avatar: CategoryDot(c, size: 10),
                      showCheckmark: false,
                      selected: _category.text.trim().toLowerCase() ==
                          c.toLowerCase(),
                      onSelected: (_) => setState(() {
                        _category.text = c;
                        _categoryError = null;
                      }),
                    ),
                ]),
                const SizedBox(height: 16),
                InkWell(
                  onTap: _pickDate,
                  borderRadius: BorderRadius.circular(12),
                  child: InputDecorator(
                    decoration: const InputDecoration(
                        labelText: 'Date',
                        suffixIcon: Icon(Icons.calendar_today_outlined)),
                    child: Text(
                      '${dayLabel(dateKey(_date))} · ${shortDate(dateKey(_date))} ${_date.year}',
                      style: t.bodyLarge,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _note,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.done,
                  decoration:
                      const InputDecoration(labelText: 'Note (optional)'),
                  onSubmitted: (_) => _submit(),
                ),
                if (_formError != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: s.errorContainer,
                        borderRadius: BorderRadius.circular(12)),
                    child: Row(children: [
                      Icon(Icons.error_outline, color: s.onErrorContainer),
                      const SizedBox(width: 12),
                      Expanded(
                          child: Text(_formError!,
                              style: t.bodyMedium!
                                  .copyWith(color: s.onErrorContainer))),
                    ]),
                  ),
                ],
              ]),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.5))
                    : const Text('Save'),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  /// Rows swiped away: hidden at once so the Dismissible leaves the tree in the same frame.
  final _hidden = <int>{};

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

  /// Long-press / accessibility path: ask first (there is no swipe to cancel), then delete with Undo.
  Future<void> _confirmDelete(Map<String, dynamic> e) async {
    final ok = await confirm(
      context,
      'Delete ${titleCase(e['category'] as String)} ${money(e['amount'] as num)}?',
      'You can undo this right after.',
      'Delete',
    );
    if (ok && mounted) await _delete(e);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final key = app.key;
    return Scaffold(
      body: Loader<List<dynamic>>(
        resetKey: key,
        loadKey: app.tick,
        load: () => Api.expenses(key),
        builder: (ctx, all, reload) {
          final rows = all
              .cast<Map<String, dynamic>>()
              .where((e) => !_hidden.contains(e['id']))
              .toList();
          if (rows.isEmpty) {
            return EmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'No expenses in ${monthLabel(app.month)}',
              message:
                  'Tap Add expense to log what you spend. You are warned the moment a purchase goes over a budget.',
            );
          }
          final total =
              rows.fold<double>(0, (a, e) => a + (e['amount'] as num));
          final items = <Widget>[];
          String? current;
          for (var i = 0; i < rows.length; i++) {
            final e = rows[i];
            final date = e['date'] as String;
            if (date != current) {
              current = date;
              final dayTotal = rows
                  .where((r) => r['date'] == date)
                  .fold<double>(0, (a, r) => a + (r['amount'] as num));
              items.add(_DayHeader(label: dayLabel(date), total: dayTotal));
            }
            items.add(_ExpenseRow(e,
                onDelete: () => _delete(e),
                onDeleteConfirmed: () => _confirmDelete(e)));
          }
          return RefreshIndicator(
            onRefresh: reload,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 96),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Text(
                    '${rows.length} ${rows.length == 1 ? 'expense' : 'expenses'} · ${money(total)}',
                    style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ),
                ...items,
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => addExpense(context),
        icon: const Icon(Icons.add),
        label: const Text('Add expense'),
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  final String label;
  final double total;
  const _DayHeader({required this.label, required this.total});

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
      child: Row(children: [
        Expanded(
            child: Semantics(
                header: true,
                child: Text(label,
                    style: t.labelLarge!.copyWith(color: s.onSurfaceVariant)))),
        Text(money(total),
            style: amountStyle(context,
                size: 15, weight: FontWeight.w600, color: s.onSurfaceVariant)),
      ]),
    );
  }
}

class _ExpenseRow extends StatelessWidget {
  final Map<String, dynamic> e;
  final VoidCallback onDelete;
  final VoidCallback onDeleteConfirmed;
  const _ExpenseRow(this.e,
      {required this.onDelete, required this.onDeleteConfirmed});

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final category = e['category'] as String;
    final note = e['note'] as String;
    final recurring = e['recurring_id'] != null;
    return Dismissible(
      key: ValueKey('expense-${e['id']}'),
      direction: DismissDirection.endToStart,
      background: Container(
        color: s.errorContainer,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: Icon(Icons.delete_outline, color: s.onErrorContainer),
      ),
      onDismissed: (_) => onDelete(),
      child: Semantics(
        // Delete without a swipe, for TalkBack, switch and keyboard users.
        customSemanticsActions: {
          const CustomSemanticsAction(label: 'Delete expense'):
              onDeleteConfirmed
        },
        child: InkWell(
          onLongPress: onDeleteConfirmed,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(children: [
                CategoryDot(category),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(titleCase(category), style: t.titleSmall),
                        if (note.isNotEmpty || recurring)
                          Row(children: [
                            if (recurring) ...[
                              Icon(Icons.repeat,
                                  size: 14, color: s.onSurfaceVariant),
                              const SizedBox(width: 4),
                              Text('Recurring',
                                  style: t.bodySmall!
                                      .copyWith(color: s.onSurfaceVariant)),
                              if (note.isNotEmpty)
                                Text(' · ',
                                    style: t.bodySmall!
                                        .copyWith(color: s.onSurfaceVariant)),
                            ],
                            if (note.isNotEmpty)
                              Flexible(
                                child: Text(note,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: t.bodySmall!
                                        .copyWith(color: s.onSurfaceVariant)),
                              ),
                          ]),
                      ]),
                ),
                const SizedBox(width: 12),
                Amount(money(e['amount'] as num),
                    style: amountStyle(context, size: 18)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
