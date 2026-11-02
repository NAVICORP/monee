import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/book.dart';
import '../../core/format.dart';
import '../money.dart';
import '../more/budgets.dart' show BudgetsPage;
import '../theme.dart';
import '../widgets.dart';
import 'category_stats.dart';
import 'stats_views.dart';

/// The Stats tab: where the money came from and where it went, by category,
/// for a week, a month, a year or any span; with the budgets and the notes.
class StatsPage extends StatefulWidget {
  const StatsPage({super.key});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> with ReloadOnChange<StatsPage> {
  static const _views = ['Stats', 'Budget', 'Note'];

  Period? _period;
  int view = 0;
  String kind = 'expense';
  String noteSort = 'amount';

  CategoryTotals? income;
  CategoryTotals? expense;
  Map<String, dynamic>? budget;
  List<Map<String, dynamic>>? notes;
  String? error;
  int _seq = 0;

  Period get period => _period ??= Period.monthOf(Me.instance.book!, Me.instance.book!.today);

  static String _budgetPeriod(PeriodKind k) => switch (k) {
        PeriodKind.week => 'week',
        PeriodKind.year => 'year',
        _ => 'month',
      };

  @override
  Future<void> reload() async {
    if (Me.instance.book == null) return;
    final p = period;
    final v = view;
    final k = kind;
    final wantBudget = v == 1 && p.kind != PeriodKind.custom;
    final wantNotes = v == 2;
    final seq = ++_seq;
    try {
      final r = await Future.wait<dynamic>([
        Api.instance.rpc('category_totals', {...p.args, 'kind': 'income', 'f': <String, dynamic>{}}),
        Api.instance.rpc('category_totals', {...p.args, 'kind': 'expense', 'f': <String, dynamic>{}}),
        if (wantBudget) Api.instance.rpc('budget_status', {...p.args, 'period': _budgetPeriod(p.kind)}),
        if (wantNotes) Api.instance.rpc('note_totals', {...p.args, 'kind': k, 'f': <String, dynamic>{}}),
      ]);
      if (!mounted || seq != _seq) return;
      setState(() {
        income = CategoryTotals.from(r[0]);
        expense = CategoryTotals.from(r[1]);
        if (wantBudget) budget = mapOf(r[2]) ?? <String, dynamic>{};
        if (wantNotes) notes = rowsOf(r[2]);
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
      income = null;
      expense = null;
      budget = null;
      notes = null;
      error = null;
    });
    reload();
  }

  void _setView(int i) {
    if (i == view) return;
    setState(() {
      view = i;
      error = null;
    });
    reload();
  }

  void _setKind(String k) {
    if (k == kind) return;
    setState(() {
      kind = k;
      notes = null;
    });
    if (view == 2) reload();
  }

  Future<void> _choosePeriodKind() async {
    final b = Me.instance.book;
    if (b == null) return;
    final picked = await showPicker<PeriodKind>(context, title: 'Show by', selected: period.kind, options: const [
      PickOption(PeriodKind.week, 'Weekly'),
      PickOption(PeriodKind.month, 'Monthly'),
      PickOption(PeriodKind.year, 'Yearly'),
      PickOption(PeriodKind.custom, 'Period', sub: 'Pick the first and the last day'),
    ]);
    if (picked == null || !mounted) return;
    if (picked.value == PeriodKind.custom) {
      final r = await pickPeriod(context, from: period.from, to: period.to);
      if (r == null || !mounted) return;
      _setPeriod(Period(PeriodKind.custom, r.$1, r.$2));
      return;
    }
    final anchor = period.contains(b.today) ? b.today : period.from;
    _setPeriod(Period.of(b, picked.value, anchor));
  }

  void _openRow(Map<String, dynamic> r, Color color) {
    final id = r['category_id'] as String?;
    final title = categoryLabel(r);
    final p = period;
    final k = kind;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => id != null
          ? CategoryStatsPage(kind: k, categoryId: id, title: title, period: p, color: color, hasSubs: r['has_subs'] == true)
          : specialTxnsPage(kind: k, key: r['key'] as String? ?? 'none', title: title, period: p),
    ));
  }

  static bool _canOpen(Map<String, dynamic> r) =>
      r['category_id'] != null || const {'transfer', 'card', 'fee', 'none'}.contains(r['key']);

  void _openNote(String note) {
    final p = period;
    final k = kind;
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => noteTxnsPage(kind: k, note: note, period: p)));
  }

  void _openBudgets() {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const BudgetsPage()));
  }

  @override
  Widget build(BuildContext context) {
    final b = Me.instance.book;
    if (b == null) return const SizedBox.shrink();
    final p = period;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 4, end: Sp.md),
            child: PeriodBar(period: p, onChanged: _setPeriod, trailing: [PeriodMenuButton(kind: p.kind, onTap: _choosePeriodKind)]),
          ),
          PillTabs(labels: _views, index: view, onChanged: _setView),
          if (view != 1) KindSwitch(kind: kind, income: income?.total, expense: expense?.total, onChanged: _setKind),
          Expanded(child: _body(b)),
        ]),
      ),
    );
  }

  Widget _wait() => error != null ? LoadFailed(message: error!, onRetry: reload) : const Loading();

  Widget _body(Book b) {
    switch (view) {
      case 1:
        return _budgetBody(b);
      case 2:
        return _noteBody(b);
      default:
        return _statsBody(b);
    }
  }

  Widget _statsBody(Book b) {
    final data = kind == 'income' ? income : expense;
    if (data == null) return _wait();
    final rows = data.rows.where((r) => toNum(r['amount']) > 0).toList();
    if (rows.isEmpty) {
      return PageBody(onRefresh: reload, children: [
        EmptyState(
          icon: Icons.pie_chart_outline_rounded,
          text: kind == 'income' ? 'No income in ${period.label(b)}.' : 'No expenses in ${period.label(b)}.',
        ),
      ]);
    }
    return PageBody(onRefresh: reload, children: [
      const SizedBox(height: Sp.sm),
      CategoryBreakdown(rows: rows, canTap: _canOpen, onTap: _openRow),
    ]);
  }

  Widget _budgetBody(Book b) {
    if (period.kind == PeriodKind.custom) {
      return PageBody(children: [
        EmptyState(
          icon: Icons.savings_outlined,
          text: 'Budgets run by week, month or year. Pick one of those to see them.',
          action: KButton(
            label: 'Show this month',
            kind: KButtonKind.secondary,
            small: true,
            onPressed: () => _setPeriod(Period.monthOf(b, b.today)),
          ),
        ),
      ]);
    }
    final d = budget;
    if (d == null) return _wait();
    return PageBody(onRefresh: reload, children: [
      const SizedBox(height: Sp.md),
      BudgetView(data: d, currency: b.currency, onSettings: b.canEdit ? _openBudgets : null),
    ]);
  }

  Widget _noteBody(Book b) {
    final list = notes;
    if (list == null) return _wait();
    if (list.isEmpty) {
      return PageBody(onRefresh: reload, children: [
        EmptyState(
          icon: Icons.sticky_note_2_outlined,
          text: kind == 'income' ? 'No income in ${period.label(b)}.' : 'No expenses in ${period.label(b)}.',
        ),
      ]);
    }
    return PageBody(onRefresh: reload, children: [
      const SizedBox(height: Sp.sm),
      NoteView(
        rows: list,
        kind: kind,
        sort: noteSort,
        onSort: (s) => setState(() => noteSort = s),
        onTap: _openNote,
      ),
    ]);
  }
}
