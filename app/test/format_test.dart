import 'package:flutter_test/flutter_test.dart';
import 'package:monee/core/book.dart';
import 'package:monee/core/format.dart';

void main() {
  test('money keeps each currency\'s decimals and grouping', () {
    expect(money(150000, 'INR'), '₹1,50,000.00');
    expect(money(1287.2, 'SAR'), 'SAR 1,287.20');
    expect(money(4.7, 'BHD'), 'BD 4.700');
    expect(money(-25.5, 'USD'), r'-$25.50');
    expect(money(1200, 'JPY'), '¥1,200');
    expect(amountText(0.004, 'SAR'), '0.00');
  });

  test('a month can start on any day', () {
    final b = Book({'book_id': 'x', 'month_start_day': 25, 'week_start': 0});
    expect(b.month(2026, 10), (DateTime(2026, 10, 25), DateTime(2026, 11, 24)));
    expect(b.monthOf(DateTime(2026, 11, 2)), (2026, 10));
    final last = Book({'book_id': 'x', 'month_start_day': 31});
    expect(last.month(2026, 2), (DateTime(2026, 2, 28), DateTime(2026, 3, 30)));
  });

  test('weeks start on the book\'s day', () {
    final sun = Book({'book_id': 'x', 'week_start': 0});
    expect(sun.week(DateTime(2026, 10, 28)), (DateTime(2026, 10, 25), DateTime(2026, 10, 31)));
    final mon = Book({'book_id': 'x', 'week_start': 1});
    expect(mon.week(DateTime(2026, 10, 25)), (DateTime(2026, 10, 19), DateTime(2026, 10, 25)));
    expect(mon.weekdayNames.first, 'Mon');
  });

  test('a financial year from April', () {
    final b = Book({'book_id': 'x', 'fy_start_month': 4});
    expect(b.year(DateTime(2026, 2, 1)), (DateTime(2025, 4, 1), DateTime(2026, 3, 31)));
  });
}
