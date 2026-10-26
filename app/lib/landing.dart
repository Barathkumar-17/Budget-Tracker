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
    return PopScope(
      canPop: _page == _Page.landing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _page = _Page.landing);
      },
      child: _body(),
    );
  }

  Widget _body() {
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
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          _Nav(onLogin: onLogin, onRegister: onRegister),
          Expanded(
            child: SingleChildScrollView(
              child: Column(children: [
                _Hero(onLogin: onLogin, onRegister: onRegister),
                const _Features(),
                const _How(),
                _Closing(onRegister: onRegister),
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

/// Content is centred in a column no wider than 1200.
class _Page1200 extends StatelessWidget {
  final Widget child;
  const _Page1200({required this.child});

  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Padding(
              padding: EdgeInsets.symmetric(horizontal: _gutter(context)),
              child: child),
        ),
      );
}

// --------------------------------------------------------------------- nav

class _Nav extends StatelessWidget {
  final VoidCallback onLogin;
  final VoidCallback onRegister;
  const _Nav({required this.onLogin, required this.onRegister});

  @override
  Widget build(BuildContext context) {
    final k = context.tk;
    final wide = isWide(context);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: _gutter(context), vertical: 16),
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
            ],
          ),
        ),
      ]),
    );
  }
}

// -------------------------------------------------------------------- hero

class _Hero extends StatelessWidget {
  final VoidCallback onLogin;
  final VoidCallback onRegister;
  const _Hero({required this.onLogin, required this.onRegister});

  @override
  Widget build(BuildContext context) {
    final k = context.tk;
    final t = Theme.of(context).textTheme;
    final w = MediaQuery.sizeOf(context).width;
    final headline = t.displayLarge!.copyWith(
        fontSize: w >= 900 ? 80 : (w >= 560 ? 60 : 38),
        height: 1.08,
        letterSpacing: w >= 900 ? -1.5 : -0.8);
    return _Page1200(
      child: Column(children: [
        const SizedBox(height: 56),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: const Eyebrow('Introducing Budget Tracker', centered: true),
        ),
        const SizedBox(height: 28),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Semantics(
            header: true,
            container: true,
            child: GradientText('Know where your money goes.',
                align: TextAlign.center, style: headline),
          ),
        ),
        const SizedBox(height: 20),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Text(
            'Log what you spend, give each category a monthly budget, and get told the moment a '
            'purchase takes you over it. Your balance, bills that repeat every month and savings '
            'goals sit in one place.',
            textAlign: TextAlign.center,
            style:
                t.bodyLarge!.copyWith(fontSize: 18, color: k.ink3, height: 1.5),
          ),
        ),
        const SizedBox(height: 32),
        Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 12,
            children: [
              Btn('Create account', onPressed: onRegister),
              Btn('Log in', kind: BtnKind.ghost, onPressed: onLogin),
            ]),
        const SizedBox(height: 18),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Text(
            'Your data stays in your own account. There is no bank connection and nothing is shared.',
            textAlign: TextAlign.center,
            style: t.bodySmall!.copyWith(color: k.ink4),
          ),
        ),
        const SizedBox(height: 56),
        const _CardFan(),
        const SizedBox(height: 96),
      ]),
    );
  }
}

/// Three glass cards in an overlapping fan: expenses, a budget, a goal.
class _CardFan extends StatelessWidget {
  const _CardFan();

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w < 760) return const _BudgetCard();
    return LayoutBuilder(builder: (context, c) {
      final half = c.maxWidth / 2;
      // Each side card tucks about 90px behind the centre card.
      final side = math.min(340.0, half - 100);
      return SizedBox(
        height: 400,
        child: Stack(children: [
          Positioned(
            left: half - 100 - side,
            top: 44,
            width: side,
            child: Transform.rotate(angle: -0.07, child: const _ExpensesCard()),
          ),
          Positioned(
            left: half + 100,
            top: 44,
            width: side,
            child: Transform.rotate(angle: 0.07, child: const _GoalCard()),
          ),
          Positioned(
            left: half - 190,
            top: 0,
            width: 380,
            child: const _BudgetCard(),
          ),
        ]),
      );
    });
  }
}

class _MiniHead extends StatelessWidget {
  final String text;
  const _MiniHead(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: ExcludeSemantics(child: Eyebrow(text)),
      );
}

class _BudgetCard extends StatelessWidget {
  const _BudgetCard();

