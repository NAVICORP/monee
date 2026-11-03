import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/book.dart';
import '../../core/format.dart';
import '../money.dart';
import '../more/budgets.dart';
import '../theme.dart';
import '../widgets.dart';
import 'export_excel.dart';
import 'trans_common.dart';

/// The Total sub-tab: the budget against spending, the period's account
/// summary, and the Excel export.
class TransTotalView extends StatefulWidget {
  const TransTotalView({super.key, required this.period, required this.filter});
  final Period period;
  final Map<String, dynamic> filter;

  @override
  State<TransTotalView> createState() => _TransTotalViewState();
}

class _TransTotalViewState extends State<TransTotalView> with ReloadOnChange {
  Map<String, dynamic> _budget = const <String, dynamic>{};
  Map<String, dynamic> _accounts = const <String, dynamic>{};
  bool _loaded = false;
  bool _exporting = false;
  String? _error;
  int _ticket = 0;

  @override
  void didUpdateWidget(covariant TransTotalView old) {
    super.didUpdateWidget(old);
    if (!trSamePeriod(old.period, widget.period)) reload();
  }

  String get _budgetPeriod => switch (widget.period.kind) {
        PeriodKind.week => 'week',
        PeriodKind.year => 'year',
        _ => 'month',
      };

  @override
  Future<void> reload() async {
    final t = ++_ticket;
    final p = widget.period;
    try {
      final r = await Future.wait<dynamic>([
        Api.instance.rpc('budget_status', {...p.args, 'period': _budgetPeriod}),
        Api.instance.rpc('period_accounts', p.args),
      ]);
      if (!mounted || t != _ticket) return;
      setState(() {
        _budget = trMap(r[0]);
        _accounts = trMap(r[1]);
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

  Future<void> _export(BuildContext buttonContext) async {
    setState(() => _exporting = true);
    try {
      final done = await trExportExcel(buttonContext, period: widget.period, filter: widget.filter);
      if (!mounted) return;
      if (!done) toast(context, 'Nothing to export in this period.');
    } on ApiError catch (e) {
      if (mounted) toast(context, e.message, bad: true);
    } catch (_) {
      if (mounted) toast(context, 'The Excel file could not be made. Try again.', bad: true);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = Me.instance.book;
    if (b == null || !_loaded) return const Loading();
    return PageBody(
      onRefresh: reload,
      bottom: 104,
      children: [
        if (_error != null) ...[Notice(_error!), const SizedBox(height: Sp.md)],
        _budgetCard(b),
        const SizedBox(height: Sp.lg),
        _accountsCard(b),
        const SizedBox(height: Sp.lg),
        Builder(
          builder: (bc) => KButton(
            label: 'Export to Excel',
            icon: Icons.table_view_rounded,
            kind: KButtonKind.secondary,
            expand: true,
            busy: _exporting,
            onPressed: () => _export(bc),
          ),
        ),
      ],
    );
  }

  Widget _budgetCard(Book b) {
    final rows = trRows(_budget['rows']);
    final total = _budget['total'] is Map ? trMap(_budget['total']) : null;
    final tp = toNum(_budget['today_percent']);
    final today = tp > 0 && tp < 100 ? tp : null;
    return KCard(
      padding: const EdgeInsetsDirectional.fromSTEB(Sp.lg, Sp.md, Sp.lg, Sp.sm),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.savings_outlined, size: 20, color: K.blue),
          const SizedBox(width: Sp.sm),
          Expanded(child: Text('Budget', style: T.h3)),
          if (b.canEdit)
            KButton(
              label: 'Budget setting',
              small: true,
              kind: KButtonKind.secondary,
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const BudgetsPage())),
            ),
        ]),
        if (total == null && rows.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(vertical: Sp.md),
            child: Text('No budget for this period yet.', style: T.small),
          )
        else ...[
          if (today != null)
            Padding(
              padding: const EdgeInsets.only(top: Sp.sm),
              child: Text('The line in each bar marks today, ${today.round()}% into the period.', style: T.tiny.copyWith(fontWeight: FontWeight.w500)),
            ),
          if (total != null)
            _budgetRow(b, name: 'Total budget', emoji: null, budget: toNum(total['budget']), spent: toNum(total['spent']), percent: total['percent'], today: today, strong: true),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0 || total != null) const Divider(),
            _budgetRow(b,
                name: '${rows[i]['name'] ?? ''}',
                emoji: rows[i]['emoji'] as String?,
                budget: toNum(rows[i]['budget']),
                spent: toNum(rows[i]['spent']),
                percent: rows[i]['percent'],
                today: today),
          ],
        ],
      ]),
    );
  }

  Widget _budgetRow(Book b,
      {required String name, required String? emoji, required num budget, required num spent, required Object? percent, num? today, bool strong = false}) {
    final left = budget - spent;
    final over = left < 0;
    final pct = percent == null ? (spent > 0 ? 100 : 0) : toNum(percent);
    final cur = b.currency;
    final e = (emoji ?? '').trim();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 108,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(e.isEmpty ? name : '$e $name',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: strong ? T.label : T.small.copyWith(color: K.ink2)),
            const SizedBox(height: 2),
            MoneyText(budget, style: T.bodyStrong.copyWith(fontSize: 13.5)),
          ]),
        ),
        const SizedBox(width: Sp.md),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            BudgetBar(percent: pct, todayPercent: today, height: 20),
            const SizedBox(height: 4),
            Row(children: [
              Flexible(
                child: MoneyText(spent,
                    kind: over ? 'expense' : null, style: T.small.copyWith(fontWeight: FontWeight.w600, color: K.blue)),
              ),
              const SizedBox(width: Sp.sm),
              Expanded(
                child: Text(
                  over ? 'Over ${money(-left, cur)}' : 'Left ${money(left, cur)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: T.tiny.copyWith(color: over ? K.expense : K.muted),
                ),
              ),
            ]),
          ]),
        ),
      ]),
    );
  }

  Widget _accountsCard(Book b) {
    final a = _accounts;
    final p = widget.period;
    final compared = a['compared_percent'];
    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(children: [
            Expanded(child: Text(label, style: T.small.copyWith(color: K.ink2))),
            const SizedBox(width: Sp.sm),
            Text(value, style: T.bodyStrong.copyWith(fontSize: 14).merge(T.tabular)),
          ]),
        );
    return KCard(
      padding: const EdgeInsetsDirectional.fromSTEB(Sp.lg, Sp.md, Sp.lg, Sp.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.account_balance_wallet_outlined, size: 20, color: K.blue),
          const SizedBox(width: Sp.sm),
          Text('Accounts', style: T.h3),
          const SizedBox(width: Sp.md),
          Expanded(
            child: Text(periodLabel(p.from, p.to), maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.end, style: T.tiny),
          ),
        ]),
        const SizedBox(height: Sp.sm),
        row('Compared with last month', compared == null ? 'No spending last month' : '${toNum(compared).round()}%'),
        row('Expenses from cash and bank', money(toNum(a['expense_cash']), b.currency)),
        row('Expenses on cards', money(toNum(a['expense_card']), b.currency)),
        row('Transfers out of cash and bank', money(toNum(a['transfer_out']), b.currency)),
      ]),
    );
  }
}
