import 'dart:typed_data';

import 'package:excel/excel.dart' as xl;
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/api.dart';
import '../../core/book.dart';
import '../../core/format.dart';
import '../money.dart';
import 'trans_common.dart';

const _xlsxType = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

const _headers = [
  'Date', 'Account', 'Category', 'Subcategory', 'Note', 'Amount', 'Currency', 'Type', 'Description', 'To account', 'Tags',
];

String _two(int n) => n.toString().padLeft(2, '0');

String _kindWord(String kind) => switch (kind) {
      'income' => 'Income',
      'transfer' => 'Transfer',
      _ => 'Expense',
    };

/// The period's transactions (with the filter) as an .xlsx file, handed to
/// the share sheet (a download on the web). Returns false when there was
/// nothing to export.
Future<bool> trExportExcel(BuildContext context, {required Period period, required Map<String, dynamic> filter}) async {
  final b = Me.instance.book;
  if (b == null) return false;
  Rect? origin;
  final box = context.findRenderObject();
  if (box is RenderBox && box.hasSize) origin = box.localToGlobal(Offset.zero) & box.size;
  final label = period.label(b);

  final res = await Api.instance.rpc('txn_list', {...period.args, 'f': filter, 'max_rows': 10000});
  final txns = trRows(res).map(Txn.new).toList();
  if (txns.isEmpty) return false;

  final book = xl.Excel.createExcel();
  book.rename('Sheet1', 'Transactions');
  final sheet = book['Transactions'];
  sheet.appendRow(<xl.CellValue?>[for (final h in _headers) xl.TextCellValue(h)]);
  // Oldest first, as a sheet is read.
  for (final t in txns.reversed) {
    final at = t.at;
    final split = t.splits.isNotEmpty;
    final category = t.kind == 'transfer' ? '' : (split ? 'Split' : (t.parent ?? t.category ?? ''));
    final sub = split
        ? t.splits.map((s) => '${s['category'] ?? 'Uncategorised'} ${amountText(toNum(s['amount']), t.currency)}').join(', ')
        : (t.parent != null ? (t.category ?? '') : '');
    sheet.appendRow(<xl.CellValue?>[
      xl.TextCellValue('${isoDay(at)} ${_two(at.hour)}:${_two(at.minute)}'),
      xl.TextCellValue(t.account),
      xl.TextCellValue(category),
      xl.TextCellValue(sub),
      xl.TextCellValue(t.note ?? ''),
      xl.DoubleCellValue(t.amount.toDouble()),
      xl.TextCellValue(t.currency),
      xl.TextCellValue(_kindWord(t.kind)),
      xl.TextCellValue(t.description ?? ''),
      xl.TextCellValue(t.toAccount),
      xl.TextCellValue(t.tags.join(', ')),
    ]);
  }
  final bytes = book.encode();
  if (bytes == null) throw ApiError('The Excel file could not be made.');

  final name = 'Pursee ${label.replaceAll(RegExp(r'[^A-Za-z0-9 ._-]'), '-')}.xlsx';
  await SharePlus.instance.share(ShareParams(
    files: [XFile.fromData(Uint8List.fromList(bytes), name: name, mimeType: _xlsxType)],
    fileNameOverrides: [name],
    subject: name,
    sharePositionOrigin: origin,
  ));
  return true;
}
