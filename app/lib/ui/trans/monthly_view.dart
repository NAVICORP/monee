import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/book.dart';
import '../../core/format.dart';
import '../money.dart';
import '../theme.dart';
import '../widgets.dart';
import 'trans_common.dart';

/// The Monthly sub-tab: each month of the year with its income, expenses and
/// net. The current month (or the one tapped) opens into its weeks; tapping
/// a week, or an open month, shows it in Daily.
class TransMonthlyView extends StatefulWidget {
  const TransMonthlyView({super.key, required this.year, required this.filter, required this.onOpen});
  final Period year;
  final Map<String, dynamic> filter;
  final ValueChanged<Period> onOpen;

  @override
  State<TransMonthlyView> createState() => _TransMonthlyViewState();
}

class _Span {
  _Span(this.from, this.to, this.income, this.expense);
  final DateTime from;
  final DateTime to;
  final num income;
  final num expense;
  num get net => income - expense;
  bool contains(DateTime d) => !d.isBefore(from) && !d.isAfter(to);
}

List<_Span> _spans(dynamic j) {
  final out = <_Span>[];
  for (final x in trRows(j)) {
    final f = parseDay(x['from']);
    final t = parseDay(x['to']);
    if (f == null || t == null) continue;
    out.add(_Span(f, t, toNum(x['income']), toNum(x['expense'])));
  }
  return out;
}

class _TransMonthlyViewState extends State<TransMonthlyView> with ReloadOnChange {
  List<_Span> _months = const <_Span>[];
  Map<DateTime, (num, num)> _planned = {};

  /// The open month (its first day), and its weeks once loaded.
  DateTime? _open;
  List<_Span>? _weeks;
  bool _loaded = false;
  String? _error;
  int _ticket = 0;
  int _weekTicket = 0;

  @override
  void didUpdateWidget(covariant TransMonthlyView old) {
    super.didUpdateWidget(old);
    if (!trSamePeriod(old.year, widget.year) || !identical(old.filter, widget.filter)) {
      if (!trSamePeriod(old.year, widget.year)) {
        _open = null;
        _weeks = null;
      }
      reload();
    }
  }

  @override
  Future<void> reload() async {
    final b = Me.instance.book;
    if (b == null) return;
    final t = ++_ticket;
    final y = widget.year;
    final f = widget.filter;
    final upFrom = trLater(y.from, addDays(b.today, 1));
    try {
      final r = await Future.wait<dynamic>([
        Api.instance.rpc('span_totals', {...y.args, 'unit': 'month', 'f': f}),
        if (!upFrom.isAfter(y.to)) Api.instance.rpc('upcoming', {'date_from': isoDay(upFrom), 'date_to': isoDay(y.to)}),
      ]);
      final months = _spans(r[0]);
      final planned = <DateTime, (num, num)>{};
      if (r.length > 1) {
        for (final u in trRows(r[1])) {
          if (!trUpcomingPasses(u, f)) continue;
          final d = parseDay(u['day']);
          if (d == null) continue;
          final key = months.where((m) => m.contains(d)).firstOrNull?.from;
          if (key == null) continue;
          final counts = trUpcomingTxn(u).countsAs;
          final v = toNum(u['amount_main']);
          final (num i, num e) = planned[key] ?? (0, 0);
          if (counts == 'income') planned[key] = (i + v, e);
          if (counts == 'expense') planned[key] = (i, e + v);
        }
      }
      if (!mounted || t != _ticket) return;
      // The month to open: the one already open, else the current one.
      var open = _open;
      if (open == null || !months.any((m) => m.from == open)) {
        open = months.where((m) => m.contains(b.today)).firstOrNull?.from;
      }
      setState(() {
        _months = months;
        _planned = planned;
        _loaded = true;
        _error = null;
        if (open != _open) _weeks = null;
        _open = open;
      });
      if (open != null) _loadWeeks();
    } catch (e) {
      if (!mounted || t != _ticket) return;
      setState(() {
        _loaded = true;
        _error = trError(e);
      });
    }
  }

