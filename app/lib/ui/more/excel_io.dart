import 'dart:typed_data';

import 'package:excel/excel.dart' as xl;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/api.dart';
import '../../core/book.dart';
import '../../core/format.dart';
import '../money.dart';
import '../theme.dart';
import '../widgets.dart';
import 'more_common.dart';
import 'passcode.dart';

const _xlsxMime = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

/// A first and a last day.
typedef _Days = (DateTime, DateTime);

// ================================================================ export

/// More > Export to Excel: pick a period, then share an .xlsx of every entry
/// in it (one row per entry, one row per part of a split).
Future<void> exportToExcel(BuildContext context) async {
  if (Me.instance.book == null) return;
  await showKSheet<void>(context, title: 'Export to Excel', builder: (ctx) => const _ExportSheet());
}

class _ExportSheet extends StatefulWidget {
  const _ExportSheet();

  @override
  State<_ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends State<_ExportSheet> {
  late DateTime from;
  late DateTime to;
  String label = 'This year';
  bool busy = false;
  String? error;

  Book get _book => Me.instance.book!;

  @override
  void initState() {
    super.initState();
    final b = _book;
    final (f, t) = b.year(b.today);
    from = f;
    to = t;
  }

  Future<void> _choose() async {
    final b = _book;
    final today = b.today;
    final (y, m) = b.monthOf(today);
    final thisMonth = b.month(y, m);
    final lastMonth = m == 1 ? b.month(y - 1, 12) : b.month(y, m - 1);
    final thisYear = b.year(today);
    final lastYear = b.year(DateTime(today.year - 1, today.month, today.day > 28 ? 28 : today.day));
    final everything = (DateTime(2000, 1, 1), addDays(today, 3660));
    final p = await showPicker<String>(context, title: 'Period', options: [
      PickOption('This month', 'This month', sub: periodLabel(thisMonth.$1, thisMonth.$2)),
      PickOption('Last month', 'Last month', sub: periodLabel(lastMonth.$1, lastMonth.$2)),
      PickOption('This year', 'This year', sub: periodLabel(thisYear.$1, thisYear.$2)),
      PickOption('Last year', 'Last year', sub: periodLabel(lastYear.$1, lastYear.$2)),
      const PickOption('Everything', 'Everything', sub: 'Every entry in the book'),
      const PickOption('pick', 'Pick the days'),
    ]);
    if (p == null || !mounted) return;
    final _Days? quick = switch (p.value) {
      'This month' => thisMonth,
      'Last month' => lastMonth,
      'This year' => thisYear,
      'Last year' => lastYear,
      'Everything' => everything,
      _ => null,
    };
    final _Days picked;
    final String name;
    if (quick != null) {
      picked = quick;
      name = p.value;
    } else {
      final custom = await pickPeriod(context, from: from, to: to);
      if (custom == null || !mounted) return;
      picked = custom;
      name = periodLabel(custom.$1, custom.$2);
    }
    setState(() {
      from = picked.$1;
      to = picked.$2;
      label = name;
      error = null;
    });
  }

  Future<void> _export() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final r = await Api.instance.rpc('txn_list', {
        'date_from': isoDay(from),
        'date_to': isoDay(to),
        'f': <String, dynamic>{},
        'max_rows': 10000,
      });
      final list = (r is List ? r : const []).whereType<Map>().map((e) => Txn(Map<String, dynamic>.from(e))).toList();
      if (list.isEmpty) {
        if (mounted) setState(() => error = 'No entries in this period.');
        return;
      }
      final rows = <List<Object?>>[];
      for (final t in list.reversed) {
        rows.addAll(_exportLines(t));
      }
      final bytes = await compute(_encodeXlsx, rows);
      if (bytes == null) throw StateError('no bytes');
      if (!mounted) return;
      final name = 'Pursee ${isoDay(from)} to ${isoDay(to)}.xlsx';
      final box = context.findRenderObject() as RenderBox?;
      final origin = box == null || !box.hasSize ? null : box.localToGlobal(Offset.zero) & box.size;
      Passcode.holdBriefly();
      await SharePlus.instance.share(ShareParams(
        files: [XFile.fromData(bytes, name: name, mimeType: _xlsxMime)],
        fileNameOverrides: [name],
        subject: 'Pursee export, $label',
        sharePositionOrigin: origin,
      ));
      if (!mounted) return;
      toast(context, list.length >= 10000 ? 'Exported the latest 10000 entries. Pick a shorter period for the rest.' : 'Exported ${list.length} entries');
      Navigator.of(context).pop();
    } on ApiError catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) setState(() => error = 'The Excel file could not be made or shared. Try again.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (error != null) ...[Notice(error!), const SizedBox(height: Sp.md)],
      KChoice(label: 'Period', value: label == periodLabel(from, to) ? label : '$label, ${periodLabel(from, to)}', icon: Icons.date_range_outlined, onTap: busy ? null : _choose),
      const SizedBox(height: Sp.sm),
      Text('Columns: Date, Type, Account, To account, Category, Subcategory, Amount, Currency, Note, Description and Tags. Import reads the same file back.',
          style: T.small),
      const SizedBox(height: Sp.lg),
      KButton(label: 'Make the Excel file', icon: Icons.ios_share_rounded, expand: true, busy: busy, onPressed: _export),
    ]);
  }
}

