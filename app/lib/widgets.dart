import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'common.dart';
import 'theme.dart';

/// The app's one signature element: a rail line. [fill] is the distance
/// travelled, [station] the terminus (a budget cap, a goal target or the
/// safety line) and [total] the full length of the line. When [overrun] is set
/// the part of the line past the station is drawn in the alert colour.
class RouteLine extends StatelessWidget {
  final double fill;
  final double total;
  final double? station;
  final Color color;
  final bool overrun;

  const RouteLine({
    super.key,
    required this.fill,
    required this.total,
    required this.color,
    this.station,
    this.overrun = false,
  });

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final still = MediaQuery.of(context).disableAnimations;
    return ExcludeSemantics(
      child: SizedBox(
        height: 24,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: still ? 1 : 0, end: 1),
          duration: still ? Duration.zero : const Duration(milliseconds: 700),
          curve: Curves.easeOutExpo,
          builder: (context, t, _) => CustomPaint(
            size: Size.infinite,
            painter: _RoutePainter(
              fill: fill,
              total: total,
              station: station,
              color: color,
              track: s.outlineVariant,
              idle: s.onSurfaceVariant,
              alert: alertLineColor(Theme.of(context).brightness),
              ground: s.surface,
              overrun: overrun,
              t: t,
            ),
          ),
        ),
      ),
    );
  }
}

class _RoutePainter extends CustomPainter {
  final double fill, total, t;
  final double? station;
  final Color color, track, idle, alert, ground;
  final bool overrun;

  _RoutePainter({
    required this.fill,
    required this.total,
    required this.station,
    required this.color,
    required this.track,
    required this.idle,
    required this.alert,
    required this.ground,
    required this.overrun,
    required this.t,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 6.0, ring = 8.0, left = 5.0;
    final right = size.width - ring - 2;
    final cy = size.height / 2;
    double x(double v) => left + (right - left) * (total <= 0 ? 0.0 : (v / total).clamp(0.0, 1.0));
    Paint line(Color c) => Paint()
      ..color = c
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(Offset(left, cy), Offset(right, cy), line(track));

    final st = station;
    final travelled = (overrun && st != null) ? math.min(fill, st) : fill;
    final end = left + (x(travelled) - left) * t;
    if (end > left) canvas.drawLine(Offset(left, cy), Offset(end, cy), line(color));

    if (overrun && st != null) {
      final s0 = x(st);
      final e0 = s0 + (x(fill) - s0) * t;
      if (e0 > s0) canvas.drawLine(Offset(s0, cy), Offset(e0, cy), line(alert));
    }

    if (st != null) {
      for (final q in const [0.25, 0.5, 0.75]) {
        canvas.drawCircle(Offset(x(st * q), cy), 1.6, Paint()..color = ground);
      }
      final sx = x(st);
      canvas.drawCircle(Offset(sx, cy), ring, Paint()..color = ground);
      canvas.drawCircle(
        Offset(sx, cy),
        ring - 1.5,
        Paint()
          ..color = overrun ? alert : (fill >= st ? color : idle)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }
    canvas.drawCircle(Offset(left, cy), 4, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _RoutePainter o) =>
      o.fill != fill || o.total != total || o.station != station || o.color != color ||
      o.overrun != overrun || o.t != t || o.track != track || o.ground != ground ||
      o.idle != idle || o.alert != alert;
}

/// One column per day of the month; the busiest day is highlighted.
class SpendColumns extends StatelessWidget {
  final List<Map<String, dynamic>> trend;
  final DateTime month;
  const SpendColumns({super.key, required this.trend, required this.month});

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final days = DateTime(month.year, month.month + 1, 0).day;
    final values = List<double>.filled(days, 0);
    for (final e in trend) {
      final d = DateTime.tryParse(e['date'] as String);
      if (d != null && d.year == month.year && d.month == month.month) {
        values[d.day - 1] = (e['total'] as num).toDouble();
      }
    }
    final maxV = values.reduce(math.max);
    if (maxV <= 0) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text('No spending recorded in ${monthLabel(month)}.',
            style: t.bodyMedium!.copyWith(color: s.onSurfaceVariant)),
      );
    }
    final maxDay = values.indexOf(maxV) + 1;
    final summary = 'Highest day ${money(maxV)} on $maxDay ${monthLabel(month).split(' ').first}';
    final still = MediaQuery.of(context).disableAnimations;
    return Semantics(
      label: 'Daily spending. $summary.',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ExcludeSemantics(child: Text(summary, style: t.bodyMedium!.copyWith(color: s.onSurfaceVariant))),
        const SizedBox(height: 12),
        ExcludeSemantics(
          child: SizedBox(
            height: 112,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: still ? 1 : 0, end: 1),
              duration: still ? Duration.zero : const Duration(milliseconds: 700),
              curve: Curves.easeOutExpo,
              builder: (_, p, __) => CustomPaint(
                size: Size.infinite,
                painter: _ColumnsPainter(values, maxV, s.secondary, s.primary, s.outlineVariant, p),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        ExcludeSemantics(
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('1', style: t.labelSmall!.copyWith(color: s.onSurfaceVariant)),
            Text('${(days / 2).round()}', style: t.labelSmall!.copyWith(color: s.onSurfaceVariant)),
            Text('$days', style: t.labelSmall!.copyWith(color: s.onSurfaceVariant)),
          ]),
        ),
      ]),
    );
  }
}

