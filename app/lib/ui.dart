import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'common.dart';
import 'theme.dart';

/// Below this width the app uses a top bar and a bottom navigation pill.
const kWideBreakpoint = 760.0;

bool isWide(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= kWideBreakpoint;

bool _still(BuildContext context) => MediaQuery.of(context).disableAnimations;

// ------------------------------------------------------------- atmosphere

/// The page behind everything: midnight canvas, a faint blueprint grid that
/// fades towards the edges, and a spotlight beam from the top centre.
class Atmosphere extends StatelessWidget {
  final Widget child;
  const Atmosphere({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      const Positioned.fill(
        child: ExcludeSemantics(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: CustomPaint(painter: _AtmospherePainter()),
            ),
          ),
        ),
      ),
      Positioned.fill(child: child),
    ]);
  }
}

class _AtmospherePainter extends CustomPainter {
  const _AtmospherePainter();

  @override
  void paint(Canvas canvas, Size s) {
    final full = Offset.zero & s;
    canvas.drawRect(full, Paint()..color = Tk.midnight);

    // Spotlight: a conic beam pointing down from the top centre, fading out
    // over the first screenful.
    final beamH = math.min(s.height, 720.0);
    final beam = Rect.fromLTWH(0, 0, s.width, beamH);
    canvas.saveLayer(beam, Paint());
    final centre = Offset(s.width / 2, -beamH * 0.05);
    canvas.drawRect(
      beam,
      Paint()
        ..shader = SweepGradient(
          center: Alignment(0, (centre.dy / beamH) * 2 - 1),
          transform: const GradientRotation(-math.pi / 2),
          colors: const [
            Color(0x00000000),
            Color(0x00000000),
            Color(0x4D7C91B6),
            Color(0x807C91B6),
            Color(0x4D7C91B6),
            Color(0x00000000),
            Color(0x00000000),
          ],
          stops: const [0, 0.45, 0.49, 0.5, 0.51, 0.55, 1],
        ).createShader(Rect.fromCenter(
            center: centre, width: s.width * 2, height: beamH * 2)),
    );
    canvas.drawRect(
      beam,
      Paint()
        ..blendMode = BlendMode.dstIn
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF000000), Color(0x00000000)],
        ).createShader(beam),
    );
    canvas.restore();

    // Blueprint grid.
    canvas.saveLayer(full, Paint());
    final line = Paint()
      ..color = Tk.frostA(0.06)
      ..strokeWidth = 1;
    const cell = 80.0;
    for (var x = 0.0; x <= s.width; x += cell) {
      canvas.drawLine(Offset(x, 0), Offset(x, s.height), line);
    }
    for (var y = 0.0; y <= s.height; y += cell) {
      canvas.drawLine(Offset(0, y), Offset(s.width, y), line);
    }
    canvas.drawRect(
      full,
      Paint()
        ..blendMode = BlendMode.dstIn
        ..shader = RadialGradient(
          center: const Alignment(0, -1),
          radius: 1.1,
          colors: const [Color(0xFF000000), Color(0x00000000)],
          stops: const [0.15, 1],
        ).createShader(full),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _AtmospherePainter o) => false;
}

// ------------------------------------------------------------------- text

/// Headline text filled with the ice-to-sky vertical gradient. Only for the
/// wordmark and the largest headings.
class GradientText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final TextAlign? align;
  const GradientText(this.text, {super.key, this.style, this.align});

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (r) => const LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [Tk.ice, Tk.iceDeep],
      ).createShader(r),
      child: Text(text, textAlign: align, style: style),
    );
  }
}

/// A small all-caps tracked label. [centered] flanks it with lines that fade
/// out, the marker that opens a section.
class Eyebrow extends StatelessWidget {
  final String text;
  final bool centered;
  const Eyebrow(this.text, {super.key, this.centered = false});