/// One entry as spreadsheet rows (a split gives one row per part): plain
/// values (DateTime, String, double or null) so the file can be made away
/// from the screen's thread.
List<List<Object?>> _exportLines(Txn t) {
  String? s(String? v) => v == null || v.trim().isEmpty ? null : v;
  final type = switch (t.kind) { 'income' => 'Income', 'transfer' => 'Transfer', _ => 'Expense' };
  final tags = t.tags.isEmpty ? null : t.tags.join(', ');
  if (t.kind != 'transfer' && t.splits.isNotEmpty) {
    final parts = <List<Object?>>[];
    for (final p in t.splits) {
      final c = Me.instance.category(p['category_id'] as String?);
      final parent = Me.instance.category(c?.parentId);
      parts.add(<Object?>[
        t.at,
        type,
        s(t.account),
        null,
        s(parent?.name ?? c?.name ?? p['category'] as String?),
        parent == null ? null : s(c?.name),
        toNum(p['amount']).toDouble(),
        t.currency,
        s(p['note'] as String? ?? t.note),
        s(t.description),
        tags,
      ]);
    }
    return parts;
  }
  return [
    <Object?>[
      t.at,
      type,
      s(t.account),
      t.kind == 'transfer' ? s(t.toAccount) : null,
      t.kind == 'transfer' ? null : s(t.parent ?? t.category),
      t.kind == 'transfer' || t.parent == null ? null : s(t.category),
      t.amount.toDouble(),
      t.currency,
      s(t.note),
      s(t.description),
      tags,
    ],
  ];
}

const _headers = ['Date', 'Type', 'Account', 'To account', 'Category', 'Subcategory', 'Amount', 'Currency', 'Note', 'Description', 'Tags'];
const _widths = [18.0, 10.0, 18.0, 18.0, 18.0, 16.0, 12.0, 9.0, 24.0, 30.0, 16.0];

/// The .xlsx file for the rows (runs in a background isolate on phones).
Uint8List? _encodeXlsx(List<List<Object?>> rows) {
  final book = xl.Excel.createExcel();
  final first = book.getDefaultSheet() ?? 'Sheet1';
  var name = first;
  try {
    if (first != 'Pursee') {
      book.rename(first, 'Pursee');
      name = 'Pursee';
    }
  } catch (_) {
    name = first;
  }
  final sheet = book[name];
  sheet.appendRow([for (final h in _headers) xl.TextCellValue(h)]);
  final bold = xl.CellStyle(bold: true);
  for (var c = 0; c < _headers.length; c++) {
    sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0)).cellStyle = bold;
    sheet.setColumnWidth(c, _widths[c]);
  }
  for (final r in rows) {
    sheet.appendRow([
      for (final v in r)
        if (v is DateTime)
          xl.DateTimeCellValue.fromDateTime(v)
        else if (v is double)
          xl.DoubleCellValue(v)
        else if (v is String)
          xl.TextCellValue(v)
        else
          null,
    ]);
  }
  final bytes = book.encode();
  return bytes == null ? null : Uint8List.fromList(bytes);
}

// ================================================================ import