  Future<void> _loadWeeks() async {
    final open = _open;
    final m = _months.where((x) => x.from == open).firstOrNull;
    if (m == null) return;
    final t = ++_weekTicket;
    try {
      final r = await Api.instance.rpc('span_totals',
          {'date_from': isoDay(m.from), 'date_to': isoDay(m.to), 'unit': 'week', 'f': widget.filter});
      if (!mounted || t != _weekTicket || _open != m.from) return;
      setState(() => _weeks = _spans(r));
    } catch (e) {
      if (!mounted || t != _weekTicket) return;
      setState(() => _weeks = const <_Span>[]);
      toast(context, trError(e), bad: true);
    }
  }

  void _tapMonth(_Span m) {
    if (_open == m.from) {
      widget.onOpen(Period(PeriodKind.month, m.from, m.to));
      return;
    }
    setState(() {
      _open = m.from;
      _weeks = null;
    });
    _loadWeeks();
  }

  @override
  Widget build(BuildContext context) {
    final b = Me.instance.book;
    if (b == null || !_loaded) return const Loading();
    final today = b.today;
    return RefreshIndicator(
      onRefresh: reload,
      color: K.blue,
      child: ListView(physics: const AlwaysScrollableScrollPhysics(), padding: EdgeInsets.only(bottom: 96 + MediaQuery.paddingOf(context).bottom), children: [
        if (_error != null) Padding(padding: const EdgeInsets.fromLTRB(Sp.page, Sp.md, Sp.page, 0), child: Notice(_error!)),
        for (final m in _months) ...[
          _monthRow(b, m),
          if (m.from == _open) ...[
            if (_weeks == null)
              const Padding(padding: EdgeInsets.symmetric(vertical: Sp.md), child: Loading())
            else
              for (final w in _weeks!) _weekRow(w, w.contains(today)),
          ],
        ],
        const SizedBox(height: 96),
      ]),
    );
  }

  Widget _amounts(num income, num expense, {num? net, bool dim = false}) {
    final style = T.label.copyWith(fontSize: 13);
    final row = Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        Flexible(child: MoneyText(income, kind: 'income', style: style, symbol: false, align: TextAlign.end)),
        const SizedBox(width: Sp.md),
        Flexible(child: MoneyText(expense, kind: 'expense', style: style, symbol: false, align: TextAlign.end)),
      ]),
      if (net != null) ...[
        const SizedBox(height: 2),
        MoneyText(net, style: T.tiny.copyWith(color: K.ink2), symbol: false, align: TextAlign.end),
      ],
    ]);
    return dim ? Opacity(opacity: 0.5, child: row) : row;
  }

  Widget _monthRow(Book b, _Span m) {
    final (_, mm) = b.monthOf(m.from);
    final open = m.from == _open;
    final planned = _planned[m.from];
    return Material(
      color: K.surface,
      child: InkWell(
        onTap: () => _tapMonth(m),
        child: Container(
          padding: const EdgeInsetsDirectional.fromSTEB(Sp.page, 11, Sp.page, 11),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: K.border))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 96,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(kMonthsShort[mm - 1], style: T.h3),
                Text('${dotDay(m.from)} ~ ${dotDay(m.to)}',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: T.tiny.copyWith(fontWeight: FontWeight.w500)),
              ]),
            ),
            const SizedBox(width: Sp.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                _amounts(m.income, m.expense, net: m.net),
                if (planned != null) ...[
                  const SizedBox(height: 4),
                  Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                    const Text('Upcoming', style: T.tiny),
                    const SizedBox(width: Sp.sm),
                    Flexible(child: _amounts(planned.$1, planned.$2, dim: true)),
                  ]),
                ],
              ]),
            ),
            if (open) ...[
              const SizedBox(width: 4),
              const Padding(padding: EdgeInsets.only(top: 2), child: Icon(Icons.chevron_right_rounded, size: 20, color: K.muted)),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _weekRow(_Span w, bool current) {
    return Material(
      color: current ? K.brand100 : K.paper,
      child: InkWell(
        onTap: () => widget.onOpen(Period(PeriodKind.week, w.from, w.to)),
        child: Container(
          padding: const EdgeInsetsDirectional.fromSTEB(Sp.page + 8, 9, Sp.page, 9),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: K.border))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 96,
              child: Text('${dotDay(w.from)} ~ ${dotDay(w.to)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: T.small.copyWith(fontSize: 12, color: current ? K.brand600 : K.ink2, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: Sp.sm),
            Expanded(child: _amounts(w.income, w.expense, net: w.net)),
          ]),
        ),
      ),
    );
  }
}
