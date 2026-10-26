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

  @override
  void initState() {
    super.initState();
    _auth.restore();
  }

  @override
  void dispose() {
    _auth.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AuthScope(
      state: _auth,
      child: MaterialApp(
        title: 'Budget Tracker',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        // The midnight canvas, grid and spotlight sit behind every page.
        builder: (context, child) => Atmosphere(child: child!),
        home: const _Gate(),
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
    final wide = isWide(context);
    final still = MediaQuery.of(context).disableAnimations;
    final content = AnimatedSwitcher(
      duration: still ? Duration.zero : const Duration(milliseconds: 180),
      child: KeyedSubtree(key: ValueKey(app.tab), child: _page(app.tab)),
    );
    final padded = Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1200),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
              wide ? 32 : 16, wide ? 28 : 12, wide ? 32 : 16, 0),
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
        body: SafeArea(
          child: wide
              ? Column(children: [
                  _TopNav(selected: app.tab, onSelect: app.goTo),
                  Expanded(child: padded),
                ])
              : Stack(children: [
                  Column(children: [
                    const _PhoneBar(),
                    Expanded(child: padded),
                  ]),
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 10,
                    child: _BottomNav(selected: app.tab, onSelect: app.goTo),
                  ),
                ]),
        ),
      ),
    );
  }
}

// --------------------------------------------------------------- desktop nav

/// Logo on the left, a floating glass pill of sections in the middle, the
/// signed-in user on the right.
class _TopNav extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onSelect;
  const _TopNav({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final k = context.tk;
    final width = MediaQuery.sizeOf(context).width;
    return Container(
      decoration:
          BoxDecoration(border: Border(bottom: BorderSide(color: k.line))),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      child: Row(children: [
        Expanded(
            child: Align(
                alignment: Alignment.centerLeft,
                child: Logo(compact: width < 1000))),
        Semantics(
          container: true,
          label: 'Main navigation',
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Tk.frostA(0.05),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: k.line),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              for (var i = 0; i < _sections.length; i++)
                _NavPill(
                    section: _sections[i],
                    active: i == selected,
                    onTap: () => onSelect(i)),
            ]),
          ),
        ),
        Expanded(
          child: Align(
              alignment: Alignment.centerRight,
              child: _UserBlock(showName: width >= 1060)),
        ),
      ]),
    );
  }
}

class _NavPill extends StatelessWidget {
  final _Section section;
  final bool active;
  final VoidCallback onTap;
  const _NavPill(
      {required this.section, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final k = context.tk;
    final t = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      selected: active,
      label: section.title,
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: active ? k.strong : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: active ? k.line2 : Colors.transparent),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(section.icon, size: 16, color: active ? k.ink : k.ink4),
            const SizedBox(width: 8),
            Text(section.title,
                style: t.bodyMedium!.copyWith(
                    fontWeight: FontWeight.w500,
                    color: active ? Colors.white : k.ink3)),
          ]),
        ),
      ),
    );
  }
}

class _UserBlock extends StatelessWidget {
  final bool showName;
  const _UserBlock({required this.showName});

  @override
  Widget build(BuildContext context) {
    final auth = AuthScope.of(context);
    final k = context.tk;
    final t = Theme.of(context).textTheme;
    final name = auth.username ?? '';
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Avatar(name, size: 34),
      if (showName) ...[
        const SizedBox(width: 10),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 140),
          child: Text(name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.bodyMedium!
                  .copyWith(fontWeight: FontWeight.w500, color: k.ink2)),
        ),
      ],
      const SizedBox(width: 8),
      IconBtn(
        icon: Icons.logout_rounded,
        tooltip: 'Log out',
        outlined: true,
        size: 36,
        onPressed: auth.logout,
      ),
    ]);
  }
}

// -------------------------------------------------------------------- phone

class _PhoneBar extends StatelessWidget {
  const _PhoneBar();

  @override
  Widget build(BuildContext context) {
    final auth = AuthScope.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(children: [
        const Expanded(
            child: Align(alignment: Alignment.centerLeft, child: Logo())),
        Avatar(auth.username ?? '', size: 34),
        const SizedBox(width: 8),
        IconBtn(
            icon: Icons.logout_rounded,
            tooltip: 'Log out',
            outlined: true,
            size: 40,
            onPressed: auth.logout),
      ]),
    );
  }
}

/// A floating glass pill with every section, icon over label.
class _BottomNav extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onSelect;
  const _BottomNav({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final k = context.tk;
    return Semantics(
      container: true,
      label: 'Main navigation',
      child: Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: k.deep,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: k.line2),
          boxShadow: const [
            BoxShadow(
                color: Color(0xB3000000), blurRadius: 32, offset: Offset(0, 12))
          ],
        ),
        child: Row(children: [
          for (var i = 0; i < _sections.length; i++)
            Expanded(
              child: Semantics(
                button: true,
                selected: i == selected,
                label: _sections[i].title,
                excludeSemantics: true,
                onTap: () => onSelect(i),
                child: InkWell(
                  onTap: () => onSelect(i),
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    decoration: BoxDecoration(
                      color: i == selected ? k.strong : Colors.transparent,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: MediaQuery(
                        data: MediaQuery.of(context).copyWith(
                            textScaler: MediaQuery.textScalerOf(context)
                                .clamp(maxScaleFactor: 1.15)),
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                          Icon(_sections[i].icon,
                              size: 20, color: i == selected ? k.ink : k.ink4),
                          const SizedBox(height: 2),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(_sections[i].title,
                                maxLines: 1,
                                style: TextStyle(
                                    fontFamily: sans,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    color:
                                        i == selected ? Colors.white : k.ink4)),
                          ),
                        ])),
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}