/// More > Import from Excel: pick an .xlsx (Pursee's own export, Money
/// Manager's backup, or any sheet with Date and Amount columns), check a
/// preview, then add every row to the book.
Future<void> importFromExcel(BuildContext context) async {
  final b = Me.instance.book;
  if (b == null) return;
  if (!b.canEdit) {
    toast(context, 'You can look at this book but not change it.', bad: true);
    return;
  }
  Passcode.holdBriefly();
  FilePickerResult? picked;
  try {
    picked = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx'], withData: true);
  } catch (_) {
    if (context.mounted) toast(context, 'The file could not be opened. Try again.', bad: true);
    return;
  }
  if (picked == null || picked.files.isEmpty || !context.mounted) return;
  final file = picked.files.first;
  final bytes = file.bytes;
  if (bytes == null) {
    toast(context, 'That file could not be read. Try again.', bad: true);
    return;
  }
  _Parsed data;
  try {
    data = await compute(_parseXlsx, _ParseInput(bytes, b.currency));
  } catch (_) {
    if (context.mounted) {
      toast(context, 'That file could not be read. Only .xlsx files work: open it in Excel or Google Sheets and save it as .xlsx.', bad: true);
    }
    return;
  }
  if (!context.mounted) return;
  if (data.error != null) {
    toast(context, data.error!, bad: true);
    return;
  }
  await openPage<void>(context, _ImportPage(fileName: file.name, data: data));
}

class _ParseInput {
  const _ParseInput(this.bytes, this.mainCurrency);
  final Uint8List bytes;
  final String mainCurrency;
}

/// One row to import.
class _Row {
  _Row({
    required this.at,
    required this.kind,
    required this.account,
    required this.toAccount,
    required this.category,
    required this.subcategory,
    required this.amount,
    required this.currency,
    required this.note,
    required this.description,
    this.tags = const [],
    this.accountAmount,
    this.mainAmount,
  });
  final DateTime at;
  final String kind;
  String account;
  String toAccount;
  String category;
  final String subcategory;
  final num amount;
  final String currency;
  final String note;
  final String description;
  final List<String> tags;

  /// Money Manager's second Account column: the amount in the account's own
  /// currency (the typed amount can be in another currency).
  final num? accountAmount;

  /// The amount in the main currency (Money Manager's column named after it).
  final num? mainAmount;

  /// Worked out from the whole file (see _settle).
  String accountCurrency = '';
  num bookedAmount = 0;
  num? rate;
  String toCurrency = '';
  num? toAmount;

  Map<String, dynamic> toJson() => {
        'date': '${isoStamp(at).substring(0, 16)}:${at.second.toString().padLeft(2, '0')}',
        'kind': kind,
        'account': account,
        if (kind == 'transfer') 'to_account': toAccount,
        if (kind != 'transfer' && category.isNotEmpty) 'category': category,
        if (kind != 'transfer' && subcategory.isNotEmpty) 'subcategory': subcategory,
        'amount': (bookedAmount > 0 ? bookedAmount : amount).abs(),
        if (accountCurrency.isNotEmpty) 'currency': accountCurrency else if (currency.isNotEmpty) 'currency': currency,
        if (rate != null) 'rate': rate,
        if (kind == 'transfer' && toCurrency.isNotEmpty) 'to_currency': toCurrency,
        if (kind == 'transfer' && toAmount != null) 'to_amount': toAmount,
        if (note.isNotEmpty) 'note': note,
        if (description.isNotEmpty) 'description': description,
        if (tags.isNotEmpty) 'tags': tags,
      };
}

class _Parsed {
  const _Parsed({this.rows = const [], this.skipped = 0, this.transferIns = 0, this.columns = const [], this.sheet = '', this.error});
  final List<_Row> rows;

  /// Rows without a date or an amount.
  final int skipped;

  /// Money Manager's Transfer-In rows, left out because their Transfer-Out
  /// rows already carry the transfer.
  final int transferIns;
  final List<String> columns;
  final String sheet;
  final String? error;
}

String _norm(String s) => s.trim().toLowerCase().replaceAll(RegExp(r'[\s_\-.]+'), ' ').trim();

const _names = <String, List<String>>{
  'date': ['date', 'period', 'time', 'day', 'date time', 'datetime', 'transaction date'],
  'kind': ['type', 'income/expense', 'income/expenses', 'kind', 'transaction type', 'in/out'],
  'account': ['account', 'accounts', 'from account', 'from', 'account name', 'wallet'],
  'to': ['to account', 'to', 'to accounts', 'transfer to'],
  'category': ['category', 'main category'],
  'sub': ['subcategory', 'sub category', 'sub'],
  'amount': ['amount', 'value', 'sum'],
  'currency': ['currency', 'currency code'],
  'note': ['note', 'notes', 'memo', 'title', 'payee'],
  'description': ['description', 'details', 'desc', 'remarks', 'comment', 'comments'],
  'tags': ['tag', 'tags', 'labels'],
};

