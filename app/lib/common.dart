import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'api.dart';
import 'theme.dart';
import 'ui.dart';

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

  /// Index of the open section (0 Dashboard, 1 Expenses, 2 Budgets, 3 Recurring, 4 Goals).
  int tab = 0;

  void goTo(int i) {
    if (i == tab) return;
    tab = i;
    notifyListeners();
  }

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
  final k = c.tk;
  const base = Color(0xFF0B0D1A);
  final (bg, fg, icon) = switch (tone) {
    SnackTone.alert => (
        Color.alphaBlend(k.missSoft, base),
        k.miss,
        Icons.error_outline
      ),
    SnackTone.warning => (
        Color.alphaBlend(k.amberSoft, base),
        k.amber,
        Icons.warning_amber_rounded
      ),
    SnackTone.neutral => (base, k.ink, null),
  };
  final m = ScaffoldMessenger.of(c);
  m.clearSnackBars();
  m.showSnackBar(SnackBar(
    backgroundColor: bg,
    shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
            color: tone == SnackTone.neutral
                ? k.line2
                : fg.withValues(alpha: 0.4))),
    duration: Duration(seconds: seconds),
    content: Row(children: [
      if (icon != null) ...[Icon(icon, color: fg), const SizedBox(width: 12)],
      Expanded(child: Text(msg, style: TextStyle(color: fg))),
    ]),
    action: action == null
        ? null
        : SnackBarAction(
            label: action, textColor: k.link, onPressed: onAction ?? () {}),
  ));
}

/// A small dialog in the app's own style. Resolves true on the confirm button.
Future<bool> confirm(
    BuildContext context, String title, String body, String action) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => DialogShell(
      title: title,
      subtitle: body,
      actions: [
        Btn('Cancel',
            kind: BtnKind.ghost, onPressed: () => Navigator.pop(ctx, false)),
        Btn(action,
            kind: BtnKind.danger, onPressed: () => Navigator.pop(ctx, true)),
      ],
      children: const [],
    ),
  );
  return r ?? false;
}

class DialogShell extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> children;
  final List<Widget> actions;
  const DialogShell(
      {super.key,
      required this.title,
      this.subtitle,
      required this.children,
      required this.actions});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final k = context.tk;
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                  header: true,
                  container: true,
                  child: Text(title, style: t.titleLarge)),
              if (subtitle != null) ...[
                const SizedBox(height: 6),
                Text(subtitle!, style: t.bodyMedium!.copyWith(color: k.ink2)),
              ],
              if (children.isNotEmpty) const SizedBox(height: 18),
              ...children,
              const SizedBox(height: 22),
              Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: actions),
            ],
          ),
        ),
      ),
    );
  }
}

// -------------------------------------------------------------------- loader

/// How long to keep trying while a sleeping server (free hosting) wakes up.
class WakePolicy {
  static List<Duration> delays = const [
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 6),
    Duration(seconds: 8),
    Duration(seconds: 10),
    Duration(seconds: 12),
  ];
}

/// True for failures that mean "the server is not answering yet": a network
/// error or timeout, or a gateway error from a host that is still starting up.
bool isServerAsleep(Object e) {
  if (e is ApiException) return const [502, 503, 504].contains(e.status);
  return e is http.ClientException || e is TimeoutException;
}

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
  bool _waking = false;
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
      setState(() {
        _loading = true;
        _error = null;
      });
    } else {
      _loading = true;
    }
    for (var attempt = 0;; attempt++) {
      try {
        final d = await widget.load();
        if (!mounted || gen != _gen) return;
        setState(() {
          _data = d;
          _has = true;
          _error = null;
          _loading = false;
          _waking = false;
        });
        return;
      } catch (e) {
        if (!mounted || gen != _gen) return;
        if (isServerAsleep(e) && attempt < WakePolicy.delays.length) {
          setState(() => _waking = true);
          await Future<void>.delayed(WakePolicy.delays[attempt]);
          if (!mounted || gen != _gen) return;
          continue;
        }
        setState(() {
          _error = e;
          _loading = false;
          _waking = false;
        });
        return;
      }
    }
  }

  Future<void> _reload() => _start(notify: true);

  @override
  Widget build(BuildContext context) {
    if (!_has) {
      if (_waking) return const WakingPanel();
      if (_error != null) return ErrorState(onRetry: _reload);
      return const Center(child: CircularProgressIndicator());
    }
    return Column(children: [
      SizedBox(
          height: 3,
          child: _loading ? const LinearProgressIndicator(minHeight: 3) : null),
      if (_error != null)
        const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Alert('Could not refresh. Showing the last data you loaded.',
              icon: Icons.cloud_off),
        ),
      Expanded(child: widget.builder(context, _data as T, _reload)),
    ]);
  }
}

