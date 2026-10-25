import 'package:flutter/material.dart';

String monthKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';

String dateKey(DateTime d) =>
    '${monthKey(d)}-${d.day.toString().padLeft(2, '0')}';

String money(num v) => '₹${v.toStringAsFixed(2)}';

void snack(BuildContext c, String msg) =>
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(msg)));

class Field {
  final String key;
  final String label;
  final bool numeric;
  final String initial;
  const Field(this.key, this.label, {this.numeric = false, this.initial = ''});
}

/// Shows a dialog with one text field per [Field]; returns key -> text, or null if cancelled.
Future<Map<String, String>?> promptFields(
    BuildContext context, String title, List<Field> fields) {
  final ctrls = {for (final f in fields) f.key: TextEditingController(text: f.initial)};
  return showDialog<Map<String, String>>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final f in fields)
            TextField(
              controller: ctrls[f.key],
              decoration: InputDecoration(labelText: f.label),
              keyboardType: f.numeric
                  ? const TextInputType.numberWithOptions(decimal: true)
                  : TextInputType.text,
            ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
          onPressed: () =>
              Navigator.pop(ctx, {for (final e in ctrls.entries) e.key: e.value.text.trim()}),
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

/// Loads data with [loader] and renders it; shows an error with retry.
class Loader<T> extends StatefulWidget {
  final Future<T> Function() load;
  final Widget Function(BuildContext, T, Future<void> Function() reload) builder;
  const Loader({super.key, required this.load, required this.builder});

  @override
  State<Loader<T>> createState() => _LoaderState<T>();
}

class _LoaderState<T> extends State<Loader<T>> {
  late Future<T> _f = widget.load();

  Future<void> _reload() async {
    setState(() {
      _f = widget.load();
    });
    try {
      await _f;
    } catch (_) {}
  }

  @override
  void didUpdateWidget(covariant Loader<T> old) {
    super.didUpdateWidget(old);
    _f = widget.load();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: _f,
      builder: (ctx, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('Could not reach the server'),
              const SizedBox(height: 8),
              FilledButton(onPressed: _reload, child: const Text('Retry')),
            ]),
          );
        }
        return widget.builder(ctx, snap.data as T, _reload);
      },
    );
  }
}