/// The text of a cell.
String _text(xl.Data? d) {
  final v = d?.value;
  if (v == null) return '';
  if (v is xl.DoubleCellValue) {
    final x = v.value;
    return x == x.roundToDouble() ? x.round().toString() : x.toString();
  }
  if (v is xl.DateCellValue) return isoDay(DateTime(v.year, v.month, v.day));
  if (v is xl.DateTimeCellValue) return isoStamp(DateTime(v.year, v.month, v.day, v.hour, v.minute));
  return v.toString().trim();
}

DateTime? _checked(int y, int m, int d, [int h = 0, int min = 0, int s = 0]) {
  if (y < 100) y += 2000;
  if (y < 1970 || y > 2100 || m < 1 || m > 12 || d < 1 || d > 31 || h > 23 || min > 59 || s > 59) return null;
  final x = DateTime(y, m, d, h, min, s);
  return x.month == m && x.day == d ? x : null;
}

final _isoDate = RegExp(r'^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})(?:[ T](\d{1,2}):(\d{2})(?::(\d{2}))?)?');
final _dmyDate = RegExp(r'^(\d{1,2})[-/.](\d{1,2})[-/.](\d{2,4})(?:[ T,]+(\d{1,2}):(\d{2})(?::(\d{2}))?\s*([AaPp][Mm])?)?');

DateTime? _dateText(String raw, bool dayFirst) {
  final s = raw.trim();
  var m = _isoDate.firstMatch(s);
  if (m != null) {
    return _checked(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!), int.tryParse(m[4] ?? '') ?? 0, int.tryParse(m[5] ?? '') ?? 0,
        int.tryParse(m[6] ?? '') ?? 0);
  }
  m = _dmyDate.firstMatch(s);
  if (m != null) {
    final a = int.parse(m[1]!), b = int.parse(m[2]!), y = int.parse(m[3]!);
    var h = int.tryParse(m[4] ?? '') ?? 0;
    final ap = (m[7] ?? '').toLowerCase();
    if (ap == 'pm' && h < 12) h += 12;
    if (ap == 'am' && h == 12) h = 0;
    final min = int.tryParse(m[5] ?? '') ?? 0, sec = int.tryParse(m[6] ?? '') ?? 0;
    final dayFirstHere = a > 12 ? true : (b > 12 ? false : dayFirst);
    return dayFirstHere ? _checked(y, b, a, h, min, sec) : _checked(y, a, b, h, min, sec);
  }
  return null;
}

/// Excel's own day numbers (days since 30 Dec 1899).
DateTime? _serial(double v) {
  if (v < 20000 || v > 80000) return null;
  final u = DateTime.utc(1899, 12, 30).add(Duration(milliseconds: (v * 86400000).round()));
  return DateTime(u.year, u.month, u.day, u.hour, u.minute, u.second);
}

DateTime? _date(xl.Data? d, bool dayFirst) {
  final v = d?.value;
  if (v == null) return null;
  if (v is xl.DateTimeCellValue) return _checked(v.year, v.month, v.day, v.hour, v.minute, v.second);
  if (v is xl.DateCellValue) return _checked(v.year, v.month, v.day);
  if (v is xl.DoubleCellValue) return _serial(v.value);
  if (v is xl.IntCellValue) return _serial(v.value.toDouble());
  return _dateText(v.toString(), dayFirst);
}

num? _amount(xl.Data? d) {
  final v = d?.value;
  if (v == null) return null;
  if (v is xl.IntCellValue) return v.value;
  if (v is xl.DoubleCellValue) return v.value;
  var s = v.toString().trim();
  if (s.isEmpty) return null;
  final negative = s.startsWith('-') || s.startsWith('(') || s.endsWith('-');
  s = s.replaceAll(RegExp(r'[^0-9.,]'), '');
  if (s.isEmpty) return null;
  final dot = s.lastIndexOf('.'), comma = s.lastIndexOf(',');
  if (dot >= 0 && comma >= 0) {
    s = comma > dot ? s.replaceAll('.', '').replaceAll(',', '.') : s.replaceAll(',', '');
  } else if (comma >= 0) {
    final tail = s.length - comma - 1;
    s = (tail == 1 || tail == 2) && ','.allMatches(s).length == 1 ? s.replaceAll(',', '.') : s.replaceAll(',', '');
  }
  final n = num.tryParse(s);
  if (n == null) return null;
  return negative ? -n : n;
}

