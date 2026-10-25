import 'package:budget_tracker/common.dart';
import 'package:budget_tracker/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('money', () {
    test('whole rupees drop the decimals', () {
      expect(money(0), '₹0');
      expect(money(150), '₹150');
      expect(money(999.0), '₹999');
    });

    test('paise show when present', () {
      expect(money(4226.5), '₹4,226.50');
      expect(money(0.05), '₹0.05');
      expect(money(12.345), '₹12.35');
    });

    test('Indian digit grouping', () {
      expect(money(1000), '₹1,000');
      expect(money(150000), '₹1,50,000');
      expect(money(12345678), '₹1,23,45,678');
    });

    test('negative amounts use a real minus sign', () {
      expect(money(-50), '−₹50');
      expect(money(-0.001), '₹0');
    });
  });

  group('labels', () {
    final now = DateTime(2026, 10, 25);

    test('dayLabel names today, yesterday and older days', () {
      expect(dayLabel('2026-10-25', now: now), 'Today');
      expect(dayLabel('2026-10-24', now: now), 'Yesterday');
      expect(dayLabel('2026-10-23', now: now), 'Fri, 23 Oct');
      expect(dayLabel('not-a-date', now: now), 'not-a-date');
    });

    test('monthLabel, monthKey, dateKey', () {
      expect(monthLabel(DateTime(2026, 3)), 'March 2026');
      expect(monthKey(DateTime(2026, 3, 9)), '2026-03');
      expect(dateKey(DateTime(2026, 3, 9)), '2026-03-09');
    });

    test('titleCase capitalises each word', () {
      expect(titleCase('food'), 'Food');
      expect(titleCase('eating out'), 'Eating Out');
      expect(titleCase(''), '');
    });
  });

  group('category colours', () {
    test('are stable, case-insensitive and distinct for the common categories', () {
      expect(categoryColor('Food', Brightness.light), categoryColor(' food ', Brightness.light));
      final names = ['food', 'transport', 'rent', 'fun', 'shopping', 'bills', 'health', 'subscriptions', 'gym'];
      final colors = {for (final n in names) categoryColor(n, Brightness.light)};
      expect(colors.length, names.length);
    });

    test('dark palette differs from light', () {
      expect(categoryColor('food', Brightness.dark), isNot(categoryColor('food', Brightness.light)));
    });

    test('unknown names still get a palette colour', () {
      expect(categoryColor('zzz-unknown', Brightness.light), isA<Color>());
    });
  });
}
