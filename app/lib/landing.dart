import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'auth.dart';
import 'auth_screen.dart';
import 'theme.dart';
import 'ui.dart';

enum _Page { landing, login, register }

/// What a visitor sees before logging in: the landing page, then the login screen.
class PublicArea extends StatefulWidget {
  const PublicArea({super.key});

  @override
  State<PublicArea> createState() => _PublicAreaState();
}

class _PublicAreaState extends State<PublicArea> {
  _Page? _pageOrNull;

  /// A visitor starts on the landing page; someone whose session just ended
  /// goes straight to the login screen (where the notice is shown).
  _Page get _page =>
      _pageOrNull ??
      (AuthScope.of(context).notice != null ? _Page.login : _Page.landing);
  set _page(_Page p) => _pageOrNull = p;

  @override
  Widget build(BuildContext context) {
    return switch (_page) {
      _Page.landing => LandingScreen(
          onLogin: () => setState(() => _page = _Page.login),
          onRegister: () => setState(() => _page = _Page.register)),
      _ => AuthScreen(
          registering: _page == _Page.register,
          onMode: (reg) =>
              setState(() => _page = reg ? _Page.register : _Page.login),
          onBack: () => setState(() => _page = _Page.landing)),
    };
  }
}

class LandingScreen extends StatelessWidget {
  final VoidCallback onLogin;
  final VoidCallback onRegister;
  const LandingScreen(
      {super.key, required this.onLogin, required this.onRegister});

  @override
  Widget build(BuildContext context) {
    final k = context.tk;
    return Scaffold(
      backgroundColor: k.paper,
      body: SafeArea(
        child: Column(children: [
          _Nav(onLogin: onLogin, onRegister: onRegister),
          Expanded(
            child: SingleChildScrollView(
              child: Column(children: [
                _Hero(onLogin: onLogin, onRegister: onRegister),
                const _How(),
                const _Foot(),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

double _gutter(BuildContext c) {
  final w = MediaQuery.sizeOf(c).width;
  return (w * 0.05).clamp(16.0, 64.0);
}

class _Nav extends StatelessWidget {
  final VoidCallback onLogin;
  final VoidCallback onRegister;
  const _Nav({required this.onLogin, required this.onRegister});

  @override
  Widget build(BuildContext context) {
    final k = context.tk;
    final theme = ThemeScope.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final wide = isWide(context);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: _gutter(context), vertical: 18),
      decoration:
          BoxDecoration(border: Border(bottom: BorderSide(color: k.line))),
      child: Row(children: [
        Logo(compact: MediaQuery.sizeOf(context).width < 520),
        const SizedBox(width: 12),
        // The buttons wrap onto a second line when large system text leaves
        // no room for them beside the logo.
        Expanded(
          child: Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              Btn('Log in',
                  kind: BtnKind.ghost, small: !wide, onPressed: onLogin),
              Btn('Create account', small: !wide, onPressed: onRegister),
              IconBtn(
                icon:
                    dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                tooltip:
                    dark ? 'Switch to light theme' : 'Switch to dark theme',
                outlined: true,
                size: 40,
                onPressed: () =>
                    theme.set(dark ? ThemeMode.light : ThemeMode.dark),
              ),
            ],
          ),
        ),
      ]),
    );
  }
}

class _Hero extends StatelessWidget {
  final VoidCallback onLogin;
  final VoidCallback onRegister;
  const _Hero({required this.onLogin, required this.onRegister});

  @override
  Widget build(BuildContext context) {
    final k = context.tk;
    final t = Theme.of(context).textTheme;
    final w = MediaQuery.sizeOf(context).width;
    final wide = w >= 900;
    final headline = t.displayLarge!.copyWith(
        fontSize: wide ? math.min(66, w * 0.05) : (w < 420 ? 40 : 52));
    final text =
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Semantics(
          header: true,
          container: true,
          child: Text('Know where your money goes.', style: headline)),
      const SizedBox(height: 20),
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 544),
        child: Text(
          'Log what you spend, give each category a monthly budget, and get told the moment a '
          'purchase takes you over it. Your balance, bills that repeat every month and savings '
          'goals sit in one place.',
          style:
              t.bodyLarge!.copyWith(fontSize: 18, color: k.ink2, height: 1.55),
        ),
      ),
      const SizedBox(height: 28),
      Wrap(spacing: 12, runSpacing: 12, children: [
        Btn('Create account', kind: BtnKind.hl, onPressed: onRegister),
        Btn('Log in', kind: BtnKind.ghost, onPressed: onLogin),
      ]),
      const SizedBox(height: 22),
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 512),
        child: Text(
          'Your data stays in your own account. There is no bank connection and nothing is shared.',
          style: t.bodySmall!.copyWith(color: k.ink3, fontSize: 14.4),
        ),
      ),
    ]);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1280),
        child: Padding(
          padding: EdgeInsets.symmetric(
              horizontal: _gutter(context), vertical: wide ? 72 : 36),
          child: wide
              ? Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                  Expanded(flex: 105, child: text),
                  const SizedBox(width: 56),
                  const Expanded(flex: 100, child: _StatementIllustration()),
                ])
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  text,
                  const SizedBox(height: 40),
                  const _StatementIllustration(),
                ]),
        ),
      ),
    );
  }
}