/// income, expense, transfer, transfer_in (Money Manager's other half of a
/// transfer), or null when the words say nothing.
String? _kind(String raw) {
  final s = raw.trim().toLowerCase();
  if (s.isEmpty) return null;
  if (s.contains('transfer')) {
    final rest = s.replaceAll('transfer', '');
    return rest.contains('in') && !rest.contains('out') ? 'transfer_in' : 'transfer';
  }
  if (s.startsWith('inc') || const {'in', 'credit', 'cr', 'deposit', 'received', 'income'}.contains(s)) return 'income';
  if (s.startsWith('exp') || const {'out', 'debit', 'dr', 'spent', 'withdrawal', 'expense'}.contains(s)) return 'expense';
  return null;
}

String _cut(String s, int n) => s.length <= n ? s : s.substring(0, n);

/// Reads the first sheet that has a header row with a date and an amount.
_Parsed _parseXlsx(_ParseInput input) {
  final excel = xl.Excel.decodeBytes(input.bytes);
  final codes = {for (final c in kCurrencies) c.code, input.mainCurrency};
  for (final entry in excel.tables.entries) {
    final rows = entry.value.rows;
    if (rows.length < 2) continue;
    // The header row: within the first rows, the first with a date and an amount.
    for (var h = 0; h < rows.length && h < 15; h++) {
      final col = <String, int>{};
      int? mainCol;
      final found = <String>[];
      for (var c = 0; c < rows[h].length; c++) {
        final raw = _text(rows[h][c]);
        if (raw.isEmpty) continue;
        final n = _norm(raw);
        var matched = false;
        // Money Manager has two Account columns: the name, then the amount
        // in that account's own currency.
        if (n == 'account' && col.containsKey('account') && !col.containsKey('acct_amount')) {
          col['acct_amount'] = c;
          found.add('$raw (amount in the account\'s currency)');
          continue;
        }
        for (final e in _names.entries) {
          if (!col.containsKey(e.key) && e.value.contains(n)) {
            col[e.key] = c;
            matched = true;
            break;
          }
        }
        if (!matched && mainCol == null && codes.contains(raw.trim().toUpperCase())) {
          mainCol = c;
          matched = true;
        }
        if (matched) found.add(raw);
      }
      if (!col.containsKey('date') || (!col.containsKey('amount') && mainCol == null)) continue;
      return _readRows(rows, h, col, mainCol, found, entry.key, input.mainCurrency);
    }
  }
  return const _Parsed(error: 'No sheet with a Date and an Amount column was found. Put the column names in the first row.');
}