  @override
  Widget build(BuildContext context) {
    final k = context.tk;
    final t = Theme.of(context).textTheme;
    return ExcludeSemantics(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Panel(
          deep: true,
          padding: const EdgeInsets.all(24),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const _MiniHead('Food · this month'),
                Text('₹40 over',
                    style: t.headlineMedium!.copyWith(color: k.miss)),
                const SizedBox(height: 4),
                Text('₹1,540 spent of a ₹1,500 budget',
                    style: t.bodyMedium!.copyWith(color: k.ink3)),
                const SizedBox(height: 18),
                BarRow(
                    label: 'Food',
                    trailing: '₹1,540 of ₹1,500',
                    fraction: 1,
                    color: k.miss),
                const SizedBox(height: 14),
                BarRow(
                    label: 'Transport',
                    trailing: '₹285 of ₹400',
                    fraction: 0.71,
                    color: k.link),
                const SizedBox(height: 14),
                const Tag('Over budget', kind: TagKind.no),
              ]),
        ),
      ),
    );
  }
}

class _ExpensesCard extends StatelessWidget {
  const _ExpensesCard();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final k = context.tk;
    Widget row(String cat, String note, String amount) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(children: [
            CategoryTag(cat),
            const SizedBox(width: 10),
            Expanded(
                child: Text(note,
                    overflow: TextOverflow.ellipsis,
                    style: t.bodySmall!.copyWith(color: k.ink3))),
            Text(amount,
                style: t.bodyMedium!
                    .copyWith(fontWeight: FontWeight.w500, color: k.ink)),
          ]),
        );
    return ExcludeSemantics(
      child: Panel(
        padding: const EdgeInsets.all(22),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const _MiniHead('Recent expenses'),
              row('Food', 'Lunch', '₹180'),
              row('Transport', 'Metro card', '₹90'),
              row('Fun', 'Movie', '₹250'),
            ]),
      ),
    );
  }
}

class _GoalCard extends StatelessWidget {
  const _GoalCard();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final k = context.tk;
    return ExcludeSemantics(
      child: Panel(
        padding: const EdgeInsets.all(22),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const _MiniHead('Savings goal'),
              Row(children: [
                Ring(percent: 17, color: k.link, center: '17%', size: 84),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Laptop', style: t.titleMedium),
                        const SizedBox(height: 2),
                        Text('₹10,000 of ₹60,000',
                            style: t.bodySmall!.copyWith(color: k.ink3)),
                      ]),
                ),
              ]),
            ]),
      ),
    );
  }
}

// ---------------------------------------------------------------- features

class _SectionHead extends StatelessWidget {
  final String eyebrow;
  final String title;
  final String? body;
  const _SectionHead({required this.eyebrow, required this.title, this.body});

  @override
  Widget build(BuildContext context) {
    final k = context.tk;
    final t = Theme.of(context).textTheme;
    final w = MediaQuery.sizeOf(context).width;
    return Column(children: [
      ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Eyebrow(eyebrow, centered: true)),
      const SizedBox(height: 24),
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Semantics(
          header: true,
          container: true,
          child: GradientText(title,
              align: TextAlign.center,
              style: t.displayMedium!.copyWith(fontSize: w >= 760 ? 44 : 30)),
        ),
      ),
      if (body != null) ...[
        const SizedBox(height: 16),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Text(body!,
              textAlign: TextAlign.center,
              style: t.bodyLarge!.copyWith(fontSize: 17, color: k.ink3)),
        ),
      ],
    ]);
  }
}

class _Features extends StatelessWidget {
  const _Features();

