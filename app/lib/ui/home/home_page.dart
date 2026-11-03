import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/book.dart';
import '../../core/format.dart';
import '../charts.dart';
import '../money.dart';
import '../stats/category_stats.dart';
import '../stats/stats_views.dart';
import '../theme.dart';
import '../txn_list.dart';
import '../widgets.dart';

/// The Home tab: the whole book at a glance. What it is worth today, what
/// came in and went out this month, the money in each currency, where it
/// went, six months of cash flow, the budget and the latest entries.
class HomePage extends StatefulWidget {
  const HomePage({super.key, this.onOpenTab});

  /// Opens another tab (1 Trans, 2 Stats, 3 Accounts).
  final ValueChanged<int>? onOpenTab;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with ReloadOnChange<HomePage> {
  Period? _period;
  Map<String, dynamic>? overview;
  Map<String, dynamic>? totals;
  CategoryTotals? spending;
  List<Map<String, dynamic>>? flow;
  Map<String, dynamic>? budget;
  List<Txn>? recent;
  String? error;
  int _seq = 0;

  Period get period => _period ??= Period.monthOf(Me.instance.book!, Me.instance.book!.today);

  @override
  Future<void> reload() async {
    final b = Me.instance.book;
    if (b == null) return;
    final p = period;
    final first = p.step(b, -5);
    final seq = ++_seq;
    try {
      final r = await Future.wait<dynamic>([
        Api.instance.rpc('accounts_overview', {'include_deleted': false}),
        Api.instance.rpc('period_totals', {...p.args, 'f': <String, dynamic>{}}),
        Api.instance.rpc('category_totals', {...p.args, 'kind': 'expense', 'f': <String, dynamic>{}}),
        Api.instance.rpc('span_totals', {'date_from': isoDay(first.from), 'date_to': isoDay(p.to), 'unit': 'month', 'f': <String, dynamic>{}}),
        Api.instance.rpc('budget_status', {...p.args, 'period': 'month'}),
        Api.instance.rpc('txn_list', {...p.args, 'f': <String, dynamic>{}, 'max_rows': 5}),
      ]);
      if (!mounted || seq != _seq) return;
      setState(() {
        overview = mapOf(r[0]) ?? <String, dynamic>{};
        totals = mapOf(r[1]) ?? <String, dynamic>{};
        spending = CategoryTotals.from(r[2]);
        flow = rowsOf(r[3]).reversed.toList();
        budget = mapOf(r[4]);
        recent = [for (final t in rowsOf(r[5]).take(5)) Txn(t)];
        error = null;
      });
    } on ApiError catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() => error = e.message);
    }
  }

  void _setPeriod(Period p) {
    setState(() {
      _period = p;
      totals = null;
      spending = null;
      flow = null;
      budget = null;
      recent = null;
      error = null;
    });
    reload();
  }

  @override
  Widget build(BuildContext context) {
    final b = Me.instance.book;
    if (b == null) return const SizedBox.shrink();
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 4, end: Sp.md),
            child: PeriodBar(period: period, onChanged: _setPeriod),
          ),
          Expanded(child: _body(b)),
        ]),
      ),
    );
  }

  Widget _body(Book b) {
    final o = overview;
    if (o == null || totals == null || spending == null || flow == null || recent == null) {
      return error != null ? LoadFailed(message: error!, onRetry: reload) : const Loading();
    }
    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 900;
      const gap = SizedBox(height: Sp.md, width: Sp.md);
      final worth = _worthCard(b, o);
      final month = _monthTiles(b);
      final currencies = _currencies(b, o);
      final donut = _spendingCard(b);
      final cash = _flowCard(b);
      final budgetCard = _budgetCard(b);
      final latest = _recentCard(b);
      return PageBody(
        onRefresh: reload,
        maxWidth: wide ? 1180 : 760,
        bottom: 96,
        children: [
          if (wide)
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 5, child: worth),
              gap,
              Expanded(flex: 6, child: month),
            ])
          else ...[
            worth,
            gap,
            month,
          ],
          if (currencies != null) ...[const SectionTitle('Money by currency'), currencies],
          const SizedBox(height: Sp.lg),
          if (wide)
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 5, child: donut),
              gap,
              Expanded(flex: 6, child: cash),
            ])
          else ...[
            donut,
            gap,
            cash,
          ],
          const SizedBox(height: Sp.md),
          if (wide)
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 5, child: budgetCard ?? const SizedBox.shrink()),
              if (budgetCard != null) gap,
              Expanded(flex: budgetCard == null ? 11 : 6, child: latest),
            ])
          else ...[
            if (budgetCard != null) ...[budgetCard, gap],
            latest,
          ],
        ],
      );
    });
  }

  // ---------------------------------------------------------------- the cards

  /// What the book is worth today: assets less what is owed.
  Widget _worthCard(Book b, Map<String, dynamic> o) {
    final total = toNum(o['total']);
    final missing = rowsOrList(o['missing_rates']);
    return HeroCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Expanded(child: Text('Net worth today', style: T.label.copyWith(color: K.heroText))),
          Pill(b.currency, color: const Color(0x26FFFFFF), fg: Colors.white),
        ]),
        const SizedBox(height: Sp.sm),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: Text(money(total, b.currency), maxLines: 1, style: T.amount.copyWith(fontSize: 34)),
        ),
        const SizedBox(height: Sp.md),
        Row(children: [
          Expanded(child: _heroFigure('Assets', money(toNum(o['assets']), b.currency))),
          const SizedBox(width: Sp.md),
          Expanded(child: _heroFigure('Liabilities', money(toNum(o['liabilities']), b.currency))),
        ]),
        if (missing.isNotEmpty) ...[
          const SizedBox(height: Sp.sm),
          Text('Add a rate for ${missing.join(', ')} to count it here.', style: T.tiny.copyWith(color: K.heroText)),
        ],
      ]),
    );
  }

  Widget _heroFigure(String label, String value) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: T.tiny.copyWith(color: K.heroText)),
        const SizedBox(height: 2),
        Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.bodyStrong.copyWith(color: Colors.white).merge(T.tabular)),
      ]);

  /// This month's income, expenses and what is left of them.
  Widget _monthTiles(Book b) {
    final t = totals!;
    final inc = toNum(t['income']);
    final exp = toNum(t['expense']);
    final left = inc - exp;
    Widget tile(String label, num v, Color tone, IconData icon, {bool sign = false}) => KCard(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(icon, size: 16, color: tone),
              const SizedBox(width: 6),
              Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.small)),
            ]),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                '${sign && v > 0 ? '+' : ''}${money(v, b.currency)}',
                maxLines: 1,
                style: T.h2.copyWith(color: tone).merge(T.tabular),
              ),
            ),
          ]),
        );
    final income = tile('Income', inc, K.income, Icons.south_west_rounded);
    final expense = tile('Expenses', exp, K.expense, Icons.north_east_rounded);
    final rest = tile('Left this month', left, left < 0 ? K.expense : K.ink, Icons.savings_outlined, sign: true);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Row(children: [Expanded(child: income), const SizedBox(width: Sp.md), Expanded(child: expense)]),
      const SizedBox(height: Sp.md),
      rest,
    ]);
  }

  /// The balances held in each currency, and what they are worth in the
  /// main one. Only when the book keeps more than one currency.
  Widget? _currencies(Book b, Map<String, dynamic> o) {
    final own = <String, num>{};
    final main = <String, num>{};
    for (final g in rowsOf(o['groups'])) {
      if (g['kind'] == 'debit_card' || g['deleted'] == true) continue;
      for (final a in rowsOf(g['accounts'])) {
        if (a['in_totals'] != true || a['deleted'] == true || a['balance'] == null) continue;
        final c = '${a['currency'] ?? b.currency}';
        own[c] = (own[c] ?? 0) + toNum(a['balance']);
        if (a['balance_main'] != null) main[c] = (main[c] ?? 0) + toNum(a['balance_main']);
      }
    }
    if (own.length < 2) return null;
    final codes = own.keys.toList()..sort((x, y) => x == b.currency ? -1 : (y == b.currency ? 1 : x.compareTo(y)));
    Widget card(String c) {
      final isMain = c == b.currency;
      final inMain = main[c];
      return KCard(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Pill(c),
            if (isMain) ...[const SizedBox(width: 6), Text('Main', style: T.tiny)],
          ]),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(money(own[c], c), maxLines: 1, style: T.h3.merge(T.tabular)),
          ),
          Text(isMain ? 'Main currency' : (inMain == null ? 'No rate yet' : 'About ${money(inMain, b.currency)}'),
              maxLines: 1, overflow: TextOverflow.ellipsis, style: T.small.merge(T.tabular)),
        ]),
      );
    }

    // A grid, two to a row on phones and four on computers, so no card is cut off.
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth >= 700 ? 4 : 2;
      final w = (c.maxWidth - Sp.md * (cols - 1)) / cols;
      return Wrap(spacing: Sp.md, runSpacing: Sp.md, children: [
        for (final code in codes) SizedBox(width: w, child: card(code)),
      ]);
    });
  }

  /// Where this month's money went: a ring of the biggest categories.
  Widget _spendingCard(Book b) {
    final data = spending!;
    final rows = data.rows.where((r) => toNum(r['amount']) > 0).toList();
    final top = rows.take(5).toList();
    final restSum = rows.skip(5).fold<num>(0, (s, r) => s + toNum(r['amount']));
    final slices = [
      for (var i = 0; i < top.length; i++) Slice(categoryLabel(top[i]), toNum(top[i]['amount']), sliceColor(i)),
      if (restSum > 0) Slice('Other', restSum, K.border2),
    ];
    final total = data.total;
    return KCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _cardTitle('Spending by category', action: 'Stats', onAction: () => widget.onOpenTab?.call(2)),
        const SizedBox(height: Sp.md),
        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Sp.xl),
            child: Text('No expenses in ${period.label(b)} yet.', style: T.small, textAlign: TextAlign.center),
          )
        else
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            DonutChart(
              slices: slices,
              size: 136,
              center: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('Spent', style: T.tiny),
                FittedBox(fit: BoxFit.scaleDown, child: Text(compactMoney(total, b.currency), maxLines: 1, style: T.h3.merge(T.tabular))),
              ]),
            ),
            const SizedBox(width: Sp.lg),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (var i = 0; i < slices.length; i++)
                  _legendRow(
                    slices[i],
                    total,
                    onTap: i < top.length && top[i]['category_id'] != null ? () => _openCategory(top[i], slices[i].color) : null,
                  ),
              ]),
            ),
          ]),
      ]),
    );
  }

  Widget _legendRow(Slice s, num total, {VoidCallback? onTap}) {
    final pct = total <= 0 ? 0 : (s.value * 100 / total);
    final line = Row(children: [
      Container(width: 10, height: 10, decoration: BoxDecoration(color: s.color, shape: BoxShape.circle)),
      const SizedBox(width: 8),
      Expanded(child: Text(s.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.small.copyWith(color: K.ink2))),
      const SizedBox(width: 6),
      Text(pct < 10 ? '${(pct * 10).round() / 10}%' : '${pct.round()}%', style: T.small.copyWith(color: K.ink, fontWeight: FontWeight.w600).merge(T.tabular)),
    ]);
    final row = Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: line);
    return onTap == null ? row : InkWell(borderRadius: BorderRadius.circular(8), onTap: onTap, child: row);
  }

  void _openCategory(Map<String, dynamic> r, Color color) {
    final id = r['category_id'] as String?;
    if (id == null) return;
    final p = period;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => CategoryStatsPage(
        kind: 'expense',
        categoryId: id,
        title: categoryLabel(r),
        period: p,
        color: color,
        hasSubs: r['has_subs'] == true,
      ),
    ));
  }

  /// Six months of income beside expenses.
  Widget _flowCard(Book b) {
    final months = flow!;
    final points = [
      for (final m in months)
        ChartPoint(_monthShort(b, m), toNum(m['income']), value2: toNum(m['expense'])),
    ];
    final empty = points.every((p) => p.value == 0 && (p.value2 ?? 0) == 0);
    return KCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _cardTitle('Cash flow', action: 'Trans', onAction: () => widget.onOpenTab?.call(1)),
        const SizedBox(height: 4),
        Row(children: [
          _dot(K.income, 'Income'),
          const SizedBox(width: Sp.md),
          _dot(K.expense, 'Expenses'),
          const Spacer(),
          Text('Last ${points.length} months', style: T.tiny),
        ]),
        const SizedBox(height: Sp.md),
        if (empty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Sp.xl),
            child: Text('Nothing recorded in these months yet.', style: T.small, textAlign: TextAlign.center),
          )
        else
          BarChart(points: points, height: 172),
      ]),
    );
  }

  String _monthShort(Book b, Map<String, dynamic> m) {
    final from = parseDay(m['from']);
    if (from == null) return '';
    final (_, mm) = b.monthOf(from);
    return kMonthsShort[(mm - 1) % 12];
  }

  Widget _dot(Color c, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 9, height: 9, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 6),
        Text(label, style: T.tiny),
      ]);

  /// The month's total budget, when the book has one.
  Widget? _budgetCard(Book b) {
    final t = mapOf(budget?['total']);
    if (t == null || t['budget'] == null) return null;
    final total = toNum(t['budget']);
    final spent = toNum(t['spent']);
    final left = total - spent;
    final share = total <= 0 ? 0.0 : math.min(1.0, spent / total);
    final over = left < 0;
    return KCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _cardTitle('Budget', action: 'Stats', onAction: () => widget.onOpenTab?.call(2)),
        const SizedBox(height: Sp.md),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(child: Text(money(spent, b.currency), style: T.h2.merge(T.tabular))),
          Text('of ${money(total, b.currency)}', style: T.small.merge(T.tabular)),
        ]),
        const SizedBox(height: Sp.sm),
        ProgressLine(share.toDouble(), color: over ? K.expense : K.blue, track: K.surface2),
        const SizedBox(height: Sp.sm),
        Text(over ? 'Over by ${money(-left, b.currency)}' : '${money(left, b.currency)} left this month',
            style: T.small.copyWith(color: over ? K.expense : K.muted)),
      ]),
    );
  }

  /// The latest entries of the month.
  Widget _recentCard(Book b) {
    final list = recent!;
    return KCard(
      padding: const EdgeInsets.fromLTRB(0, Sp.lg, 0, Sp.sm),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
          child: _cardTitle('Latest entries', action: 'See all', onAction: () => widget.onOpenTab?.call(1)),
        ),
        const SizedBox(height: Sp.sm),
        if (list.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.lg),
            child: Text('No entries in ${period.label(b)} yet.', style: T.small),
          )
        else
          for (final t in list) TxnRow(t, showDate: true),
      ]),
    );
  }

  Widget _cardTitle(String text, {String? action, VoidCallback? onAction}) => Row(children: [
        Expanded(child: Text(text, style: T.h3)),
        if (action != null && onAction != null)
          InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: onAction,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(action, style: T.label.copyWith(color: K.blue)),
                Icon(Icons.chevron_right_rounded, size: 18, color: K.blue),
              ]),
            ),
          ),
      ]);
}

/// A plain list of strings from the server (currency codes).
List<String> rowsOrList(Object? j) => j is List ? [for (final x in j) '$x'] : const [];