_Parsed _readRows(List<List<xl.Data?>> rows, int h, Map<String, int> col, int? mainCol, List<String> found, String sheet, String main) {
  xl.Data? cell(List<xl.Data?> r, String key) {
    final c = col[key];
    return c == null || c >= r.length ? null : r[c];
  }

  String text(List<xl.Data?> r, String key) => _text(cell(r, key));

  num? amountOf(List<xl.Data?> r) {
    final a = col.containsKey('amount') ? _amount(cell(r, 'amount')) : null;
    if (a != null && a != 0) return a;
    final mc = mainCol;
    if (mc != null && mc < r.length) return _amount(r[mc]);
    return a;
  }

  // Day first (28/10/2026) unless the dates themselves say month first.
  var dayFirstSeen = 0, monthFirstSeen = 0;
  var negatives = false;
  for (var i = h + 1; i < rows.length; i++) {
    final m = _dmyDate.firstMatch(text(rows[i], 'date'));
    if (m != null) {
      if (int.parse(m[1]!) > 12) dayFirstSeen++;
      if (int.parse(m[2]!) > 12) monthFirstSeen++;
    }
    final a = amountOf(rows[i]);
    if (a != null && a < 0) negatives = true;
  }
  final dayFirst = !(monthFirstSeen > 0 && dayFirstSeen == 0);

  final out = <_Row>[];
  final ins = <_Row>[];
  var skipped = 0;
  for (var i = h + 1; i < rows.length; i++) {
    final r = rows[i];
    if (r.every((d) => _text(d).isEmpty)) continue;
    final at = _date(cell(r, 'date'), dayFirst);
    final amount = amountOf(r);
    if (at == null || amount == null || amount == 0) {
      skipped++;
      continue;
    }
    final kind = _kind(text(r, 'kind')) ?? (amount < 0 || !negatives ? 'expense' : 'income');
    final cur = text(r, 'currency').toUpperCase();
    final row = _Row(
      at: at,
      kind: kind == 'transfer_in' ? 'transfer' : kind,
      account: _cut(text(r, 'account'), 60),
      toAccount: _cut(text(r, 'to'), 60),
      category: _cut(text(r, 'category'), 40),
      subcategory: _cut(text(r, 'sub'), 40),
      amount: amount.abs(),
      currency: RegExp(r'^[A-Z]{3}$').hasMatch(cur) ? cur : '',
      note: _cut(text(r, 'note'), 120),
      description: _cut(text(r, 'description'), 2000),
      tags: [
        for (final t in text(r, 'tags').split(RegExp(r'[,#]')))
          if (t.trim().isNotEmpty) _cut(t.trim(), 30),
      ],
      accountAmount: col.containsKey('acct_amount') ? _amount(cell(r, 'acct_amount'))?.abs() : null,
      mainAmount: mainCol != null && mainCol < r.length ? _amount(r[mainCol])?.abs() : null,
    );
    if (row.account.isEmpty) row.account = 'Imported';
    if (kind == 'transfer_in') {
      ins.add(row);
    } else {
      out.add(row);
    }
  }

  // Money Manager writes a transfer's other account in Category. Its
  // Transfer-In rows repeat the Transfer-Out ones; only when a file has no
  // Transfer-Out rows are they read (the other way round).
  final hasOut = out.any((r) => r.kind == 'transfer');
  // A Transfer-In row says how much arrived: keep it for its Transfer-Out.
  final arrived = <String, num>{};
  if (hasOut) {
    for (final r in ins) {
      final other = r.toAccount.isNotEmpty ? r.toAccount : r.category;
      final got = r.accountAmount ?? r.amount;
      arrived['${r.at.millisecondsSinceEpoch}|${other.toLowerCase()}|${r.account.toLowerCase()}'] = got;
    }
  }
  var transferIns = 0;
  if (!hasOut && ins.isNotEmpty) {
    for (final r in ins) {
      final other = r.toAccount.isNotEmpty ? r.toAccount : r.category;
      r.toAccount = r.account;
      r.account = other.isEmpty ? 'Imported' : _cut(other, 60);
      r.category = '';
      out.add(r);
    }
  } else {
    transferIns = ins.length;
  }
  final kept = <_Row>[];
  for (final r in out) {
    if (r.kind == 'transfer') {
      if (r.toAccount.isEmpty && r.category.isNotEmpty) {
        r.toAccount = _cut(r.category, 60);
        r.category = '';
      }
      if (r.toAccount.isEmpty || r.toAccount.toLowerCase() == r.account.toLowerCase()) {
        skipped++;
        continue;
      }
    }
    kept.add(r);
  }
  kept.sort((a, b) => a.at.compareTo(b.at));
  _settle(kept, main, arrived);
  return _Parsed(rows: kept, skipped: skipped, transferIns: transferIns, columns: found, sheet: sheet);
}