  static const _items = [
    (Icons.receipt_long_outlined, 'Expenses', 'Log in seconds, edit or undo'),
    (Icons.pie_chart_outline_rounded, 'Budgets', 'A monthly cap per category'),
    (Icons.notifications_none_rounded, 'Alerts', 'Told the moment you go over'),
    (Icons.autorenew_rounded, 'Recurring', 'Rent and subscriptions, once'),
    (Icons.flag_outlined, 'Goals', 'Save towards what you want'),
    (
      Icons.lock_outline_rounded,
      'Private',
      'Your own account, hashed password'
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final k = context.tk;
    final t = Theme.of(context).textTheme;
    final w = MediaQuery.sizeOf(context).width;
    final perRow = w >= 1000 ? 6 : (w >= 600 ? 3 : 2);
    Widget cell(int i) => Column(children: [
          IconTile(_items[i].$1, size: 60),
          const SizedBox(height: 14),
          Text(_items[i].$2, style: t.titleSmall!.copyWith(color: k.ink)),
          const SizedBox(height: 4),
          Text(_items[i].$3,
              textAlign: TextAlign.center,
              style: t.bodySmall!.copyWith(color: k.ink4, fontSize: 13)),
        ]);
    final rows = <Widget>[];
    for (var s = 0; s < _items.length; s += perRow) {
      final end = math.min(s + perRow, _items.length);
      rows.add(Stack(alignment: Alignment.topCenter, children: [
        // the line that threads the tiles together
        Positioned(
          top: 30,
          left: 40,
          right: 40,
          child: Container(height: 1, color: k.line),
        ),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (var i = s; i < s + perRow; i++)
            Expanded(
                child: i < end
                    ? Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: cell(i))
                    : const SizedBox.shrink()),
        ]),
      ]));
      if (end < _items.length) rows.add(const SizedBox(height: 36));
    }
    return _Page1200(
      child: Column(children: [
        const _SectionHead(
          eyebrow: 'Everything in one place',
          title: 'Five screens, no spreadsheet.',
          body:
              'Each one answers a single question: what did I spend, what is left, what is coming, what am I saving for.',
        ),
        const SizedBox(height: 56),
        ...rows,
        const SizedBox(height: 120),
      ]),
    );
  }
}

// ------------------------------------------------------------ how it works

class _How extends StatelessWidget {
  const _How();

  static const _steps = [
    (
      '01',
      'Set a budget',
      'Give a category such as Food a monthly cap. Set a safety line for your balance too.'
    ),
    (
      '02',
      'Log what you spend',
      'Add an expense in a few seconds. You are told straight away if it takes you over a budget or below your safety line.'
    ),
    (
      '03',
      'See where it went',
      'The dashboard shows what is left, how much of each budget you have used and how your month is going.'
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final k = context.tk;
    final t = Theme.of(context).textTheme;
    final wide = MediaQuery.sizeOf(context).width >= 860;
    Widget card(int i) => Panel(
          padding: const EdgeInsets.all(28),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_steps[i].$1,
                    style: TextStyle(
                        fontFamily: mono,
                        fontFamilyFallback: const [sans],
                        fontSize: 15,
                        letterSpacing: 1.5,
                        color: k.ink4)),
                const SizedBox(height: 22),
                Text(_steps[i].$2, style: t.titleLarge),
                const SizedBox(height: 10),
                Text(_steps[i].$3,
                    style: t.bodyMedium!.copyWith(color: k.ink3, height: 1.55)),
              ]),
        );
    return _Page1200(
      child: Column(children: [
        const _SectionHead(eyebrow: 'Three steps', title: 'How it works'),
        const SizedBox(height: 48),
        if (wide)
          IntrinsicHeight(
            child:
                Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (var i = 0; i < _steps.length; i++) ...[
                if (i > 0) const SizedBox(width: 20),
                Expanded(child: card(i)),
              ],
            ]),
          )
        else
          Column(children: [
            for (var i = 0; i < _steps.length; i++) ...[
              if (i > 0) const SizedBox(height: 16),
              card(i),
            ],
          ]),
        const SizedBox(height: 120),
      ]),
    );
  }
}

class _Closing extends StatelessWidget {
  final VoidCallback onRegister;
  const _Closing({required this.onRegister});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final k = context.tk;
    return _Page1200(
      child: Panel(
        deep: true,
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 56),
        child: Column(children: [
          Text('Start with this month.',
              textAlign: TextAlign.center, style: t.headlineMedium),
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Text(
                'Make an account, set one budget and log your next expense. It takes about a minute.',
                textAlign: TextAlign.center,
                style: t.bodyLarge!.copyWith(color: k.ink3)),
          ),
          const SizedBox(height: 26),
          Btn('Create account', onPressed: onRegister),
        ]),
      ),
    );
  }
}

class _Foot extends StatelessWidget {
  const _Foot();

  @override
  Widget build(BuildContext context) {
    final k = context.tk;
    return Padding(
      padding: EdgeInsets.fromLTRB(_gutter(context), 64, _gutter(context), 40),
      child: Text(
        'A prototype for a small number of users. Not built for scale.',
        textAlign: TextAlign.center,
        style: Theme.of(context)
            .textTheme
            .bodySmall!
            .copyWith(color: k.ink4, fontSize: 13),
      ),
    );
  }
}
