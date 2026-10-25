import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';

// ---------------------------------------------------------------- formatting

String monthKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}';

String dateKey(DateTime d) =>
    '${monthKey(d)}-${d.day.toString().padLeft(2, '0')}';

const _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];
const _monthShort = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec'
];
const _weekdayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String monthLabel(DateTime d) => '${_monthNames[d.month - 1]} ${d.year}';

/// "Today", "Yesterday" or "Sat, 24 Oct" for an ISO date (YYYY-MM-DD).
String dayLabel(String iso, {DateTime? now}) {
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  final today = now ?? DateTime.now();
  final a = DateTime(d.year, d.month, d.day);
  final b = DateTime(today.year, today.month, today.day);
  final diff = b.difference(a).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  return '${_weekdayShort[d.weekday - 1]}, ${d.day} ${_monthShort[d.month - 1]}';
}

String shortDate(String iso) {
  final d = DateTime.tryParse(iso);
  return d == null ? iso : '${d.day} ${_monthShort[d.month - 1]}';
}

String _grouped(int n) {
  final s = n.toString();
  if (s.length <= 3) return s;
  var rest = s.substring(0, s.length - 3);
  final parts = <String>[];
  while (rest.length > 2) {
    parts.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  if (rest.isNotEmpty) parts.insert(0, rest);
  return '${parts.join(',')},${s.substring(s.length - 3)}';
}

/// Rupees with Indian digit grouping; paise only when there are any: ₹1,50,000 / ₹4,226.50.
String money(num v) {
  final paise = (v.abs() * 100).round();
  final rupees = paise ~/ 100;
  final p = paise % 100;
  final body =
      _grouped(rupees) + (p == 0 ? '' : '.${p.toString().padLeft(2, '0')}');
  return '${v < 0 && paise != 0 ? '−' : ''}₹$body';
}

String titleCase(String s) => s.isEmpty
    ? s
    : s
        .split(' ')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');

// ----------------------------------------------------------------- app state

/// The month being viewed (shared by Dashboard, Expenses, Budgets, Recurring)
/// and a counter that screens watch to reload after any change.
class AppState extends ChangeNotifier {
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
  int tick = 0;

  String get key => monthKey(month);

  void shiftMonth(int delta) {
    month = DateTime(month.year, month.month + delta);
    notifyListeners();
  }

  /// Call after any create/update/delete so visible screens reload.
  void changed() {
    tick++;
    notifyListeners();
  }
}

class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
      : super(notifier: state);

  /// Watches the state: the caller rebuilds when the month or data tick changes.
  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  /// Reads the state without subscribing (for use in callbacks).
  static AppState read(BuildContext context) =>
      (context.getElementForInheritedWidgetOfExactType<AppScope>()!.widget
              as AppScope)
          .notifier!;
}

// ------------------------------------------------------------------- snacks

enum SnackTone { neutral, warning, alert }

void snack(BuildContext c, String msg,
    {SnackTone tone = SnackTone.neutral,
    String? action,
    VoidCallback? onAction,
    int seconds = 4}) {
  final s = Theme.of(c).colorScheme;
  final (bg, fg, icon) = switch (tone) {
    SnackTone.alert => (
        s.errorContainer,
        s.onErrorContainer,
        Icons.error_outline
      ),
    SnackTone.warning => (
        s.tertiaryContainer,
        s.onTertiaryContainer,
        Icons.warning_amber_rounded
      ),
    SnackTone.neutral => (null, null, null),
  };
  final m = ScaffoldMessenger.of(c);
  m.clearSnackBars();
  m.showSnackBar(SnackBar(
    backgroundColor: bg,
    duration: Duration(seconds: seconds),
    content: Row(children: [
      if (icon != null) ...[Icon(icon, color: fg), const SizedBox(width: 12)],
      Expanded(
          child: Text(msg, style: fg == null ? null : TextStyle(color: fg))),
    ]),
    action: action == null
        ? null
        : SnackBarAction(
            label: action,
            textColor: fg == null ? null : s.primary,
            onPressed: onAction ?? () {}),
  ));
}

Future<bool> confirm(
    BuildContext context, String title, String body, String action) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: TextButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error),
          child: Text(action),
        ),
      ],
    ),
  );
  return r ?? false;
}

// -------------------------------------------------------------------- loader

/// Loads data and renders it. Reloads when [loadKey] changes, keeping the old
/// data on screen (with a thin progress line); drops it when [resetKey] changes.
class Loader<T> extends StatefulWidget {
  final Future<T> Function() load;
  final Object? loadKey;
  final Object? resetKey;
  final Widget Function(BuildContext, T, Future<void> Function() reload)
      builder;
  const Loader(
      {super.key,
      required this.load,
      required this.builder,
      this.loadKey,
      this.resetKey});

  @override
  State<Loader<T>> createState() => _LoaderState<T>();
}

