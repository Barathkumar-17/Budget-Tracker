import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'common.dart';
import 'theme.dart';

/// The reference design switches from sidebar to a top bar under 760px.
const kWideBreakpoint = 760.0;

bool isWide(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= kWideBreakpoint;

bool _still(BuildContext context) => MediaQuery.of(context).disableAnimations;

// ------------------------------------------------------------------- logo

class LogoMark extends StatelessWidget {
  final bool inverted;
  final double size;
  const LogoMark({super.key, this.inverted = false, this.size = 30});

  @override
  Widget build(BuildContext context) {
    final k = context.tk;
    return ExcludeSemantics(
      child: CustomPaint(
        size: Size(size, size),
        painter: _LogoPainter(
          bg: inverted ? k.onStrong : k.strong,
          fg: inverted ? k.strong : k.onStrong,
          hl: k.hl,
        ),
      ),
    );
  }
}

class _LogoPainter extends CustomPainter {
  final Color bg, fg, hl;
  _LogoPainter({required this.bg, required this.fg, required this.hl});

  @override
  void paint(Canvas canvas, Size s) {
    final u = s.width / 30;
    RRect r(double l, double t, double w, double h, double rad) =>
        RRect.fromRectAndRadius(Rect.fromLTWH(l * u, t * u, w * u, h * u),
            Radius.circular(rad * u));
    canvas.drawRRect(r(0, 0, 30, 30, 8), Paint()..color = bg);
    canvas.drawRRect(r(7, 8, 16, 3, 2), Paint()..color = fg);
    canvas.drawRRect(r(7, 14, 16, 3, 2), Paint()..color = fg);
    canvas.drawRRect(r(7, 20, 11, 4, 2), Paint()..color = hl);
  }

  @override
  bool shouldRepaint(covariant _LogoPainter o) =>
      o.bg != bg || o.fg != fg || o.hl != hl;
}

class Logo extends StatelessWidget {
  final bool inverted;

  /// Just the mark, for tight spaces.
  final bool compact;
  const Logo({super.key, this.inverted = false, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final k = context.tk;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      LogoMark(inverted: inverted),
      if (!compact) ...[
        const SizedBox(width: 9),
        Flexible(
            child: Text(
          'Budget Tracker',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleLarge!.copyWith(
              fontSize: 20,
              color: inverted ? k.onStrong : k.ink,
              letterSpacing: -0.4),
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
        decoration: BoxDecoration(color: k.hl, shape: BoxShape.circle),
        child: Text(
          name.isEmpty ? '?' : name[0].toUpperCase(),
          style: TextStyle(
              fontFamily: display,
              fontWeight: FontWeight.w800,
              fontSize: size * 0.44,
              color: k.onHl),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------ layout blocks

class Panel extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final Color? color;
  const Panel(
      {super.key,
      required this.child,
      this.padding = const EdgeInsets.all(24),
      this.color});

  @override
  Widget build(BuildContext context) {
    final k = context.tk;
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? k.paper,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: k.line),
      ),
      child: child,
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

/// Page title, one-line explanation and the page's actions.
class PageHead extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  const PageHead(
      {super.key, required this.title, this.subtitle, this.actions = const []});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final k = context.tk;
    final wide = isWide(context);
    final heading =
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Semantics(
        header: true,
        container: true,
        child: Text(title, style: wide ? t.headlineMedium : t.headlineSmall),
      ),
      if (subtitle != null) ...[
        const SizedBox(height: 4),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Text(subtitle!, style: t.bodyLarge!.copyWith(color: k.ink2)),
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

/// One divided panel of figures (not four identical cards).
class StatStrip extends StatelessWidget {
  final List<Stat> stats;
  const StatStrip(this.stats, {super.key});

  @override
  Widget build(BuildContext context) {
    final k = context.tk;
    return Container(
      decoration: BoxDecoration(
        color: k.paper,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: k.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(builder: (context, c) {
        final perRow = c.maxWidth >= 640 ? stats.length : 2;
        final rows = <Widget>[];
        for (var start = 0; start < stats.length; start += perRow) {
          final slice =
              stats.sublist(start, math.min(start + perRow, stats.length));
          rows.add(IntrinsicHeight(
            child:
                Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
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
        Text.rich(
          TextSpan(children: [
            TextSpan(
                text: s.value,
                style: t.headlineMedium!.copyWith(
                    fontSize: 32, letterSpacing: -1, color: s.color ?? k.ink)),
            if (s.small != null)
              TextSpan(
                  text: s.small,
                  style: t.titleSmall!.copyWith(
                      fontSize: 16,
                      color: k.ink3,
                      fontWeight: FontWeight.w600)),
          ]),
        ),
        const SizedBox(height: 2),
        Text(s.label, style: t.bodySmall),
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
      TagKind.cobalt => (k.cobaltSoft, k.cobaltDark),
      TagKind.ok => (k.matchSoft, k.match),
      TagKind.no => (k.missSoft, k.miss),
      TagKind.warn => (k.amberSoft, k.amber),
      TagKind.plain => (k.surface2, k.ink2),
      TagKind.hl => (k.hl, k.onHl),
      TagKind.purple => (k.purpleSoft, k.purple),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 4)
        ],
        Flexible(
          child: Text(text,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontFamily: sans,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: fg,
                  height: 1.25)),
        ),
      ]),
    );
  }
}

/// A category's name in its own colour: a tag with a dot.
class CategoryTag extends StatelessWidget {
  final String name;
  const CategoryTag(this.name, {super.key});

  @override
  Widget build(BuildContext context) {
    final k = context.tk;
    final c = categoryColor(name, Theme.of(context).brightness);
    return Container(
      padding: const EdgeInsets.fromLTRB(9, 4, 11, 4),
      decoration: BoxDecoration(
          color: k.surface2, borderRadius: BorderRadius.circular(99)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 7),
        Flexible(
          child: Text(titleCase(name),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontFamily: sans,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: k.ink,
                  height: 1.25)),
        ),
      ]),
    );
  }
}

/// Big percentage in a coloured block (the reference's match badge).
class PctBadge extends StatelessWidget {
  final String value;
  final String caption;
  final TagKind kind; // ok / warn / no / plain
  const PctBadge(this.value, this.caption, {super.key, this.kind = TagKind.ok});

  @override
  Widget build(BuildContext context) {
    final k = context.tk;
    final (bg, fg) = switch (kind) {
      TagKind.ok => (k.matchSoft, k.match),
      TagKind.warn => (k.amberSoft, k.amber),
      TagKind.no => (k.missSoft, k.miss),
      _ => (k.surface2, k.ink3),
    };
    return Container(
      constraints: const BoxConstraints(minWidth: 74),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(value,
            style: TextStyle(
                fontFamily: display,
                fontWeight: FontWeight.w800,
                fontSize: 21,
                letterSpacing: -0.4,
                color: fg,
                height: 1.1)),
        Text(caption,
            style: TextStyle(
                fontFamily: sans,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: fg)),
      ]),
    );
  }
}

// ------------------------------------------------------------ ring and bars

/// Percentage ring: green / amber / red by [color].
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
                track: k.track,
                hole: k.paper),
            child: Center(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(
                      text: center,
                      style: TextStyle(
                          fontFamily: display,
                          fontWeight: FontWeight.w800,
                          fontSize: size * 0.16,
                          letterSpacing: -0.6,
                          color: k.ink)),
                  if (small != null)
                    TextSpan(
                        text: small,
                        style: TextStyle(
                            fontFamily: sans,
                            fontWeight: FontWeight.w600,
                            fontSize: size * 0.065,
                            color: k.ink3)),
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
  final Color color, track, hole;
  _RingPainter(
      {required this.percent,
      required this.color,
      required this.track,
      required this.hole});

  @override
  void paint(Canvas canvas, Size s) {
    final stroke = s.width * 0.106;
    final rect = Rect.fromLTWH(
        stroke / 2, stroke / 2, s.width - stroke, s.height - stroke);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
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

/// Label and figure above a 10px bar, with an optional note below.
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
                style: t.bodyMedium!.copyWith(fontWeight: FontWeight.w600))),
        const SizedBox(width: 12),
        ConstrainedBox(
          constraints:
              BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.5),
          child: Text(trailing,
              textAlign: TextAlign.end,
              style: t.bodyMedium!.copyWith(color: k.ink2)),
        ),
      ]),
      const SizedBox(height: 6),
      ExcludeSemantics(
        child: Container(
          height: 10,
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
        const SizedBox(height: 4),
        Text(why!,
            style: t.labelSmall!.copyWith(
                fontWeight: FontWeight.w500,
                color: whyColor ?? k.ink3,
                fontSize: 12.8)),
      ],
    ]);
  }
}

