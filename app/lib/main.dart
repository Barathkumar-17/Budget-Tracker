import 'package:flutter/material.dart';

import 'auth.dart';
import 'auth_screen.dart';
import 'budgets.dart';
import 'common.dart';
import 'dashboard.dart';
import 'expenses.dart';
import 'goals.dart';
import 'recurring.dart';
import 'theme.dart';
import 'widgets.dart';

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
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: ThemeMode.system,
        home: const _Gate(),
      ),
    );
  }
}

/// Shows the login screen until someone is logged in, then the app.
class _Gate extends StatelessWidget {
  const _Gate();

  @override
  Widget build(BuildContext context) {
    final auth = AuthScope.of(context);
    return switch (auth.status) {
      AuthStatus.loading =>
        const Scaffold(body: Center(child: CircularProgressIndicator())),
      AuthStatus.unreachable =>
        Scaffold(body: ErrorState(onRetry: auth.restore)),
      AuthStatus.loggedOut => const AuthScreen(),
      // A new key per user, so nothing from the previous account can linger.
      AuthStatus.loggedIn => _Session(key: ValueKey(auth.username)),
    };
  }
}

/// One logged-in session: its own month and reload state.
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

class _Tab {
  final String title;
  final IconData icon;
  final IconData selectedIcon;
  final bool monthly;
  const _Tab(this.title, this.icon, this.selectedIcon, {this.monthly = true});
}

const _tabs = [
  _Tab('Dashboard', Icons.dashboard_outlined, Icons.dashboard),
  _Tab('Expenses', Icons.receipt_long_outlined, Icons.receipt_long),
  _Tab('Budgets', Icons.pie_chart_outline, Icons.pie_chart),
  _Tab('Recurring', Icons.repeat, Icons.repeat_on),
  _Tab('Goals', Icons.savings_outlined, Icons.savings, monthly: false),
];

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _i = 0;

  Widget _page(int i) => switch (i) {
        0 => const DashboardScreen(),
        1 => const ExpensesScreen(),
        2 => const BudgetsScreen(),
        3 => const RecurringScreen(),
        _ => const GoalsScreen(),
      };

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 720;
    final still = MediaQuery.of(context).disableAnimations;
    final tab = _tabs[_i];
    final body = AnimatedSwitcher(
      duration: still ? Duration.zero : const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutCubic,
      child: KeyedSubtree(key: ValueKey(_i), child: _page(_i)),
    );

    return PopScope(
      // System Back from any other tab returns to the dashboard first.
      canPop: _i == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _i = 0);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(tab.title),
          actions: [
            if (_i == 0)
              IconButton(
                tooltip: 'Balance settings',
                icon: const Icon(Icons.tune),
                onPressed: () => editAccount(context),
              ),
            const _AccountMenu(),
            const SizedBox(width: 4),
          ],
          bottom: tab.monthly ? const MonthBar() : null,
        ),
        body: wide
            ? Row(children: [
                NavigationRail(
                  selectedIndex: _i,
                  labelType: NavigationRailLabelType.all,
                  onDestinationSelected: (i) => setState(() => _i = i),
                  destinations: [
                    for (final t in _tabs)
                      NavigationRailDestination(
                        icon: Icon(t.icon),
                        selectedIcon: Icon(t.selectedIcon),
                        label: Text(t.title),
                      ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 640),
                        child: body),
                  ),
                ),
              ])
            : body,
        bottomNavigationBar: wide
            ? null
            : NavigationBar(
                selectedIndex: _i,
                onDestinationSelected: (i) => setState(() => _i = i),
                destinations: [
                  for (final t in _tabs)
                    NavigationDestination(
                        icon: Icon(t.icon),
                        selectedIcon: Icon(t.selectedIcon),
                        label: t.title),
                ],
              ),
      ),
    );
  }
}

class _AccountMenu extends StatelessWidget {
  const _AccountMenu();

  @override
  Widget build(BuildContext context) {
    final auth = AuthScope.of(context);
    return PopupMenuButton<String>(
      tooltip: 'Account',
      icon: const Icon(Icons.account_circle_outlined),
      onSelected: (v) {
        if (v == 'logout') auth.logout();
      },
      itemBuilder: (_) => [
        PopupMenuItem(
            enabled: false,
            value: 'who',
            child: Text('Signed in as ${auth.username}')),
        const PopupMenuItem(value: 'logout', child: Text('Log out')),
      ],
    );
  }
}
