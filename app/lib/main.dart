import 'package:flutter/material.dart';

import 'auth.dart';
import 'budgets.dart';
import 'common.dart';
import 'dashboard.dart';
import 'expenses.dart';
import 'goals.dart';
import 'landing.dart';
import 'recurring.dart';
import 'theme.dart';
import 'ui.dart';

void main() => runApp(const BudgetApp());

class BudgetApp extends StatefulWidget {
  const BudgetApp({super.key});

  @override
  State<BudgetApp> createState() => _BudgetAppState();
}

class _BudgetAppState extends State<BudgetApp> {
  final _auth = AuthState();
  final _theme = ThemeController();

  @override
  void initState() {
    super.initState();
    _theme.restore();
    _auth.restore();
  }

  @override
  void dispose() {
    _auth.dispose();
    _theme.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ThemeScope(
      controller: _theme,
      child: AuthScope(
        state: _auth,
        child: ListenableBuilder(
          listenable: _theme,
          builder: (context, _) => MaterialApp(
            title: 'Budget Tracker',
            debugShowCheckedModeBanner: false,
            theme: buildTheme(Brightness.light),
            darkTheme: buildTheme(Brightness.dark),
            themeMode: _theme.mode,
            home: const _Gate(),
          ),
        ),
      ),
    );
  }
}

/// The public pages until someone is logged in, then the app.
class _Gate extends StatelessWidget {
  const _Gate();

  @override
  Widget build(BuildContext context) {
    final auth = AuthScope.of(context);
    return switch (auth.status) {
      AuthStatus.loading => Scaffold(
          body: auth.waking
              ? const WakingPanel()
              : const Center(child: CircularProgressIndicator())),
      AuthStatus.unreachable =>
        Scaffold(body: ErrorState(onRetry: auth.restore)),
      AuthStatus.loggedOut => const PublicArea(),
      // A new key per user, so nothing from the previous account can linger.
      AuthStatus.loggedIn => _Session(key: ValueKey(auth.username)),
    };
  }
}

/// One logged-in session: its own month, tab and reload state.
class _Session extends StatefulWidget {
  const _Session({super.key});

  @override
  State<_Session> createState() => _SessionState();
}

class _SessionState extends State<_Session> {
  final _state = AppState();

  @override
  void dispose() {
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      AppScope(state: _state, child: const Shell());
}

class _Section {
  final String title;
  final IconData icon;
  const _Section(this.title, this.icon);
}

const _sections = [
  _Section('Dashboard', Icons.grid_view_rounded),
  _Section('Expenses', Icons.receipt_long_outlined),
  _Section('Budgets', Icons.pie_chart_outline_rounded),
  _Section('Recurring', Icons.autorenew_rounded),
  _Section('Goals', Icons.flag_outlined),
];

class Shell extends StatelessWidget {
  const Shell({super.key});

  Widget _page(int i) => switch (i) {
        0 => const DashboardScreen(),
        1 => const ExpensesScreen(),
        2 => const BudgetsScreen(),
        3 => const RecurringScreen(),
        _ => const GoalsScreen(),
      };

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final k = context.tk;
    final wide = isWide(context);
    final still = MediaQuery.of(context).disableAnimations;
    final content = AnimatedSwitcher(
      duration: still ? Duration.zero : const Duration(milliseconds: 180),
      child: KeyedSubtree(key: ValueKey(app.tab), child: _page(app.tab)),
    );
    final padded = Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1240),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
              wide ? 40 : 18, wide ? 36 : 22, wide ? 40 : 18, 0),
          child: content,
        ),
      ),
    );
    return PopScope(
      // System Back from any other section returns to the dashboard first.
      canPop: app.tab == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) app.goTo(0);
      },
      child: Scaffold(
        backgroundColor: k.bg,
        body: wide
            ? Row(children: [
                _Sidebar(selected: app.tab, onSelect: app.goTo),
                Expanded(child: padded),
              ])
            : SafeArea(
                child: Column(children: [
                  const _TopBar(),
                  _TabRow(selected: app.tab, onSelect: app.goTo),
                  Expanded(child: padded),
                ]),
              ),
      ),
    );
  }
}

// ----------------------------------------------------------------- sidebar