/// Works out each account's currency and the exact amounts, the way Money
/// Manager's file has them: the amount in the account's own currency, the
/// amount in the main currency (so the rate of that day), and for transfers
/// what arrived in the other account.
void _settle(List<_Row> rows, String main, Map<String, num> arrived) {
  bool same(num a, num b) => (a - b).abs() < 0.005;
  // An account's currency: the typed currency on rows where the typed amount
  // is the account's own amount.
  final votes = <String, Map<String, int>>{};
  void vote(String acc, String cur) {
    if (cur.isEmpty) return;
    final v = votes.putIfAbsent(acc.toLowerCase(), () => {});
    v[cur] = (v[cur] ?? 0) + 1;
  }

  for (final r in rows) {
    final own = r.accountAmount;
    if (own == null) {
      vote(r.account, r.currency);
    } else if (same(own, r.amount)) {
      vote(r.account, r.currency);
    }
  }
  final cur = <String, String>{};
  votes.forEach((acc, v) {
    final best = v.entries.reduce((a, b) => b.value > a.value ? b : a);
    cur[acc] = best.key;
  });
  // Rates seen in the file: main currency per unit, by currency, in date order.
  final seen = <String, List<(DateTime, num)>>{};
  for (final r in rows) {
    final c = cur[r.account.toLowerCase()];
    final own = r.accountAmount ?? r.amount;
    final m = r.mainAmount;
    if (c != null && c != main && m != null && m > 0 && own > 0) {
      seen.putIfAbsent(c, () => []).add((r.at, m / own));
    }
  }
  num? rateNear(String c, DateTime at) {
    if (c == main) return 1;
    final list = seen[c];
    if (list == null || list.isEmpty) return null;
    var best = list.first;
    for (final x in list) {
      if ((x.$1.difference(at)).abs() < (best.$1.difference(at)).abs()) best = x;
    }
    return best.$2;
  }

  // Accounts the file names only as a transfer's other side: an account's
  // own currency is not known, so it takes the sending account's.
  for (final r in rows) {
    final c = cur[r.account.toLowerCase()];
    // An account seen only with rows in another currency: the main amount
    // and the account amount say which currency it is.
    if (c == null) {
      final own = r.accountAmount;
      final m = r.mainAmount;
      if (own != null && m != null && same(own, m)) {
        cur[r.account.toLowerCase()] = main;
      } else {
        cur[r.account.toLowerCase()] = r.currency.isNotEmpty ? r.currency : main;
      }
    }
  }
  for (final r in rows) {
    final from = cur[r.account.toLowerCase()] ?? main;
    r.accountCurrency = from;
    r.bookedAmount = r.accountAmount ?? r.amount;
    final m = r.mainAmount;
    if (from == main) {
      r.rate = 1;
    } else if (m != null && m > 0 && r.bookedAmount > 0) {
      r.rate = double.parse((m / r.bookedAmount).toStringAsFixed(10));
    }
    if (r.kind != 'transfer') continue;
    final to = cur.putIfAbsent(r.toAccount.toLowerCase(), () => from);
    r.toCurrency = to;
    final got = arrived['${r.at.millisecondsSinceEpoch}|${r.account.toLowerCase()}|${r.toAccount.toLowerCase()}'];
    if (got != null) {
      r.toAmount = got;
    } else if (to == from) {
      r.toAmount = r.bookedAmount;
    } else if (to == main && m != null && m > 0) {
      r.toAmount = m;
    } else {
      final inMain = m ?? (r.rate == null ? null : r.bookedAmount * r.rate!);
      final toRate = rateNear(to, r.at);
      if (inMain != null && toRate != null && toRate > 0) {
        r.toAmount = double.parse((inMain / toRate).toStringAsFixed(2));
      }
    }
  }
}

/// The preview: how many rows, the first few, the totals, then Import.
class _ImportPage extends StatefulWidget {
  const _ImportPage({required this.fileName, required this.data});
  final String fileName;
  final _Parsed data;