  @override
  Widget build(BuildContext context) {
    final k = context.tk;
    final label = Text(
      text.toUpperCase(),
      textAlign: TextAlign.center,
      style: TextStyle(
        fontFamily: mono,
        fontFamilyFallback: const [sans],
        fontSize: 12.5,
        letterSpacing: 1.5,
        height: 1.2,
        color: k.ink3,
      ),
    );
    if (!centered) return label;
    Widget rule(bool left) => Expanded(
          child: Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: left ? Alignment.centerLeft : Alignment.centerRight,
                end: left ? Alignment.centerRight : Alignment.centerLeft,
                colors: [Colors.transparent, k.line2],
              ),
            ),
          ),
        );
    // With large system text the label can be wider than the space: then it
    // wraps on its own, without the lines.
    final measure = TextPainter(
      text: TextSpan(text: text.toUpperCase(), style: label.style),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    return LayoutBuilder(builder: (context, c) {
      if (measure.width + 2 * (16 + 24) + 4 > c.maxWidth) return label;
      return Row(children: [
        rule(true),
        const SizedBox(width: 16),
        label,
        const SizedBox(width: 16),
        rule(false),
      ]);
    });
  }
}

// ------------------------------------------------------------------- logo

class LogoMark extends StatelessWidget {
  final double size;
  const LogoMark({super.key, this.size = 30});

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: CustomPaint(size: Size(size, size), painter: _LogoPainter()),
    );
  }
}

class _LogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final u = s.width / 30;
    final tile = RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, 30 * u, 30 * u), Radius.circular(15 * u));
    canvas.drawRRect(tile, Paint()..color = Tk.frostA(0.08));
    canvas.drawRRect(
        tile,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Tk.frostA(0.24));
    // three rising columns, like a tiny bar chart
    RRect bar(double l, double h) => RRect.fromRectAndRadius(
        Rect.fromLTWH(l * u, (21.5 - h) * u, 3.4 * u, h * u),
        Radius.circular(1.7 * u));
    final fill = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [Tk.ice, Tk.iceDeep],
      ).createShader(Offset.zero & s);
    canvas.drawRRect(bar(8.6, 6), fill);
    canvas.drawRRect(bar(13.3, 9.5), fill);
    canvas.drawRRect(bar(18, 13), fill);
  }

  @override
  bool shouldRepaint(covariant _LogoPainter o) => false;
}

class Logo extends StatelessWidget {
  /// Just the mark, for tight spaces.
  final bool compact;
  const Logo({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final k = context.tk;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      const LogoMark(),
      if (!compact) ...[
        const SizedBox(width: 10),
        Flexible(
            child: Text(
          'Budget Tracker',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium!.copyWith(
              fontSize: 17, color: k.ink2, fontWeight: FontWeight.w500),
        )),
      ],
    ]);
  }
}

class Avatar extends StatelessWidget {
  final String name;
  final double size;
  const Avatar(this.name, {super.key, this.size = 36});