// ------------------------------------------------------------------ buttons

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
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final k = context.tk;
    final shape = RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(small ? 8 : 10));
    final pad = small
        ? const EdgeInsets.symmetric(horizontal: 12, vertical: 7)
        : const EdgeInsets.symmetric(horizontal: 18, vertical: 12);
    final size = small ? const Size(0, 34) : const Size(0, 44);
    final textStyle = TextStyle(
        fontFamily: sans,
        fontWeight: FontWeight.w600,
        fontSize: small ? 13.6 : 15.2);
    final child = busy
        ? SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
                strokeWidth: 2.4,
                color: kind == BtnKind.primary ? Colors.white : k.cobalt))
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
        button = OutlinedButton(
          onPressed: busy ? null : onPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: k.ink,
            backgroundColor: Colors.transparent,
            disabledForegroundColor: k.ink3,
            side: BorderSide(color: k.line2, width: 1.5),
            shape: shape,
            padding: pad,
            minimumSize: size,
            textStyle: textStyle,
          ).copyWith(
              overlayColor:
                  WidgetStatePropertyAll(k.surface2.withValues(alpha: 0.7))),
          child: child,
        );
      case BtnKind.hl:
        button = FilledButton(
          onPressed: busy ? null : onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: k.hl,
            foregroundColor: k.onHl,
            disabledBackgroundColor: k.hl.withValues(alpha: 0.5),
            shape: shape,
            padding: pad,
            minimumSize: size,
            textStyle: textStyle,
            elevation: 0,
          ),
          child: child,
        );
      case BtnKind.danger:
        button = FilledButton(
          onPressed: busy ? null : onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: k.miss,
            foregroundColor: Theme.of(context).brightness == Brightness.dark
                ? const Color(0xFF2A0F0E)
                : Colors.white,
            disabledBackgroundColor: k.miss.withValues(alpha: 0.5),
            shape: shape,
            padding: pad,
            minimumSize: size,
            textStyle: textStyle,
            elevation: 0,
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
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: outlined
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: k.line2, width: 1.5))
                : null,
            child: Icon(icon, size: 18, color: k.ink2),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------- fields

