import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/book.dart';
import '../../core/format.dart';
import '../money.dart';
import '../theme.dart';
import '../txn_list.dart';
import '../widgets.dart';
import 'trans_common.dart';

/// The Daily sub-tab: the period's transactions by day, newest first, with
/// repeats still to come shown dimmed on their days.
class TransDailyView extends StatefulWidget {
  const TransDailyView({super.key, required this.period, required this.filter});
  final Period period;
  final Map<String, dynamic> filter;

  @override
  State<TransDailyView> createState() => _TransDailyViewState();
}

class _TransDailyViewState extends State<TransDailyView> with ReloadOnChange {
  List<Txn> _txns = const <Txn>[];
  List<Txn> _up = const <Txn>[];
  bool _loaded = false;
  String? _error;
  int _ticket = 0;

  @override
  void didUpdateWidget(covariant TransDailyView old) {
    super.didUpdateWidget(old);
    if (!trSamePeriod(old.period, widget.period) || !identical(old.filter, widget.filter)) reload();
  }

  @override
  Future<void> reload() async {
    final t = ++_ticket;
    final p = widget.period;
    final f = widget.filter;
    final upFrom = trLater(p.from, addDays(trToday(), 1));
    try {
      final r = await Future.wait<dynamic>([
        Api.instance.rpc('txn_list', {...p.args, 'f': f, 'max_rows': 3000}),
        if (!upFrom.isAfter(p.to)) Api.instance.rpc('upcoming', {'date_from': isoDay(upFrom), 'date_to': isoDay(p.to)}),
      ]);
      if (!mounted || t != _ticket) return;
      setState(() {
        _txns = trRows(r[0]).map(Txn.new).toList();
        _up = r.length > 1 ? trRows(r[1]).where((u) => trUpcomingPasses(u, f)).map(trUpcomingTxn).toList() : const <Txn>[];
        _loaded = true;
        _error = null;
      });
    } catch (e) {
      if (!mounted || t != _ticket) return;
      setState(() {
        _loaded = true;
        _error = trError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Loading();
    return TxnDayList(
      txns: _txns,
      upcoming: _up,
      header: _error == null ? null : Padding(padding: const EdgeInsets.fromLTRB(Sp.page, Sp.md, Sp.page, 0), child: Notice(_error!)),
      empty: _error == null ? const EmptyState(icon: Icons.receipt_long_outlined, text: 'Nothing recorded in this period.') : null,
      onRefresh: reload,
    );
  }
}