  @override
  Widget build(BuildContext context) {
    final k = context.tk;
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: k.strong,
          shape: BoxShape.circle,
          border: Border.all(color: k.line2),
        ),
        child: Text(
          name.isEmpty ? '?' : name[0].toUpperCase(),
          style: TextStyle(
              fontFamily: display,
              fontWeight: FontWeight.w500,
              fontSize: size * 0.42,
              color: k.ink),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------ layout blocks

/// A glass plate: a faint frost tint, a hairline edge and a bright top edge,
/// as if lit from behind.
class Panel extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;

  /// Nearly opaque midnight with a deeper shadow: dialogs and the sign-in card.
  final bool deep;
  final double radius;
  const Panel(
      {super.key,
      required this.child,
      this.padding = const EdgeInsets.all(24),
      this.deep = false,
      this.radius = 16});

  @override
  Widget build(BuildContext context) {
    final k = context.tk;
    final r = BorderRadius.circular(radius);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: deep ? k.deep : null,
        gradient: deep
            ? null
            : LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Tk.frostA(0.055), Tk.frostA(0.02)],
              ),
        borderRadius: r,
        border: Border.all(color: k.line),
        boxShadow: [
          BoxShadow(
              color: deep ? const Color(0x4D000000) : const Color(0x66000000),
              blurRadius: deep ? 32 : 24,
              offset: Offset(0, deep ? 16 : 12)),
        ],
      ),
      child: Stack(children: [
        SizedBox(
            width: double.infinity,
            child: Padding(padding: padding, child: child)),
        Positioned(
          top: 0,
          left: radius,
          right: radius,
          height: 1,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [
                  Colors.transparent,
                  Color.fromRGBO(216, 236, 248, deep ? 0.3 : 0.2),
                  Colors.transparent,
                ]),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

class PanelTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const PanelTitle(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Row(children: [
          Expanded(
              child: Semantics(
                  header: true,
                  container: true,
                  child: Text(text,
                      style: Theme.of(context).textTheme.titleMedium))),
          if (trailing != null) trailing!,
        ]),
      );
}

/// Eyebrow, page title, one-line explanation and the page's actions.
class PageHead extends StatelessWidget {
  final String title;
  final String? eyebrow;
  final String? subtitle;
  final List<Widget> actions;
  const PageHead(
      {super.key,
      required this.title,
      this.eyebrow,
      this.subtitle,
      this.actions = const []});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final k = context.tk;
    final wide = isWide(context);
    final heading =
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (eyebrow != null) ...[Eyebrow(eyebrow!), const SizedBox(height: 10)],
      Semantics(
        header: true,
        container: true,
        child: Text(title, style: wide ? t.headlineMedium : t.headlineSmall),
      ),
      if (subtitle != null) ...[
        const SizedBox(height: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Text(subtitle!, style: t.bodyLarge!.copyWith(color: k.ink3)),
        ),
      ],
    ]);
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: wide
          ? Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(child: heading),
              if (actions.isNotEmpty) ...[
                const SizedBox(width: 16),
                Wrap(spacing: 8, runSpacing: 8, children: actions),
              ],
            ])
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              heading,
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 16),
                Wrap(spacing: 8, runSpacing: 8, children: actions),
              ],
            ]),
    );
  }
}

class Stat {
  final String value;
  final String? small;
  final String label;
  final Color? color;
  const Stat(this.value, this.label, {this.small, this.color});
}

/// One glass plate divided into figures (not four identical cards).
class StatStrip extends StatelessWidget {
  final List<Stat> stats;
  const StatStrip(this.stats, {super.key});

  @override
  Widget build(BuildContext context) {
    final k = context.tk;
    return Panel(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: LayoutBuilder(builder: (context, c) {
          final perRow = c.maxWidth >= 640 ? stats.length : 2;
          final rows = <Widget>[];
          for (var start = 0; start < stats.length; start += perRow) {
            final slice =
                stats.sublist(start, math.min(start + perRow, stats.length));
            rows.add(IntrinsicHeight(
              child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < perRow; i++)
                      Expanded(
                        child: i < slice.length
                            ? Container(
                                decoration: BoxDecoration(
                                    border: Border(
                                        left: i == 0
                                            ? BorderSide.none
                                            : BorderSide(color: k.line),
                                        top: start == 0
                                            ? BorderSide.none
                                            : BorderSide(color: k.line))),
                                child: _StatCell(slice[i]),
                              )
                            : const SizedBox.shrink(),
                      ),
                  ]),
            ));
          }
          return Column(children: rows);
        }),
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  final Stat s;
  const _StatCell(this.s);

  @override
  Widget build(BuildContext context) {
    final k = context.tk;
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 16, 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text.rich(
              softWrap: false,
              TextSpan(children: [
                TextSpan(
                    text: s.value,
                    style: t.headlineMedium!
                        .copyWith(fontSize: 30, color: s.color ?? k.ink)),
                if (s.small != null)
                  TextSpan(
                      text: s.small,
                      style:
                          t.titleSmall!.copyWith(fontSize: 16, color: k.ink4)),
              ]),
            )),
        const SizedBox(height: 4),
        Text(s.label, style: t.bodySmall!.copyWith(color: k.ink4)),
      ]),
    );
  }
}

