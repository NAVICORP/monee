import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:monee/ui/more/excel_io.dart';

/// A Money Manager export (names and amounts changed): two Account columns,
/// the main currency's column, and accounts in SAR, INR and BHD.
void main() {
  test('a Money Manager file imports with each account in its own currency', () {
    final bytes = File('test/fixtures/money_manager_export.xlsx').readAsBytesSync();
    final p = parseExcelForTest(bytes, 'SAR');
    expect(p.error, isNull);
    expect(p.rows.length, 2013);
    expect(p.skipped, 0);
    final currencies = {for (final r in p.rows) r['currency']};
    expect(currencies, containsAll(['SAR', 'INR', 'BHD']));
    for (final r in p.rows) {
      // A tiny amount that rounds to 0 in SAR has no rate; the book's is used.
      if (r['currency'] != 'SAR' && (r['amount'] as num) >= 1) expect(r['rate'], isNotNull, reason: '$r');
      if (r['rate'] != null) expect((r['rate'] as num) > 0, isTrue, reason: '$r');
      if (r['kind'] == 'transfer') {
        expect(r['to_account'], isNotEmpty, reason: '$r');
        expect(r['to_amount'], isNotNull, reason: '$r');
      }
    }
  });
}