  @override
  State<_ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends State<_ImportPage> {
  static const _chunk = 1000;
  bool busy = false;
  String? error;

  /// Rows sent so far (a failed chunk can be tried again from here).
  int sent = 0;
  int imported = 0;
  int accountsMade = 0;
  int categoriesMade = 0;

  /// Start the book over: its entries and accounts are replaced by the file's.
  bool fresh = false;

  Future<void> _import() async {
    final rows = widget.data.rows;
    if (fresh && sent == 0) {
      final ok = await confirm(context,
          title: 'Start this book over?',
          text: 'Every entry and account in this book is deleted, then the file is imported. This cannot be undone.',
          yes: 'Delete and import',
          danger: true);
      if (!ok || !mounted) return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      while (sent < rows.length) {
        final end = sent + _chunk < rows.length ? sent + _chunk : rows.length;
        final r = await Api.instance.rpc('import_rows', {
          'rows': [for (final x in rows.sublist(sent, end)) x.toJson()],
          'fresh': fresh && sent == 0,
        });
        if (r is Map) {
          imported += toNum(r['imported']).toInt();
          accountsMade += toNum(r['accounts_made']).toInt();
          categoriesMade += toNum(r['categories_made']).toInt();
        }
        sent = end;
        if (mounted) setState(() {});
      }
    } on ApiError catch (e) {
      if (imported > 0) await Me.instance.changed(lists: true);
      if (mounted) {
        setState(() {
          busy = false;
          error = imported == 0 ? e.message : '${e.message} The first $imported entries were imported; Import again carries on from there.';
        });
      }
      return;
    }
    await Me.instance.changed(lists: true);
    if (!mounted) return;
    final extra = [
      if (accountsMade > 0) '$accountsMade new account${accountsMade == 1 ? '' : 's'}',
      if (categoriesMade > 0) '$categoriesMade new categor${categoriesMade == 1 ? 'y' : 'ies'}',
    ];
    toast(context, 'Imported $imported entries${extra.isEmpty ? '' : ', ${extra.join(', ')}'}');
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final main = Me.instance.book?.currency;
    final rows = d.rows;
    num income = 0, expense = 0;
    var transfers = 0;
    for (final r in rows) {
      final inMain = r.mainAmount ?? (r.rate == null ? null : r.bookedAmount * r.rate!);
      if (r.kind == 'income') income += inMain ?? r.amount;
      if (r.kind == 'expense') expense += inMain ?? r.amount;
      if (r.kind == 'transfer') transfers++;
    }
    final mixed = rows.any((r) => r.mainAmount == null && r.rate == null && r.accountCurrency != main);
    final left = rows.length - sent;
    final notes = <String>[
      if (d.skipped > 0) '${d.skipped} row${d.skipped == 1 ? '' : 's'} without a date or an amount ${d.skipped == 1 ? 'is' : 'are'} left out.',
      if (d.transferIns > 0) '${d.transferIns} Transfer-In row${d.transferIns == 1 ? ' is' : 's are'} left out: the Transfer-Out rows carry those transfers.',
    ];
    return PopScope(
      canPop: !busy,
      child: Scaffold(
        appBar: AppBar(title: const Text('Import from Excel')),
        body: PageBody(children: [
          KCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.fileName, maxLines: 2, overflow: TextOverflow.ellipsis, style: T.h3),
              Text('${rows.length} entr${rows.length == 1 ? 'y' : 'ies'} to add, from the sheet ${d.sheet}', style: T.small),
              if (rows.isNotEmpty) Text('${dateLabel(rows.first.at)} to ${dateLabel(rows.last.at)}', style: T.small),
            ]),
          ),
          const SizedBox(height: Sp.sm),
          Row(children: [
            Expanded(child: StatTile(amountText(income, main), mixed ? 'Income, mixed currencies' : 'Income', tone: K.income)),
            const SizedBox(width: Sp.sm),
            Expanded(child: StatTile(amountText(expense, main), mixed ? 'Expenses, mixed currencies' : 'Expenses', tone: K.expense)),
            const SizedBox(width: Sp.sm),
            Expanded(child: StatTile('$transfers', 'Transfers', tone: K.transfer)),
          ]),
          for (final n in notes) ...[const SizedBox(height: Sp.sm), Notice(n, bad: false)],
          if (rows.isNotEmpty) ...[
            const SectionTitle('The first rows'),
            KGroup(children: [
              for (final r in rows.take(5))
                KRow(
                  title: r.kind == 'transfer'
                      ? '${r.account} to ${r.toAccount}'
                      : (r.category.isEmpty ? 'Uncategorised' : (r.subcategory.isEmpty ? r.category : '${r.category} / ${r.subcategory}')),
                  sub: [dateLabel(r.at), if (r.kind != 'transfer') r.account, if (r.note.isNotEmpty) r.note].join(', '),
                  trailing: MoneyText(r.bookedAmount > 0 ? r.bookedAmount : r.amount, currency: r.accountCurrency.isEmpty ? main : r.accountCurrency, kind: r.kind),
                ),
            ]),
          ],
          const SectionTitle('Columns read'),
          Text(d.columns.join(', '), style: T.small),
          const SizedBox(height: Sp.md),
          const Notice(
              'Accounts and categories that are not in this book yet are made for you: accounts go in Others, each in its own currency as the sheet shows it. Amounts keep the exchange rate of their own day.',
              bad: false),
          if ((Me.instance.book?.isOwner ?? false) && sent == 0) ...[
            const SizedBox(height: Sp.md),
            KCard(
              child: KSwitchRow(
                title: 'Start this book over',
                sub: 'Deletes every entry and account in this book first, so it matches the file exactly. Categories stay.',
                value: fresh,
                onChanged: busy ? null : (v) => setState(() => fresh = v),
              ),
            ),
          ],
          if (error != null) ...[const SizedBox(height: Sp.md), Notice(error!)],
          if (busy && rows.isNotEmpty) ...[
            const SizedBox(height: Sp.md),
            ProgressLine(sent / rows.length, color: K.blue, track: K.surface2, height: 6),
            const SizedBox(height: 4),
            Text('Added $sent of ${rows.length}', style: T.small),
          ],
          const SizedBox(height: Sp.lg),
          KButton(
            label: rows.isEmpty ? 'Nothing to import' : (sent == 0 ? 'Import ${rows.length} entr${rows.length == 1 ? 'y' : 'ies'}' : 'Import the other $left'),
            icon: Icons.file_download_outlined,
            expand: true,
            busy: busy,
            onPressed: rows.isEmpty || left <= 0 ? null : _import,
          ),
        ]),
      ),
    );
  }
}
