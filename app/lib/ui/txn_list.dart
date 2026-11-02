import 'package:flutter/material.dart';

import '../core/book.dart';
import '../core/format.dart';
import 'entry/entry_page.dart';
import 'money.dart';
import 'theme.dart';

/// One transaction as a row: the category (subcategory under it), the
/// account or "From → To", the note, and the amount in its own currency.
class TxnRow extends StatelessWidget {
  const TxnRow(this.t, {super.key, this.showDate = false, this.onTap, this.dim = false});
  final Txn t;

  /// Show the date under the account (search results, an account's list).
  final bool showDate;
  final VoidCallback? onTap;

  /// Upcoming repeats and instalments still to come.
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final isTransfer = t.kind == 'transfer';
    final where = isTransfer ? '${t.account} → ${t.toAccount}' : t.account;
    final extra = <String>[
      if (t.planNo != null && t.planMonths != null) '${t.planNo}/${t.planMonths}',
      if (t.repeatId != null) 'Repeats',
      ...t.tags.map((g) => '#$g'),
    ];
    final note = (t.note ?? '').trim();
    final row = InkWell(
      onTap: onTap ?? () => openEntry(context, txn: t),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Sp.page, vertical: 9),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 96,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.small.copyWith(color: K.ink2, fontWeight: FontWeight.w600)),
              if (t.subtitle != null) Text(t.subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.tiny.copyWith(fontWeight: FontWeight.w500)),
            ]),
          ),
          const SizedBox(width: Sp.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (note.isNotEmpty) Text(note, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.bodyStrong.copyWith(fontSize: 14)),
              Text(where, maxLines: 1, overflow: TextOverflow.ellipsis, style: note.isEmpty ? T.body.copyWith(fontSize: 14) : T.small),
              if (showDate || extra.isNotEmpty)
                Text([if (showDate) shortDate(t.at), ...extra].join('   '), maxLines: 1, overflow: TextOverflow.ellipsis, style: T.tiny.copyWith(fontWeight: FontWeight.w500)),
            ]),
          ),
          const SizedBox(width: Sp.sm),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            MoneyText(t.amount, currency: t.currency, kind: t.countsAs, style: T.bodyStrong.copyWith(fontSize: 14)),
            if (isTransfer && t.toCurrency != null && t.toCurrency != t.currency && t.toAmount != null)
              MoneyText(t.toAmount!, currency: t.toCurrency, kind: 'transfer', style: T.tiny),
            if (t.fee > 0) Text('Fee ${amountText(t.fee, t.currency)}', style: T.tiny),
            if (t.photos > 0) const Icon(Icons.photo_outlined, size: 13, color: K.muted),
          ]),
        ]),
      ),
    );
    return dim ? Opacity(opacity: 0.5, child: row) : row;
  }
}

/// A day's header in the list: the big date, the weekday, month.year, and
/// the day's income and expenses.
class DayHeader extends StatelessWidget {
  const DayHeader({super.key, required this.day, required this.income, required this.expense});
  final DateTime day;
  final num income;
  final num expense;

  @override
  Widget build(BuildContext context) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final wd = day.weekday;
    return Container(
      padding: const EdgeInsets.fromLTRB(Sp.page, 12, Sp.page, 6),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: K.border))),
      child: Row(children: [
        Text('${day.day}', style: T.h2.copyWith(fontSize: 22).merge(T.tabular)),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: wd == 7 ? K.expenseBg : (wd == 6 ? K.brand100 : K.surface2),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(days[wd - 1], style: T.tiny.copyWith(color: wd == 7 ? K.expense : (wd == 6 ? K.brand600 : K.ink2))),
        ),
        const SizedBox(width: 6),
        Text('${day.month.toString().padLeft(2, '0')}.${day.year}', style: T.tiny),
        const Spacer(),
        if (income != 0) MoneyText(income, kind: 'income', style: T.label),
        if (income != 0 && expense != 0) const SizedBox(width: Sp.md),
        if (expense != 0) MoneyText(expense, kind: 'expense', style: T.label),
      ]),
    );
  }
}

/// Transactions grouped by day, newest first, each day with its header.
/// Totals per day come from what each row counts as, in the main currency.
class TxnDayList extends StatelessWidget {
  const TxnDayList({super.key, required this.txns, this.upcoming = const [], this.header, this.footer, this.empty, this.onRefresh});
  final List<Txn> txns;

  /// Repeats still to come, shown dimmed on their days.
  final List<Txn> upcoming;
  final Widget? header;
  final Widget? footer;
  final Widget? empty;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final byDay = <DateTime, List<(Txn, bool)>>{};
    for (final t in txns) {
      byDay.putIfAbsent(t.day, () => []).add((t, false));
    }
    for (final t in upcoming) {
      byDay.putIfAbsent(t.day, () => []).add((t, true));
    }
    final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));
    final children = <Widget>[
      if (header != null) header!,
      if (days.isEmpty && empty != null) empty!,
      for (final d in days) ...[
        Builder(builder: (context) {
          num inc = 0, exp = 0;
          for (final (t, up) in byDay[d]!) {
            if (up) continue;
            if (t.countsAs == 'income') inc += t.amountMain;
            if (t.countsAs == 'expense') exp += t.amountMain;
            if (t.kind == 'transfer' && t.fee > 0) exp += t.fee * t.rate;
          }
          return DayHeader(day: d, income: inc, expense: exp);
        }),
        for (final (t, up) in byDay[d]!) TxnRow(t, dim: up, onTap: up ? () {} : null),
        const SizedBox(height: 6),
      ],
      if (footer != null) footer!,
      SizedBox(height: 96 + MediaQuery.paddingOf(context).bottom),
    ];
    final list = ListView(padding: EdgeInsets.zero, children: children);
    return onRefresh == null ? list : RefreshIndicator(onRefresh: onRefresh!, color: K.blue, child: list);
  }
}
