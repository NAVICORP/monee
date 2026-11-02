import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/book.dart';
import '../../core/format.dart';
import '../money.dart';
import '../theme.dart';

// Small helpers shared by the Trans tab's files (not used outside trans/).

/// The rows of a database function's list answer.
List<Map<String, dynamic>> trRows(dynamic j) =>
    j is List ? j.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : <Map<String, dynamic>>[];

/// A database function's object answer.
Map<String, dynamic> trMap(dynamic j) => j is Map ? Map<String, dynamic>.from(j) : <String, dynamic>{};

/// Two periods covering the same days the same way.
bool trSamePeriod(Period a, Period b) => a.kind == b.kind && a.from == b.from && a.to == b.to;

/// Today on the book's own clock.
DateTime trToday() => Me.instance.book?.today ?? dayOnly(DateTime.now());

/// The later of two days.
DateTime trLater(DateTime a, DateTime b) => a.isAfter(b) ? a : b;

/// Words for anything that went wrong while loading.
String trError(Object e) => e is ApiError ? e.message : 'That did not load. Pull down to try again.';

/// What a row counts as, by the same rules as txn_list() in the database.
String trCountsAs(String kind, Account? from, Account? to) {
  if (kind == 'transfer' && from != null && to != null) {
    if (to.transferExpense && !from.transferExpense) return 'expense';
    if (from.transferExpense && !to.transferExpense) return 'income';
    return 'transfer';
  }
  if (kind == 'expense' && from != null && from.isCard && Me.instance.book?.cardDisplay == 'lump_sum') return 'card';
  return kind;
}

/// A repeat still to come (a row of upcoming()) as a row TxnRow can show.
Txn trUpcomingTxn(Map<String, dynamic> u) {
  final me = Me.instance;
  final acc = me.account(u['account_id'] as String?);
  final to = me.account(u['to_account_id'] as String?);
  final cat = me.category(u['category_id'] as String?);
  final parent = cat == null ? null : me.category(cat.parentId);
  final kind = u['kind'] as String? ?? 'expense';
  final day = '${u['day'] ?? ''}';
  return Txn(<String, dynamic>{
    'id': 'up-${u['repeat_id']}-$day',
    'kind': kind,
    'at': '${day}T00:00:00',
    'account_id': u['account_id'],
    'account': acc?.name ?? '',
    'currency': acc?.currency ?? me.book?.currency ?? 'INR',
    'to_account_id': u['to_account_id'],
    'to_account': to?.name,
    'to_currency': to?.currency,
    'category_id': u['category_id'],
    'category': cat?.name,
    'emoji': cat?.emoji,
    'parent_id': parent?.id,
    'parent': parent?.name,
    'parent_emoji': parent?.emoji,
    'amount': u['amount'],
    'amount_main': u['amount_main'],
    'counts_as': trCountsAs(kind, acc, to),
    'note': u['note'],
    'repeat_id': u['repeat_id'],
  });
}

/// Whether a repeat still to come passes the Trans tab's filter. Repeats carry
/// no tags, so a tag filter leaves them out.
bool trUpcomingPasses(Map<String, dynamic> u, Map<String, dynamic> f) {
  if (f.isEmpty) return true;
  final tags = f['tags'];
  if (tags is List && tags.isNotEmpty) return false;
  final accs = f['accounts'];
  if (accs is List && accs.isNotEmpty) {
    final a = u['account_id'] as String?;
    final t = u['to_account_id'] as String?;
    final linked = Me.instance.account(a)?.linkedAccountId;
    if (!accs.contains(a) && !(t != null && accs.contains(t)) && !(linked != null && accs.contains(linked))) return false;
  }
  final cats = f['categories'];
  if (cats is List && cats.isNotEmpty) {
    final c = Me.instance.category(u['category_id'] as String?);
    if (c == null) return false;
    if (!cats.contains(c.id) && !(c.parentId != null && cats.contains(c.parentId))) return false;
  }
  return true;
}

/// The colours a day memo can have.
const List<String> trMemoColours = ['#6D4AE8', '#2D9CDB', '#138A5E', '#F2994A', '#D63A4B'];

/// A memo's colour from its #RRGGBB, or the brand violet.
Color trHex(String? hex) {
  if (hex == null || hex.length != 7 || !hex.startsWith('#')) return K.blue;
  final v = int.tryParse(hex.substring(1), radix: 16);
  return v == null ? K.blue : Color(0xFF000000 | v);
}

/// Small figures in a calendar cell.
final TextStyle trCellStyle = T.tiny.copyWith(fontSize: 10, height: 1.2).merge(T.tabular);
