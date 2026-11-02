import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/book.dart';
import '../../core/format.dart';
import '../charts.dart';
import '../money.dart';
import '../theme.dart';
import '../txn_list.dart';
import '../widgets.dart';
import 'stats_views.dart';

/// One category for a period: its subcategories' pie (when it has any), the
/// category month by month, and its transactions.
class CategoryStatsPage extends StatefulWidget {
  const CategoryStatsPage({
    super.key,
    required this.kind,
    required this.categoryId,
    required this.title,
    required this.period,
    this.color = K.blue,
    this.hasSubs = false,
  });

  /// income or expense.
  final String kind;
  final String categoryId;
  final String title;
  final Period period;
  final Color color;
  final bool hasSubs;

  @override
  State<CategoryStatsPage> createState() => _CategoryStatsPageState();
}

class _CategoryStatsPageState extends State<CategoryStatsPage> with ReloadOnChange<CategoryStatsPage> {
  late Period period = widget.period;
  CategoryTotals? subs;
  List<Map<String, dynamic>> trend = const [];
  List<Txn>? txns;
  String? error;
  int _seq = 0;

  @override
  Future<void> reload() async {
    if (Me.instance.book == null) return;
    final p = period;
    final seq = ++_seq;
    try {
      final r = await Future.wait<dynamic>([
        Api.instance.rpc('category_totals', {...p.args, 'kind': widget.kind, 'parent': widget.categoryId, 'f': <String, dynamic>{}}),
        Api.instance.rpc('category_trend', {
          'kind': widget.kind,
          'category': widget.categoryId,
          'months': 12,
          'until': isoDay(p.to),
          'f': <String, dynamic>{},
        }),
        Api.instance.rpc('txn_list', {
          ...p.args,
          'f': {
            'categories': [widget.categoryId],
          },
        }),
      ]);
      if (!mounted || seq != _seq) return;
      setState(() {
        subs = CategoryTotals.from(r[0]);
        trend = rowsOf(r[1]);
        txns = rowsOf(r[2]).map(Txn.new).toList();
        error = null;
      });
    } on ApiError catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() => error = e.message);
    }
  }

  void _setPeriod(Period p) {
    setState(() {
      period = p;
      subs = null;
      txns = null;
      error = null;
    });
    reload();
  }

  void _openSub(Map<String, dynamic> r, Color color) {
    final id = r['category_id'] as String?;
    if (id == null) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => CategoryStatsPage(kind: widget.kind, categoryId: id, title: categoryLabel(r), period: period, color: color),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final b = Me.instance.book;
    if (b == null) return const SizedBox.shrink();
    return Scaffold(
      appBar: AppBar(title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: _body(b),
    );
  }

  Widget _body(Book b) {
    final list = txns;
    if (list == null) {
      return Column(children: [
        Padding(padding: const EdgeInsets.symmetric(horizontal: Sp.page), child: PeriodBar(period: period, onChanged: _setPeriod)),
        Expanded(child: error != null ? LoadFailed(message: error!, onRetry: reload) : const Loading()),
      ]);
    }
    final subRows = (subs?.rows ?? const <Map<String, dynamic>>[]).where((r) => toNum(r['amount']) > 0).toList();
    final showSubs = widget.hasSubs && subRows.isNotEmpty;
    final points = [
      for (final m in trend) ChartPoint(monthShort(m['month']), toNum(m['amount'])),
    ];
    final label = period.label(b);
    return PageBody(onRefresh: reload, children: [
      PeriodBar(period: period, onChanged: _setPeriod),
      KCard(
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.kind == 'income' ? 'Income, $label' : 'Spent, $label', maxLines: 1, overflow: TextOverflow.ellipsis, style: T.small),
              const SizedBox(height: 2),
              MoneyText(subs?.total ?? 0, kind: widget.kind, style: T.h2),
            ]),
          ),
          const SizedBox(width: Sp.sm),
          Pill.grey(list.length == 1 ? '1 entry' : '${list.length} entries'),
        ]),
      ),
      if (showSubs) ...[
        const SectionTitle('Subcategories'),
        CategoryBreakdown(
          rows: subRows,
          canTap: (r) => r['category_id'] != null && r['category_id'] != widget.categoryId,
          onTap: _openSub,
        ),
      ],
      if (points.isNotEmpty) ...[
        const SectionTitle('Month by month'),
        KCard(
          padding: const EdgeInsets.fromLTRB(Sp.sm, Sp.md, Sp.sm, Sp.sm),
          child: LineChart(points: points, color: widget.color, format: (v) => compactMoney(v, b.currency)),
        ),
      ],
      const SectionTitle('Transactions'),
      if (list.isEmpty)
        EmptyState(icon: Icons.receipt_long_outlined, text: 'Nothing in $label.')
      else
        KGroup(children: [for (final t in list) TxnRow(t, showDate: true)]),
    ]);
  }
}