class _ColumnsPainter extends CustomPainter {
  final List<double> values;
  final double maxV, p;
  final Color bar, peak, axis;
  _ColumnsPainter(this.values, this.maxV, this.bar, this.peak, this.axis, this.p);

  @override
  void paint(Canvas canvas, Size size) {
    final n = values.length;
    const gap = 2.0;
    final w = (size.width - gap * (n - 1)) / n;
    canvas.drawRect(Rect.fromLTWH(0, size.height - 1, size.width, 1), Paint()..color = axis);
    for (var i = 0; i < n; i++) {
      final v = values[i];
      if (v <= 0) continue;
      final h = math.max(3.0, (v / maxV) * (size.height - 6)) * p;
      final r = RRect.fromRectAndCorners(
        Rect.fromLTWH(i * (w + gap), size.height - 1 - h, w, h),
        topLeft: const Radius.circular(2),
        topRight: const Radius.circular(2),
      );
      canvas.drawRRect(r, Paint()..color = v == maxV ? peak : bar);
    }
  }

  @override
  bool shouldRepaint(covariant _ColumnsPainter o) => o.values != values || o.p != p || o.bar != bar;
}

/// A right-aligned amount that wraps instead of overflowing at large text
/// sizes: bounded to under half the screen so the name beside it keeps room.
class Amount extends StatelessWidget {
  final String text;
  final TextStyle style;
  const Amount(this.text, {super.key, required this.style});

  @override
  Widget build(BuildContext context) {
    final maxWidth = math.min(MediaQuery.sizeOf(context).width * 0.45, 220.0);
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Text(text, textAlign: TextAlign.end, style: style),
    );
  }
}

/// Small coloured dot naming a category's line.
class CategoryDot extends StatelessWidget {
  final String category;
  final double size;
  const CategoryDot(this.category, {super.key, this.size = 12});

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: categoryColor(category, Theme.of(context).brightness),
            shape: BoxShape.circle,
          ),
        ),
      );
}

class SectionHeading extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionHeading(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 28, bottom: 8),
      child: Row(children: [
        Expanded(child: Semantics(header: true, child: Text(text, style: Theme.of(context).textTheme.titleMedium))),
        if (trailing != null) trailing!,
      ]),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(32, 32, 32, 96),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 48, color: s.outline),
          const SizedBox(height: 16),
          Text(title, style: t.titleMedium, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(message, style: t.bodyMedium!.copyWith(color: s.onSurfaceVariant), textAlign: TextAlign.center),
          if (actionLabel != null) ...[
            const SizedBox(height: 24),
            FilledButton.tonal(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ]),
      ),
    );
  }
}

/// Month switcher that lives under the title in the navy header.
class MonthBar extends StatelessWidget implements PreferredSizeWidget {
  const MonthBar({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final t = Theme.of(context).textTheme;
    return SizedBox(
      height: 56,
      child: Row(children: [
        const SizedBox(width: 4),
        IconButton(
          tooltip: 'Previous month',
          color: Colors.white,
          onPressed: () => app.shiftMonth(-1),
          icon: const Icon(Icons.chevron_left, size: 28),
        ),
        Expanded(
          child: Semantics(
            liveRegion: true,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                monthLabel(app.month),
                textAlign: TextAlign.center,
                style: t.titleMedium!.copyWith(color: Colors.white),
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: 'Next month',
          color: Colors.white,
          onPressed: () => app.shiftMonth(1),
          icon: const Icon(Icons.chevron_right, size: 28),
        ),
        const SizedBox(width: 4),
      ]),
    );
  }
}
