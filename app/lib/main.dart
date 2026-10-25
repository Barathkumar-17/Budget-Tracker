import 'package:flutter/material.dart';
import 'budgets.dart';
import 'dashboard.dart';
import 'expenses.dart';
import 'goals.dart';
import 'recurring.dart';

void main() => runApp(const BudgetApp());

class BudgetApp extends StatelessWidget {
  const BudgetApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Budget Tracker',
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      home: const Shell(),
    );
  }
}

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _i = 0;
  static const _titles = ['Dashboard', 'Expenses', 'Budgets', 'Recurring', 'Goals'];
  static const _pages = [
    DashboardScreen(),
    ExpensesScreen(),
    BudgetsScreen(),
    RecurringScreen(),
    GoalsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_titles[_i])),
      body: _pages[_i], // rebuilt per tab so each screen reloads fresh data
      bottomNavigationBar: NavigationBar(
        selectedIndex: _i,
        onDestinationSelected: (i) => setState(() => _i = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), label: 'Dashboard'),
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), label: 'Expenses'),
          NavigationDestination(icon: Icon(Icons.pie_chart_outline), label: 'Budgets'),
          NavigationDestination(icon: Icon(Icons.repeat), label: 'Recurring'),
          NavigationDestination(icon: Icon(Icons.savings_outlined), label: 'Goals'),
        ],
      ),
    );
  }
}