class _LoaderState<T> extends State<Loader<T>> {
  T? _data;
  bool _has = false;
  Object? _error;
  bool _loading = true;
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    _start(notify: false);
  }

  @override
  void didUpdateWidget(covariant Loader<T> old) {
    super.didUpdateWidget(old);
    if (old.resetKey != widget.resetKey) {
      _has = false;
      _data = null;
      _error = null;
    }
    if (old.loadKey != widget.loadKey || old.resetKey != widget.resetKey) {
      _start(notify: false);
    }
  }

  Future<void> _start({required bool notify}) async {
    final gen = ++_gen;
    if (notify) {
      setState(() => _loading = true);
    } else {
      _loading = true;
    }
    try {
      final d = await widget.load();
      if (!mounted || gen != _gen) return;
      setState(() {
        _data = d;
        _has = true;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || gen != _gen) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _reload() => _start(notify: true);

  @override
  Widget build(BuildContext context) {
    if (!_has) {
      if (_error != null) return ErrorState(onRetry: _reload);
      return const Center(child: CircularProgressIndicator());
    }
    return Column(children: [
      SizedBox(
          height: 3,
          child: _loading ? const LinearProgressIndicator(minHeight: 3) : null),
      if (_error != null)
        Material(
          color: Theme.of(context).colorScheme.errorContainer,
          child: ListTile(
            dense: true,
            leading: Icon(Icons.cloud_off,
                color: Theme.of(context).colorScheme.onErrorContainer),
            title: Text('Could not refresh. Showing the last data.',
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer)),
            trailing:
                TextButton(onPressed: _reload, child: const Text('Retry')),
          ),
        ),
      Expanded(child: widget.builder(context, _data as T, _reload)),
    ]);
  }
}

class ErrorState extends StatelessWidget {
  final Future<void> Function() onRetry;
  const ErrorState({super.key, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.cloud_off, size: 48, color: s.outline),
          const SizedBox(height: 16),
          Text('Could not reach the server',
              style: t.titleMedium, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(
              'Check that the backend is running and that you are online.\n${baseUrl.isEmpty ? 'This server' : baseUrl}',
              style: t.bodyMedium!.copyWith(color: s.onSurfaceVariant),
              textAlign: TextAlign.center),
          const SizedBox(height: 24),
          FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry')),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------- form sheet

class Field {
  final String key;
  final String label;
  final bool numeric;
  final bool money;
  final String initial;
  final String? helper;
  final bool readOnly;
  const Field(this.key, this.label,
      {this.numeric = false,
      this.money = false,
      this.initial = '',
      this.helper,
      this.readOnly = false});
}

/// Key under which [showFormSheet]'s submit callback reports a whole-form error.
const formError = '_';

/// Bottom sheet with one text field per [Field]. [onSubmit] gets the trimmed
/// values and returns null on success (the sheet closes), or a map of field key
/// to message (use [formError] for a message not tied to a field), which is
/// shown in the sheet so the user can correct it. Resolves true on success.
Future<bool> showFormSheet(
  BuildContext context, {
  required String title,
  String? subtitle,
  required List<Field> fields,
  String submit = 'Save',
  required Future<Map<String, String>?> Function(Map<String, String> values)
      onSubmit,
}) async {
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => _FormSheet(
        title: title,
        subtitle: subtitle,
        fields: fields,
        submit: submit,
        onSubmit: onSubmit),
  );
  return ok ?? false;
}

class _FormSheet extends StatefulWidget {
  final String title;
  final String? subtitle;
  final List<Field> fields;
  final String submit;
  final Future<Map<String, String>?> Function(Map<String, String>) onSubmit;
  const _FormSheet(
      {required this.title,
      this.subtitle,
      required this.fields,
      required this.submit,
      required this.onSubmit});

  @override
  State<_FormSheet> createState() => _FormSheetState();
}

class _FormSheetState extends State<_FormSheet> {
  late final Map<String, TextEditingController> _c = {
    for (final f in widget.fields)
      f.key: TextEditingController(text: f.initial),
  };
  Map<String, String> _errors = {};
  bool _busy = false;

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _errors = {};
    });
    Map<String, String>? errors;
    try {
      errors = await widget
          .onSubmit({for (final e in _c.entries) e.key: e.value.text.trim()});
    } catch (e) {
      errors = {formError: '$e'};
    }
    if (!mounted) return;
    if (errors == null || errors.isEmpty) {
      Navigator.pop(context, true);
    } else {
      setState(() {
        _busy = false;
        _errors = errors!;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 4, 20, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.title, style: t.titleLarge),
              if (widget.subtitle != null) ...[
                const SizedBox(height: 4),
                Text(widget.subtitle!,
                    style: t.bodyMedium!.copyWith(color: s.onSurfaceVariant)),
              ],
              const SizedBox(height: 16),
              for (var i = 0; i < widget.fields.length; i++) ...[
                _field(widget.fields[i],
                    first: i == 0, last: i == widget.fields.length - 1),
                const SizedBox(height: 12),
              ],
              if (_errors[formError] != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: s.errorContainer,
                      borderRadius: BorderRadius.circular(12)),
                  child: Row(children: [
                    Icon(Icons.error_outline, color: s.onErrorContainer),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Text(_errors[formError]!,
                            style: t.bodyMedium!
                                .copyWith(color: s.onErrorContainer))),
                  ]),
                ),
                const SizedBox(height: 12),
              ],
              const SizedBox(height: 4),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                TextButton(
                    onPressed:
                        _busy ? null : () => Navigator.pop(context, false),
                    child: const Text('Cancel')),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.5))
                      : Text(widget.submit),
                ),
              ]),
            ]),
      ),
    );
  }

  Widget _field(Field f, {required bool first, required bool last}) {
    return TextField(
      controller: _c[f.key],
      autofocus: first && !f.readOnly,
      readOnly: f.readOnly,
      enabled: !f.readOnly,
      textInputAction: last ? TextInputAction.done : TextInputAction.next,
      onSubmitted: last ? (_) => _submit() : null,
      keyboardType: f.numeric
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      inputFormatters: f.numeric
          ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))]
          : null,
      textCapitalization:
          f.numeric ? TextCapitalization.none : TextCapitalization.words,
      decoration: InputDecoration(
        labelText: f.label,
        helperText: f.helper,
        helperMaxLines: 3,
        errorText: _errors[f.key],
        prefixText: f.money ? '₹ ' : null,
      ),
    );
  }
}