// ------------------------------------------------------------------- tags

enum TagKind { cobalt, ok, no, warn, plain, hl, purple }

class Tag extends StatelessWidget {
  final String text;
  final TagKind kind;
  final IconData? icon;
  const Tag(this.text, {super.key, this.kind = TagKind.cobalt, this.icon});

  @override
  Widget build(BuildContext context) {
    final k = context.tk;
    final (bg, fg) = switch (kind) {
      TagKind.cobalt => (k.cobaltSoft, k.ink2),
      TagKind.ok => (k.matchSoft, k.match),
      TagKind.no => (k.missSoft, k.miss),
      TagKind.warn => (k.amberSoft, k.amber),
      TagKind.plain => (k.surface2, k.ink3),
      TagKind.hl => (k.cobaltSoft, k.ink),
      TagKind.purple => (k.purpleSoft, k.purple),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: fg.withValues(alpha: 0.18)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: 4)
        ],
        Flexible(
          child: Text(text,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontFamily: sans,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: fg,
                  height: 1.33)),
        ),
      ]),
    );
  }
}

/// A category's name in its own shade: a tag with a dot.
class CategoryTag extends StatelessWidget {
  final String name;
  const CategoryTag(this.name, {super.key});

  @override
  Widget build(BuildContext context) {
    final k = context.tk;
    final c = categoryColor(name);
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 10, 4),
      decoration: BoxDecoration(
        color: k.cobaltSoft,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: k.line),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 7),
        Flexible(
          child: Text(titleCase(name),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontFamily: sans,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: k.ink2,
                  height: 1.33)),
        ),
      ]),
    );
  }
}

// ------------------------------------------------------------ ring and bars

/// Percentage ring in the status colour.
class Ring extends StatelessWidget {
  final double percent; // 0..100
  final Color color;
  final double size;
  final String center;
  final String? small;
  const Ring({
    super.key,
    required this.percent,
    required this.color,
    required this.center,
    this.small,
    this.size = 132,
  });