/// The transactions of a period that a stats row stands for, when it is not a
/// category: transfers that count as income or expense, card payments, fees,
/// money without a category, or one note.
class StatsTxnsPage extends StatefulWidget {
  const StatsTxnsPage({super.key, required this.title, required this.period, this.filter = const <String, dynamic>{}, this.keep});
  final String title;
  final Period period;

  /// The filter sent to txn_list().
  final Map<String, dynamic> filter;

  /// Which of the rows that come back to show.
  final bool Function(Txn t)? keep;

  @override
  State<StatsTxnsPage> createState() => _StatsTxnsPageState();
}

class _StatsTxnsPageState extends State<StatsTxnsPage> with ReloadOnChange<StatsTxnsPage> {
  late Period period = widget.period;
  List<Txn>? txns;
  String? error;
  int _seq = 0;

  @override
  Future<void> reload() async {
    if (Me.instance.book == null) return;
    final p = period;
    final seq = ++_seq;
    try {
      final r = await Api.instance.rpc('txn_list', {...p.args, 'f': widget.filter});
      if (!mounted || seq != _seq) return;
      final keep = widget.keep;
      final all = rowsOf(r).map(Txn.new);
      setState(() {
        txns = (keep == null ? all : all.where(keep)).toList();
        error = null;
      });
    } on ApiError catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() => error = e.message);
    }
  }

  void _setPeriod(Period p) {
    setState(() {
      period = p;
      txns = null;
      error = null;
    });
    reload();
  }

  @override
  Widget build(BuildContext context) {
    final b = Me.instance.book;
    if (b == null) return const SizedBox.shrink();
    final list = txns;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: list == null
          ? Column(children: [
              Padding(padding: const EdgeInsets.symmetric(horizontal: Sp.page), child: PeriodBar(period: period, onChanged: _setPeriod)),
              Expanded(child: error != null ? LoadFailed(message: error!, onRetry: reload) : const Loading()),
            ])
          : PageBody(onRefresh: reload, children: [
              PeriodBar(period: period, onChanged: _setPeriod),
              if (list.isEmpty)
                EmptyState(icon: Icons.receipt_long_outlined, text: 'Nothing in ${period.label(b)}.')
              else ...[
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(4, 0, 4, Sp.sm),
                  child: Text(list.length == 1 ? '1 entry' : '${list.length} entries', style: T.small),
                ),
                KGroup(children: [for (final t in list) TxnRow(t, showDate: true)]),
              ],
            ]),
    );
  }
}

/// The page for a stats row without a category (key transfer, card, fee or
/// none), with the period's matching transactions.
Widget specialTxnsPage({required String kind, required String key, required String title, required Period period}) {
  switch (key) {
    case 'transfer':
      // Into (or out of) a Transfer-Expense account.
      return StatsTxnsPage(
        title: title,
        period: period,
        filter: const {
          'kinds': ['transfer'],
        },
        keep: (t) => t.countsAs == kind,
      );
    case 'card':
      // A card paid off, when card spending counts on payment day.
      return StatsTxnsPage(
        title: title,
        period: period,
        filter: const {
          'kinds': ['transfer'],
        },
        keep: (t) => (Me.instance.account(t.toAccountId)?.isCard ?? false) && !(Me.instance.account(t.accountId)?.isCard ?? false),
      );
    case 'fee':
      return StatsTxnsPage(
        title: title,
        period: period,
        filter: const {
          'kinds': ['transfer'],
        },
        keep: (t) => t.fee > 0,
      );
    default:
      // Income or expenses without a category.
      return StatsTxnsPage(
        title: title,
        period: period,
        filter: {
          'kinds': [kind],
        },
        keep: (t) => t.splits.isEmpty ? t.categoryId == null : t.splits.any((s) => s['category_id'] == null),
      );
  }
}

/// The period's income or expenses with one note.
Widget noteTxnsPage({required String kind, required String note, required Period period}) {
  final n = note.trim();
  return StatsTxnsPage(
    title: n.isEmpty ? 'No note' : n,
    period: period,
    filter: n.isEmpty ? const <String, dynamic>{} : {'q': n},
    keep: (t) => (t.note ?? '').trim() == n && (t.kind == kind || t.countsAs == kind),
  );
}