/// A label above an input (the reference's .field).
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
  });

  @override
  Widget build(BuildContext context) {
    final k = context.tk;
    final t = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: t.labelLarge!.copyWith(fontSize: 14.4)),
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
          inputFormatters: numeric
              ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))]
              : null,
          style: t.bodyLarge!
              .copyWith(fontSize: fontSize, color: readOnly ? k.ink3 : k.ink),
          decoration: InputDecoration(
            errorText: error,
            helperText: helper,
            helperMaxLines: 3,
            errorMaxLines: 3,
            prefixText: money ? '₹ ' : null,
            prefixStyle:
                t.bodyLarge!.copyWith(color: k.ink3, fontSize: fontSize),
            suffixIcon: suffix,
            enabled: !readOnly,
            fillColor: readOnly ? k.surface2 : null,
          ),
        ),
      ),
    ]);
  }
}

// -------------------------------------------------------------------- tabs

/// Segmented control. [boxed] = the reference's Saved/Applied tabs (ink pill
/// on white); otherwise the lighter login tabs.
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
        color: boxed ? k.paper : k.bg,
        borderRadius: BorderRadius.circular(boxed ? 12 : 10),
        border: boxed ? Border.all(color: k.line) : null,
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
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                decoration: BoxDecoration(
                  color: i == selected
                      ? (boxed ? k.strong : k.paper)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: i == selected && !boxed
                      ? [
                          BoxShadow(
                              color: k.ink.withValues(alpha: 0.12),
                              blurRadius: 3,
                              offset: const Offset(0, 1))
                        ]
                      : null,
                ),
                child: Text(labels[i],
                    style: TextStyle(
                        fontFamily: sans,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: i == selected
                            ? (boxed ? k.onStrong : k.ink)
                            : k.ink2)),
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
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Semantics(
            header: true,
            container: true,
            child:
                Text(title, style: t.titleMedium, textAlign: TextAlign.center)),
        const SizedBox(height: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Text(message,
              textAlign: TextAlign.center,
              style: t.bodyMedium!.copyWith(color: k.ink2)),
        ),
        if (actionLabel != null) ...[
          const SizedBox(height: 18),
          Btn(actionLabel!, onPressed: onAction),
        ],
      ]),
    );
  }
}

/// Inline message strip: red for errors, green for good news, info otherwise.
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
      TagKind.cobalt => (k.cobaltSoft, k.cobaltDark),
      TagKind.warn => (k.amberSoft, k.amber),
      _ => (k.missSoft, k.miss),
    };
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: fg),
            const SizedBox(width: 10)
          ],
          Expanded(
              child: Text(text,
                  style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                      color: fg, fontWeight: FontWeight.w500, fontSize: 14.4))),
        ]),
      ),
    );
  }
}

/// Highlighter banner (the reference's .banner).
class Banner2 extends StatelessWidget {
  final String text;
  final Widget? action;
  const Banner2(this.text, {super.key, this.action});

  @override
  Widget build(BuildContext context) {
    final k = context.tk;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration:
          BoxDecoration(color: k.hl, borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        Expanded(
            child: Text(text,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium!
                    .copyWith(color: k.onHl, fontWeight: FontWeight.w500))),
        if (action != null) ...[const SizedBox(width: 12), action!],
      ]),
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
        color: k.paper,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: k.line2, width: 1.5),
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
                style: Theme.of(context).textTheme.labelLarge),
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
            style: t.bodyMedium!.copyWith(color: k.ink2)),
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
            child: Text(summary, style: t.bodySmall!.copyWith(color: k.ink2))),
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
                          padding: const EdgeInsets.symmetric(horizontal: 1.2),
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
                                          ? k.strong
                                          : k.cobalt),
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