  @override
  Widget build(BuildContext context) {
    final k = context.tk;
    final still = _still(context);
    return ExcludeSemantics(
      child: SizedBox(
        width: size,
        height: size,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: still ? 1 : 0, end: 1),
          duration: still ? Duration.zero : const Duration(milliseconds: 700),
          curve: Curves.easeOutCubic,
          builder: (context, t, _) => CustomPaint(
            painter: _RingPainter(
                percent: (percent.clamp(0, 100)) * t,
                color: color,
                track: k.track),
            child: Center(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(
                      text: center,
                      style: TextStyle(
                          fontFamily: display,
                          fontWeight: FontWeight.w500,
                          fontSize: size * 0.17,
                          color: k.ink)),
                  if (small != null)
                    TextSpan(
                        text: small,
                        style: TextStyle(
                            fontFamily: sans,
                            fontWeight: FontWeight.w500,
                            fontSize: size * 0.07,
                            color: k.ink4)),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double percent;
  final Color color, track;
  _RingPainter(
      {required this.percent, required this.color, required this.track});

  @override
  void paint(Canvas canvas, Size s) {
    final stroke = s.width * 0.075;
    final rect = Rect.fromLTWH(
        stroke / 2, stroke / 2, s.width - stroke, s.height - stroke);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = track;
    canvas.drawArc(rect, 0, math.pi * 2, false, base);
    if (percent > 0) {
      canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * percent / 100, false,
          base..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter o) =>
      o.percent != percent || o.color != color || o.track != track;
}

/// Label and figure above a thin rail, with an optional note below.
class BarRow extends StatelessWidget {
  final String label;
  final String trailing;
  final double fraction;
  final Color color;
  final String? why;
  final Widget? leading;
  final Color? whyColor;
  const BarRow({
    super.key,
    required this.label,
    required this.trailing,
    required this.fraction,
    required this.color,
    this.why,
    this.leading,
    this.whyColor,
  });

  @override
  Widget build(BuildContext context) {
    final k = context.tk;
    final t = Theme.of(context).textTheme;
    final still = _still(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        if (leading != null) ...[leading!, const SizedBox(width: 8)],
        Expanded(
            child: Text(label,
                overflow: TextOverflow.ellipsis,
                style: t.bodyMedium!
                    .copyWith(fontWeight: FontWeight.w500, color: k.ink))),
        const SizedBox(width: 12),
        ConstrainedBox(
          constraints:
              BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.5),
          child: Text(trailing,
              textAlign: TextAlign.end,
              style: t.bodyMedium!.copyWith(color: k.ink3)),
        ),
      ]),
      const SizedBox(height: 8),
      ExcludeSemantics(
        child: Container(
          height: 6,
          decoration: BoxDecoration(
              color: k.track, borderRadius: BorderRadius.circular(99)),
          clipBehavior: Clip.antiAlias,
          child: TweenAnimationBuilder<double>(
            tween: Tween(
                begin: still ? fraction.clamp(0, 1) : 0,
                end: fraction.clamp(0, 1).toDouble()),
            duration: still ? Duration.zero : const Duration(milliseconds: 600),
            curve: Curves.easeOut,
            builder: (_, f, __) => Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: f,
                child: Container(
                    decoration: BoxDecoration(
                        color: color, borderRadius: BorderRadius.circular(99))),
              ),
            ),
          ),
        ),
      ),
      if (why != null) ...[
        const SizedBox(height: 6),
        Text(why!,
            style: t.labelSmall!.copyWith(
                fontWeight: FontWeight.w500,
                color: whyColor ?? k.ink4,
                fontSize: 12)),
      ],
    ]);
  }
}

// ------------------------------------------------------------------ buttons

/// primary: the violet action; ghost: a frosted pill; hl: a brighter frosted
/// pill for the most useful secondary action; danger: ember.
enum BtnKind { primary, ghost, hl, danger }

class Btn extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final BtnKind kind;
  final bool small;
  final IconData? icon;
  final bool busy;
  final bool expand;
  final String? tooltip;

  /// Square-ish corners (6px) instead of a pill: the sign-in form's submit.
  final bool squared;

  /// Overrides the spoken name (for repeated buttons such as one Remove per row).
  final String? semanticLabel;
  const Btn(
    this.label, {
    super.key,
    this.onPressed,
    this.kind = BtnKind.primary,
    this.small = false,
    this.icon,
    this.busy = false,
    this.expand = false,
    this.tooltip,
    this.squared = false,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final k = context.tk;
    final shape = RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(squared ? 6 : 999));
    final pad = small
        ? const EdgeInsets.symmetric(horizontal: 14, vertical: 7)
        : EdgeInsets.symmetric(horizontal: squared ? 24 : 20, vertical: 12);
    final size = small ? const Size(0, 34) : const Size(0, 44);
    final textStyle =
        TextStyle(fontFamily: sans, fontWeight: FontWeight.w500, fontSize: 14);
    final child = busy
        ? SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: kind == BtnKind.primary ? Colors.white : k.ink2))
        : Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[
              Icon(icon, size: small ? 16 : 18),
              const SizedBox(width: 8)
            ],
            Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
          ]);

    Widget button;
    switch (kind) {
      case BtnKind.ghost:
      case BtnKind.hl:
        final strong = kind == BtnKind.hl;
        button = OutlinedButton(
          onPressed: busy ? null : onPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            backgroundColor: Tk.frostA(strong ? 0.12 : 0.06),
            disabledForegroundColor: k.ink4,
            side: BorderSide(color: strong ? k.line2 : k.line, width: 1),
            shape: shape,
            padding: pad,
            minimumSize: size,
            textStyle: textStyle,
          ).copyWith(overlayColor: WidgetStatePropertyAll(Tk.frostA(0.10))),
          child: child,
        );
      case BtnKind.danger:
        button = OutlinedButton(
          onPressed: busy ? null : onPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: k.miss,
            backgroundColor: k.missSoft,
            side: BorderSide(color: k.miss.withValues(alpha: 0.4)),
            shape: shape,
            padding: pad,
            minimumSize: size,
            textStyle: textStyle,
          ),
          child: child,
        );
      case BtnKind.primary:
        button = FilledButton(
          onPressed: busy ? null : onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: k.btn,
            foregroundColor: Colors.white,
            disabledBackgroundColor: k.btn.withValues(alpha: 0.5),
            disabledForegroundColor: Colors.white70,
            shape: shape,
            padding: pad,
            minimumSize: size,
            textStyle: textStyle,
            elevation: 0,
          ).copyWith(
              overlayColor:
                  WidgetStatePropertyAll(Colors.white.withValues(alpha: 0.12))),
          child: child,
        );
    }
    if (tooltip != null) button = Tooltip(message: tooltip!, child: button);
    if (semanticLabel != null) {
      button = Semantics(
        container:
            true, // else it merges with the text next to it into one big button
        button: true,
        enabled: onPressed != null && !busy,
        label: semanticLabel,
        excludeSemantics: true,
        onTap: onPressed,
        child: button,
      );
    }
    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

class IconBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool outlined;
  final double size;
  const IconBtn(
      {super.key,
      required this.icon,
      required this.tooltip,
      required this.onPressed,
      this.outlined = false,
      this.size = 36});

  @override
  Widget build(BuildContext context) {
    final k = context.tk;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        excludeSemantics: true,
        onTap: onPressed,
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: outlined
                ? BoxDecoration(
                    color: Tk.frostA(0.06),
                    shape: BoxShape.circle,
                    border: Border.all(color: k.line))
                : const BoxDecoration(shape: BoxShape.circle),
            child: Icon(icon, size: 18, color: k.ink2),
          ),
        ),
      ),
    );
  }
}

/// A circular frosted tile with a line icon: the marker for a feature.
class IconTile extends StatelessWidget {
  final IconData icon;
  final double size;
  const IconTile(this.icon, {super.key, this.size = 56});

  @override
  Widget build(BuildContext context) {
    final k = context.tk;
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Tk.frostA(0.06),
          shape: BoxShape.circle,
          border: Border.all(color: k.line),
          boxShadow: const [
            BoxShadow(color: Color(0x66000000), blurRadius: 16)
          ],
        ),
        child: Icon(icon, size: size * 0.4, color: k.ink2),
      ),
    );
  }
}

// ------------------------------------------------------------------- fields

