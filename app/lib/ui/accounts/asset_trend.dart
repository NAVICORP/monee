import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/book.dart';
import '../../core/format.dart';
import '../charts.dart';
import '../money.dart';
import '../theme.dart';
import '../widgets.dart';
import 'account_parts.dart';

/// Assets and liabilities at each month's end over the last year, at today's
/// rates.
class AssetTrendPage extends StatefulWidget {
  const AssetTrendPage({super.key});

  @override
  State<AssetTrendPage> createState() => _AssetTrendPageState();
}

class _AssetTrendPageState extends State<AssetTrendPage> with ReloadOnChange<AssetTrendPage> {
  List<Map<String, dynamic>>? rows;
  String? error;
  int _seq = 0;

  @override
  Future<void> reload() async {
    if (Me.instance.book == null) return;
    final seq = ++_seq;
    try {
      final r = await Api.instance.rpc('asset_trend', {'months': 12});
      if (!mounted || seq != _seq) return;
      setState(() {
        rows = jsonRows(r);
        error = null;
      });
    } on ApiError catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() => error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = Me.instance.book;
    return Scaffold(
      appBar: AppBar(title: const Text('Asset trend')),
      body: b == null ? const SizedBox.shrink() : _body(b),
    );
  }

  Widget _body(Book b) {
    final list = rows;
    if (list == null) return error != null ? LoadFailed(message: error!, onRetry: reload) : const Loading();
    if (list.isEmpty) {
      return PageBody(onRefresh: reload, children: const [
        EmptyState(icon: Icons.show_chart_rounded, text: 'Nothing to show yet.'),
      ]);
    }
    final cur = b.currency;
    final points = [
      for (final m in list) ChartPoint(shortMonth(m['month']), toNum(m['assets']), value2: toNum(m['liabilities'])),
    ];
    return PageBody(onRefresh: reload, children: [
      KCard(
        padding: const EdgeInsets.fromLTRB(Sp.sm, Sp.md, Sp.sm, Sp.sm),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 6),
            child: Wrap(spacing: Sp.md, runSpacing: 4, children: [
              _Key(color: K.income, label: 'Assets'),
              _Key(color: K.expense, label: 'Liabilities'),
            ]),
          ),
          const SizedBox(height: Sp.sm),
          LineChart(points: points, color: K.income, color2: K.expense, format: (v) => chartMoney(v, cur)),
        ]),
      ),
      const SectionTitle('Month end'),
      KGroup(children: [
        for (final m in list.reversed)
          KRow(
            title: monthLabel(DateTime(toNum(m['year']).toInt(), toNum(m['month']).toInt())),
            sub: 'Assets ${money(toNum(m['assets']), cur)}, liabilities ${money(toNum(m['liabilities']), cur)}',
            trailing: BalanceText(toNum(m['total']), currency: cur),
          ),
      ]),
    ]);
  }
}

class _Key extends StatelessWidget {
  const _Key({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 6),
      Text(label, style: T.tiny),
    ]);
  }
}