/// Shown while a sleeping server is starting.
class WakingPanel extends StatelessWidget {
  const WakingPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final k = context.tk;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Panel(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 3)),
            const SizedBox(height: 18),
            Text('Waking up the server…',
                style: t.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(
                'Free hosting sleeps when nobody is using it. The first load can take up to a minute.',
                style: t.bodyMedium!.copyWith(color: k.ink2),
                textAlign: TextAlign.center),
          ]),
        ),
      ),
    );
  }
}

class ErrorState extends StatelessWidget {
  final Future<void> Function() onRetry;
  const ErrorState({super.key, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final k = context.tk;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Panel(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.cloud_off, size: 40, color: k.ink3),
            const SizedBox(height: 14),
            Text('Could not reach the server',
                style: t.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(
                baseUrl.isEmpty
                    ? 'Check that you are online and try again.'
                    : 'Check that the backend is running at $baseUrl and that you are online.',
                style: t.bodyMedium!.copyWith(color: k.ink2),
                textAlign: TextAlign.center),
            const SizedBox(height: 20),
            Btn('Retry', icon: Icons.refresh, onPressed: onRetry),
          ]),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- form dialog

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

/// Key under which [showFormDialog]'s submit callback reports a whole-form error.
const formError = '_';

/// A dialog with one labelled input per [Field]. [onSubmit] gets the trimmed
/// values and returns null on success (the dialog closes), or a map of field
/// key to message (use [formError] for a message not tied to a field), which is
/// shown so the user can correct it. Resolves true on success.
Future<bool> showFormDialog(
  BuildContext context, {
  required String title,
  String? subtitle,
  required List<Field> fields,
  String submit = 'Save',
  required Future<Map<String, String>?> Function(Map<String, String> values)
      onSubmit,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => _FormDialog(
        title: title,
        subtitle: subtitle,
        fields: fields,
        submit: submit,
        onSubmit: onSubmit),
  );
  return ok ?? false;
}

class _FormDialog extends StatefulWidget {
  final String title;
  final String? subtitle;
  final List<Field> fields;
  final String submit;
  final Future<Map<String, String>?> Function(Map<String, String>) onSubmit;
  const _FormDialog(
      {required this.title,
      this.subtitle,
      required this.fields,
      required this.submit,
      required this.onSubmit});

  @override
  State<_FormDialog> createState() => _FormDialogState();
}

class _FormDialogState extends State<_FormDialog> {
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
    final fields = widget.fields;
    return DialogShell(
      title: widget.title,
      subtitle: widget.subtitle,
      actions: [
        Btn('Cancel',
            kind: BtnKind.ghost,
            onPressed: _busy ? null : () => Navigator.pop(context, false)),
        Btn(widget.submit, busy: _busy, onPressed: _submit),
      ],
      children: [
        for (var i = 0; i < fields.length; i++) ...[
          LabeledField(
            fields[i].label,
            _c[fields[i].key]!,
            autofocus: i == 0,
            numeric: fields[i].numeric,
            money: fields[i].money,
            readOnly: fields[i].readOnly,
            helper: fields[i].helper,
            error: _errors[fields[i].key],
            capitalization: fields[i].numeric
                ? TextCapitalization.none
                : TextCapitalization.words,
            action: i == fields.length - 1
                ? TextInputAction.done
                : TextInputAction.next,
            onSubmitted: i == fields.length - 1 ? (_) => _submit() : null,
          ),
          const SizedBox(height: 14),
        ],
        if (_errors[formError] != null)
          Alert(_errors[formError]!, icon: Icons.error_outline),
      ],
    );
  }
}