/// A label above an input.
class LabeledField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String? error;
  final String? helper;
  final bool obscure;
  final bool numeric;
  final bool money;
  final bool readOnly;
  final bool autofocus;
  final TextInputAction? action;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final Widget? suffix;
  final Iterable<String>? autofillHints;
  final TextCapitalization capitalization;
  final double? fontSize;

  /// Stops typing at this many characters (the server's limit).
  final int? maxLength;

  const LabeledField(
    this.label,
    this.controller, {
    super.key,
    this.error,
    this.helper,
    this.obscure = false,
    this.numeric = false,
    this.money = false,
    this.readOnly = false,
    this.autofocus = false,
    this.action,
    this.onSubmitted,
    this.onChanged,
    this.suffix,
    this.autofillHints,
    this.capitalization = TextCapitalization.none,
    this.fontSize,
    this.maxLength,
  });

  @override
  Widget build(BuildContext context) {
    final k = context.tk;
    final t = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: t.labelLarge!.copyWith(color: k.ink2)),
      const SizedBox(height: 6),
      Semantics(
        label: label,
        child: TextField(
          controller: controller,
          obscureText: obscure,
          readOnly: readOnly,
          enabled: !readOnly,
          autofocus: autofocus && !readOnly,
          autocorrect: !(obscure || autofillHints != null),
          enableSuggestions: !(obscure || autofillHints != null),
          textInputAction: action,
          onSubmitted: onSubmitted,
          onChanged: onChanged,
          autofillHints: autofillHints,
          textCapitalization: capitalization,
          keyboardType: numeric
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.text,
          inputFormatters: [
            if (numeric) FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            if (maxLength != null) LengthLimitingTextInputFormatter(maxLength),
          ],
          style: t.bodyLarge!.copyWith(
              fontSize: fontSize, color: readOnly ? k.ink4 : Colors.white),
          decoration: InputDecoration(
            errorText: error,
            helperText: helper,
            helperMaxLines: 3,
            errorMaxLines: 3,
            prefixText: money ? '₹ ' : null,
            prefixStyle:
                t.bodyLarge!.copyWith(color: k.ink4, fontSize: fontSize),
            suffixIcon: suffix,
            enabled: !readOnly,
            fillColor: readOnly ? Tk.frostA(0.03) : null,
          ),
        ),
      ),
    ]);
  }
}

// -------------------------------------------------------------------- tabs

/// Pill segmented control. The chosen segment is a brighter frost.
class SegTabs extends StatelessWidget {
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onChanged;
  final bool boxed;
  const SegTabs({
    super.key,
    required this.labels,
    required this.selected,
    required this.onChanged,
    this.boxed = true,
  });

  @override
  Widget build(BuildContext context) {
    final k = context.tk;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Tk.frostA(boxed ? 0.03 : 0.05),
        borderRadius: BorderRadius.circular(boxed ? 24 : 999),
        border: Border.all(color: k.line),
      ),
      child: Wrap(spacing: 2, runSpacing: 2, children: [
        for (var i = 0; i < labels.length; i++)
          Semantics(
            button: true,
            selected: i == selected,
            label: labels[i],
            excludeSemantics: true,
            onTap: () => onChanged(i),
            child: InkWell(
              onTap: () => onChanged(i),
              borderRadius: BorderRadius.circular(999),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: i == selected ? k.strong : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                  border: i == selected
                      ? Border.all(color: k.line2)
                      : Border.all(color: Colors.transparent),
                ),
                child: Text(labels[i],
                    style: TextStyle(
                        fontFamily: sans,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: i == selected ? Colors.white : k.ink3)),
              ),
            ),
          ),
      ]),
    );
  }
}

// ------------------------------------------------------------- empty states

class EmptyPanel extends StatelessWidget {
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  const EmptyPanel(
      {super.key,
      required this.title,
      required this.message,
      this.actionLabel,
      this.onAction});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final k = context.tk;
    return Panel(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 44),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Semantics(
            header: true,
            container: true,
            child:
                Text(title, style: t.titleMedium, textAlign: TextAlign.center)),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Text(message,
              textAlign: TextAlign.center,
              style: t.bodyMedium!.copyWith(color: k.ink3)),
        ),
        if (actionLabel != null) ...[
          const SizedBox(height: 20),
          Btn(actionLabel!, onPressed: onAction),
        ],
      ]),
    );
  }
}

/// Inline message strip: ember for errors, teal for good news, frost for info.
class Alert extends StatelessWidget {
  final String text;
  final TagKind kind; // no / ok / cobalt
  final IconData? icon;
  const Alert(this.text, {super.key, this.kind = TagKind.no, this.icon});

  @override
  Widget build(BuildContext context) {
    final k = context.tk;
    final (bg, fg) = switch (kind) {
      TagKind.ok => (k.matchSoft, k.match),
      TagKind.cobalt => (k.cobaltSoft, k.ink2),
      TagKind.warn => (k.amberSoft, k.amber),
      _ => (k.missSoft, k.miss),
    };
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: fg.withValues(alpha: 0.3)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: fg),
            const SizedBox(width: 10)
          ],
          Expanded(
              child: Text(text,
                  style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                      color: fg, fontWeight: FontWeight.w500, fontSize: 14))),
        ]),
      ),
    );
  }
}