class _Sidebar extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onSelect;
  const _Sidebar({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final k = context.tk;
    return Container(
      width: 240,
      decoration: BoxDecoration(
        color: k.paper,
        border: Border(right: BorderSide(color: k.line)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(0, 0, 0, 24),
          child: Align(alignment: Alignment.centerLeft, child: Logo()),
        ),
        Semantics(
          container: true,
          label: 'Main navigation',
          child: Column(children: [
            for (var i = 0; i < _sections.length; i++)
              _NavItem(
                  section: _sections[i],
                  active: i == selected,
                  onTap: () => onSelect(i)),
          ]),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.only(top: 16),
          decoration:
              BoxDecoration(border: Border(top: BorderSide(color: k.line))),
          child: const _UserBlock(),
        ),
      ]),
    );
  }
}

class _NavItem extends StatelessWidget {
  final _Section section;
  final bool active;
  final VoidCallback onTap;
  const _NavItem(
      {required this.section, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final k = context.tk;
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Semantics(
        button: true,
        selected: active,
        label: section.title,
        excludeSemantics: true,
        onTap: onTap,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(9),
          hoverColor: k.bg,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: active ? k.strong : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Row(children: [
              Icon(section.icon, size: 18, color: active ? k.onStrong : k.ink2),
              const SizedBox(width: 11),
              Text(section.title,
                  style: t.bodyMedium!.copyWith(
                      fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                      color: active ? k.onStrong : k.ink2)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _UserBlock extends StatelessWidget {
  const _UserBlock();

  @override
  Widget build(BuildContext context) {
    final auth = AuthScope.of(context);
    final theme = ThemeScope.of(context);
    final k = context.tk;
    final t = Theme.of(context).textTheme;
    final name = auth.username ?? '';
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Row(children: [
      Avatar(name),
      const SizedBox(width: 10),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.bodyMedium!.copyWith(fontWeight: FontWeight.w700)),
          Text('Signed in',
              style: t.labelSmall!
                  .copyWith(fontWeight: FontWeight.w400, color: k.ink3)),
        ]),
      ),
      IconBtn(
        icon: dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
        tooltip: dark ? 'Switch to light theme' : 'Switch to dark theme',
        outlined: true,
        size: 32,
        onPressed: () => theme.set(dark ? ThemeMode.light : ThemeMode.dark),
      ),
      const SizedBox(width: 4),
      IconBtn(
        icon: Icons.logout_rounded,
        tooltip: 'Log out',
        size: 32,
        onPressed: auth.logout,
      ),
    ]);
  }
}

// ------------------------------------------------------ phone top bar + tabs

class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    final auth = AuthScope.of(context);
    final theme = ThemeScope.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(children: [
        const Expanded(
            child: Align(alignment: Alignment.centerLeft, child: Logo())),
        Avatar(auth.username ?? '', size: 34),
        const SizedBox(width: 8),
        IconBtn(
          icon: dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
          tooltip: dark ? 'Switch to light theme' : 'Switch to dark theme',
          outlined: true,
          size: 40,
          onPressed: () => theme.set(dark ? ThemeMode.light : ThemeMode.dark),
        ),
        const SizedBox(width: 4),
        IconBtn(
            icon: Icons.logout_rounded,
            tooltip: 'Log out',
            size: 40,
            onPressed: auth.logout),
      ]),
    );
  }
}

class _TabRow extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onSelect;
  const _TabRow({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final k = context.tk;
    final t = Theme.of(context).textTheme;
    return Container(
      decoration:
          BoxDecoration(border: Border(bottom: BorderSide(color: k.line))),
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Semantics(
          container: true,
          label: 'Main navigation',
          child: Row(children: [
            for (var i = 0; i < _sections.length; i++)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Semantics(
                  button: true,
                  selected: i == selected,
                  label: _sections[i].title,
                  excludeSemantics: true,
                  onTap: () => onSelect(i),
                  child: InkWell(
                    onTap: () => onSelect(i),
                    borderRadius: BorderRadius.circular(9),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: i == selected ? k.strong : Colors.transparent,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Text(_sections[i].title,
                          style: t.bodyMedium!.copyWith(
                              fontWeight: FontWeight.w600,
                              color: i == selected ? k.onStrong : k.ink2)),
                    ),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}