/// A printed statement with the amounts highlighted, and the alert it produces.
class _StatementIllustration extends StatelessWidget {
  const _StatementIllustration();

  @override
  Widget build(BuildContext context) {
    final k = context.tk;
    final t = Theme.of(context).textTheme;
    TextStyle body = TextStyle(
        fontFamily: serif, fontSize: 15.2, height: 1.75, color: k.ink2);
    TextSpan amount(String s) => TextSpan(
        text: s,
        style: body.copyWith(
            fontWeight: FontWeight.w600, color: k.onHl, backgroundColor: k.hl));
    Widget line(String what, String a) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 1),
          child: Row(children: [
            Expanded(child: Text(what, style: body)),
            Text.rich(TextSpan(children: [amount(' $a ')])),
          ]),
        );
    Widget heading(String s) => Container(
          margin: const EdgeInsets.only(top: 16, bottom: 6),
          padding: const EdgeInsets.only(bottom: 3),
          decoration:
              BoxDecoration(border: Border(bottom: BorderSide(color: k.line))),
          child: Text(s,
              style: TextStyle(
                  fontFamily: sans,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.8,
                  color: k.ink3)),
        );
    return Padding(
      padding: const EdgeInsets.only(right: 24, bottom: 120),
      child: Stack(clipBehavior: Clip.none, children: [
        Transform.rotate(
          angle: -0.026,
          child: Container(
            padding: const EdgeInsets.fromLTRB(30, 28, 30, 32),
            decoration: BoxDecoration(
              color: k.paper,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: k.line),
              boxShadow: [
                BoxShadow(
                    color: k.ink.withValues(alpha: 0.14),
                    blurRadius: 40,
                    spreadRadius: -14,
                    offset: const Offset(0, 24)),
              ],
            ),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Arun Kumar',
                  style: t.titleLarge!
                      .copyWith(fontSize: 20.8, letterSpacing: -0.4)),
              Text('October 2026 statement',
                  style: body.copyWith(color: k.ink3)),
              heading('Spending'),
              line('Lunch, canteen', '₹180'),
              line('Groceries', '₹420'),
              line('Dinner out', '₹640'),
              line('Snacks', '₹300'),
              heading('Budget'),
              line('Food, monthly budget', '₹1,500'),
            ]),
          ),
        ),
        Positioned(
          right: -24,
          bottom: -112,
          child: Container(
            width: 250,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            decoration: BoxDecoration(
              color: k.strong,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                    color: k.ink.withValues(alpha: 0.4),
                    blurRadius: 40,
                    spreadRadius: -18,
                    offset: const Offset(0, 20)),
              ],
            ),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Food',
                  style: t.titleSmall!
                      .copyWith(color: k.onStrong, fontSize: 15.5)),
              Text('Over budget this month',
                  style: t.bodySmall!
                      .copyWith(color: const Color(0xFFB8C0D9), fontSize: 13)),
              const SizedBox(height: 8),
              Text('₹40 over',
                  style: t.headlineMedium!.copyWith(
                      color: k.hl,
                      fontSize: 32,
                      letterSpacing: -0.8,
                      height: 1)),
              const SizedBox(height: 6),
              Text('₹1,540 spent of a ₹1,500 budget',
                  style: t.bodySmall!
                      .copyWith(color: const Color(0xFFB8C0D9), fontSize: 13)),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _How extends StatelessWidget {
  const _How();

  @override
  Widget build(BuildContext context) {
    final k = context.tk;
    final t = Theme.of(context).textTheme;
    final w = MediaQuery.sizeOf(context).width;
    final cols = w >= 1000 ? 4 : (w >= 600 ? 2 : 1);
    const steps = [
      (
        'Add what you spend',
        'Log an expense in a few seconds: the amount, a category, the date and an optional note.'
      ),
      (
        'Set a monthly budget',
        'Give each category a cap for the month, such as food or transport.'
      ),
      (
        'Get warned at once',
        'The moment an expense takes a category past its cap, you are told how much over you are.'
      ),
      (
        'Stay ahead',
        'See your balance, recurring bills and savings goals together, and a safety line that warns you when money runs low.'
      ),
    ];
    return Container(
      width: double.infinity,
      color: k.bg,
      padding: EdgeInsets.symmetric(horizontal: _gutter(context), vertical: 64),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Semantics(
                header: true,
                container: true,
                child: Text('How it works',
                    style: t.displayMedium!
                        .copyWith(fontSize: w < 600 ? 30 : 38))),
            const SizedBox(height: 8),
            Text('Four steps, nothing to set up first.',
                style: t.bodyLarge!.copyWith(color: k.ink2)),
            const SizedBox(height: 36),
            LayoutBuilder(builder: (context, c) {
              final cell = (c.maxWidth - (cols - 1) * 20) / cols;
              return Wrap(spacing: 20, runSpacing: 28, children: [
                for (var i = 0; i < steps.length; i++)
                  SizedBox(
                    width: cell,
                    child: Container(
                      padding: const EdgeInsets.only(top: 16),
                      decoration: BoxDecoration(
                          border:
                              Border(top: BorderSide(color: k.ink, width: 3))),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${i + 1}',
                                style: t.headlineMedium!
                                    .copyWith(fontSize: 26, color: k.cobalt)),
                            const SizedBox(height: 4),
                            Text(steps[i].$1, style: t.titleMedium),
                            const SizedBox(height: 6),
                            Text(steps[i].$2,
                                style: t.bodyMedium!.copyWith(color: k.ink2)),
                          ]),
                    ),
                  ),
              ]);
            }),
            const SizedBox(height: 40),
            Panel(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Wrap(
                  spacing: 32,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('How your balance is worked out',
                        style: t.titleSmall!.copyWith(fontSize: 16)),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                          color: k.hl, borderRadius: BorderRadius.circular(4)),
                      child: Text(
                          'Balance = opening balance − all expenses − money put into goals',
                          style: TextStyle(
                              fontFamily: sans,
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                              color: k.onHl)),
                    ),
                  ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Foot extends StatelessWidget {
  const _Foot();

  @override
  Widget build(BuildContext context) {
    final k = context.tk;
    final t = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: _gutter(context), vertical: 24),
      decoration: BoxDecoration(
          color: k.paper, border: Border(top: BorderSide(color: k.line))),
      child: Text(
          'Budget Tracker. A personal budgeting prototype for a small number of users.',
          style: t.bodySmall!.copyWith(color: k.ink3, fontSize: 13.6)),
    );
  }
}