/// A full-width notice at the top of a page (the low-balance warning).
class Banner2 extends StatelessWidget {
  final String text;
  final Widget? action;
  const Banner2(this.text, {super.key, this.action});

  @override
  Widget build(BuildContext context) {
    final k = context.tk;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: k.amberSoft,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: k.amber.withValues(alpha: 0.35)),
        ),
        child: Row(children: [
          Icon(Icons.warning_amber_rounded, size: 20, color: k.amber),
          const SizedBox(width: 12),
          Expanded(
              child: Text(text,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium!
                      .copyWith(color: k.ink, fontWeight: FontWeight.w500))),
          if (action != null) ...[const SizedBox(width: 12), action!],
        ]),
      ),
    );
  }
}

// --------------------------------------------------------------- month bar

/// Previous / next month with the current month between them.
class MonthSwitcher extends StatelessWidget {
  const MonthSwitcher({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final k = context.tk;
    return Container(
      decoration: BoxDecoration(
        color: Tk.frostA(0.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: k.line),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        IconBtn(
            icon: Icons.chevron_left,
            tooltip: 'Previous month',
            onPressed: () => app.shiftMonth(-1),
            size: 40),
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 124),
          child: Semantics(
            liveRegion: true,
            child: Text(monthLabel(app.month),
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .labelLarge!
                    .copyWith(color: Colors.white)),
          ),
        ),
        IconBtn(
            icon: Icons.chevron_right,
            tooltip: 'Next month',
            onPressed: () => app.shiftMonth(1),
            size: 40),
      ]),
    );
  }
}

// --------------------------------------------------------- daily spend chart

/// One column per day of the month; hover a column to read it.
class DailyChart extends StatelessWidget {
  final List<Map<String, dynamic>> trend;
  final DateTime month;
  const DailyChart({super.key, required this.trend, required this.month});

  @override
  Widget build(BuildContext context) {
    final k = context.tk;
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
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text('No spending recorded in ${monthLabel(month)}.',
            style: t.bodyMedium!.copyWith(color: k.ink3)),
      );
    }
    final peakDay = values.indexOf(maxV) + 1;
    final monthName = monthLabel(month).split(' ').first;
    final summary = 'Highest day: $peakDay $monthName, ${money(maxV)}';
    final still = _still(context);
    return Semantics(
      label: 'Daily spending. $summary.',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ExcludeSemantics(
            child: Text(summary, style: t.bodySmall!.copyWith(color: k.ink3))),
        const SizedBox(height: 14),
        ExcludeSemantics(
          child: SizedBox(
            height: 140,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: still ? 1 : 0, end: 1),
              duration:
                  still ? Duration.zero : const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (context, grow, _) => Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < days; i++)
                    Expanded(
                      child: Tooltip(
                        message: values[i] > 0
                            ? '${i + 1} $monthName: ${money(values[i])}'
                            : '${i + 1} $monthName: nothing spent',
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 1.5),
                          child: Container(
                            alignment: Alignment.bottomCenter,
                            color: Colors.transparent,
                            child: FractionallySizedBox(
                              heightFactor: values[i] <= 0
                                  ? 0.025
                                  : math.max(0.04, values[i] / maxV) * grow,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: values[i] <= 0
                                      ? k.track
                                      : (values[i] == maxV
                                          ? Tk.ice
                                          : Tk.iceDeep.withValues(alpha: 0.7)),
                                  borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(3)),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        ExcludeSemantics(
          child:
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('1', style: t.labelSmall),
            Text('${(days / 2).round()}', style: t.labelSmall),
            Text('$days', style: t.labelSmall),
          ]),
        ),
      ]),
    );
  }
}
