import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/book.dart';
import '../../core/format.dart';
import '../money.dart';
import '../theme.dart';
import '../widgets.dart';
import 'more_common.dart';

/// More > Budgets: a total budget and one per expense category, by month,
/// week or year. A budget applies from the month it is set until a later one
/// replaces it, so changing it never rewrites past months.
class BudgetsPage extends StatefulWidget {
  const BudgetsPage({super.key});

  @override
  State<BudgetsPage> createState() => _BudgetsPageState();
}

class _BudgetsPageState extends State<BudgetsPage> with ReloadOnChange<BudgetsPage> {
  String period = 'month';
  List<Map<String, dynamic>>? rows;
  String? error;

  @override
  Future<void> reload() async {
    try {
      final r = await Api.instance.select('budgets', order: 'from_month.desc');
      r.sort((a, b) => '${b['from_month']}'.compareTo('${a['from_month']}'));
      if (!mounted) return;
      setState(() {
        rows = r;
        error = null;
      });
    } on ApiError catch (e) {
      if (mounted) setState(() => error = e.message);
    }
  }

  /// The first day of this month, in the book's own calendar.
  /// The book month today falls in, so a month starting on the 25th is
  /// labelled by the month it starts in, as budget_status reads it.
  DateTime get _month {
    final b = Me.instance.book;
    if (b == null) {
      final t = DateTime.now();
      return DateTime(t.year, t.month, 1);
    }
    final (y, m) = b.monthOf(b.today);
    return DateTime(y, m, 1);
  }

  String get _periodWord => switch (period) { 'week' => 'Weekly', 'year' => 'Yearly', _ => 'Monthly' };

  bool _same(Map<String, dynamic> r, String? cat, String p) => r['category_id'] == cat && r['period'] == p;

  /// The budget row in force this month (the latest one from this month or before).
  Map<String, dynamic>? _current(String? cat, String p) {
    for (final r in rows ?? const <Map<String, dynamic>>[]) {
      if (!_same(r, cat, p)) continue;
      final f = parseDay(r['from_month']);
      if (f != null && !f.isAfter(_month)) return r;
    }
    return null;
  }

  /// The row set for this very month, if there is one.
  Map<String, dynamic>? _thisMonth(String? cat) {
    for (final r in rows ?? const <Map<String, dynamic>>[]) {
      if (_same(r, cat, period) && parseDay(r['from_month']) == _month) return r;
    }
    return null;
  }

  /// The row in force before this month, if there is one.
  Map<String, dynamic>? _before(String? cat) {
    for (final r in rows ?? const <Map<String, dynamic>>[]) {
      if (!_same(r, cat, period)) continue;
      final f = parseDay(r['from_month']);
      if (f != null && f.isBefore(_month)) return r;
    }
    return null;
  }

  /// The amount in force for the period on show (null when not set), and
  /// whether it is borrowed from the monthly budget.
  (num?, bool, DateTime?) _amount(String? cat) {
    final own = _current(cat, period);
    if (own != null) {
      final a = toNum(own['amount']);
      return (a > 0 ? a : null, false, parseDay(own['from_month']));
    }
    if (period != 'month') {
      final m = _current(cat, 'month');
      if (m != null && toNum(m['amount']) > 0) {
        return (toNum(m['amount']) * (period == 'week' ? 12 / 52 : 12), true, parseDay(m['from_month']));
      }
    }
    return (null, false, null);
  }

  Future<void> _edit(String? cat, String name) async {
    final b = Me.instance.book;
    if (b == null) return;
    final (amount, borrowed, _) = _amount(cat);
    final own = _current(cat, period);
    final hasOwn = own != null && toNum(own['amount']) > 0;
    final when = '${kMonthsShort[_month.month - 1]} ${_month.year}';
    final ans = await askAmount(context,
        title: name,
        label: '$_periodWord budget',
        initial: borrowed ? null : amount,
        currency: b.currency,
        yes: 'Save from $when',
        note: 'Applies from $when on. Months before keep the budget they had.',
        clearLabel: hasOwn ? 'Clear this budget' : null);
    if (ans == null || !mounted) return;
    final v = ans.amount;
    if (v == null || v == 0) {
      if (hasOwn) await _clear(cat);
    } else {
      await _set(cat, v);
    }
  }

  Future<void> _set(String? cat, num v) async {
    await attempt(context, () async {
      final mine = _thisMonth(cat);
      if (mine != null) {
        await Api.instance.update('budgets', {'amount': v}, where: {'id': 'eq.${mine['id']}'});
      } else {
        await Api.instance.insert('budgets', {'category_id': cat, 'period': period, 'amount': v, 'from_month': isoDay(_month)});
      }
      await Me.instance.changed();
    }, done: 'Budget saved');
  }

  /// Clears from this month on: this month's row goes, or becomes zero when
  /// an older budget would otherwise come back.
  Future<void> _clear(String? cat) async {
    await attempt(context, () async {
      final mine = _thisMonth(cat);
      final older = _before(cat);
      final olderCounts = older != null && toNum(older['amount']) > 0;
      if (mine != null) {
        if (olderCounts) {
          await Api.instance.update('budgets', {'amount': 0}, where: {'id': 'eq.${mine['id']}'});
        } else {
          await Api.instance.delete('budgets', where: {'id': 'eq.${mine['id']}'});
        }
      } else if (olderCounts) {
        await Api.instance.insert('budgets', {'category_id': cat, 'period': period, 'amount': 0, 'from_month': isoDay(_month)});
      }
      await Me.instance.changed();
    }, done: 'Budget cleared');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Budgets')),
      body: ListenableBuilder(listenable: Me.instance, builder: (context, _) => _body(context)),
    );
  }

  Widget _body(BuildContext context) {
    final b = Me.instance.book;
    if (b == null) return const Loading();
    if (rows == null) return error == null ? const Loading() : LoadFailed(message: error!, onRetry: reload);
    final can = b.canEdit;
    final tops = Me.instance.topCategories('expense');
    final (total, totalBorrowed, totalFrom) = _amount(null);
    num sum = 0;
    for (final c in tops) {
      sum += _amount(c.id).$1 ?? 0;
    }
    final effective = total ?? (sum > 0 ? sum : null);
    final when = '${kMonthsShort[_month.month - 1]} ${_month.year}';
    return PageBody(onRefresh: reload, children: [
      KSegmented<String>(
        expand: true,
        items: const [('month', 'Monthly'), ('week', 'Weekly'), ('year', 'Yearly')],
        value: period,
        onChanged: (v) => setState(() => period = v),
      ),
      const SizedBox(height: Sp.md),
      KCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$_periodWord budget in $when', style: T.tiny),
          const SizedBox(height: 2),
          if (effective == null)
            Text('Not set', style: T.h1.copyWith(color: K.muted))
          else
            MoneyText(effective, currency: b.currency, style: T.h1),
          const SizedBox(height: 2),
          Text(
              total != null
                  ? 'Your total budget${totalBorrowed ? ', from the monthly one' : ''}.'
                  : (sum > 0 ? 'No total set, so it is your category budgets added up.' : 'Set a total, or a budget for each category.'),
              style: T.small),
        ]),
      ),
      if (!can) ...[const SizedBox(height: Sp.md), const ReadOnlyNote('You can look at this book but not change it.')],
      const SectionTitle('Total'),
      KGroup(children: [
        _row(context, null, 'Total budget', null, b.currency, can, total, totalBorrowed, totalFrom),
      ]),
      const SectionTitle('Categories'),
      if (tops.isEmpty)
        const KCard(child: EmptyState(icon: Icons.category_outlined, text: 'No expense categories yet.'))
      else
        KGroup(children: [
          for (final c in tops)
            Builder(builder: (context) {
              final (a, borrowed, from) = _amount(c.id);
              return _row(context, c.id, c.name, c.emoji, b.currency, can, a, borrowed, from);
            }),
        ]),
      const SizedBox(height: Sp.md),
      const Text(
          'A budget applies from the month it is set until you change it. A weekly or yearly budget that is not set borrows the monthly one (a week is 12/52 of a month).',
          style: T.small),
    ]);
  }

  Widget _row(BuildContext context, String? cat, String name, String? emoji, String currency, bool can, num? amount, bool borrowed, DateTime? from) {
    final since = from == null ? null : 'Since ${kMonthsShort[from.month - 1]} ${from.year}';
    return KRow(
      leading: cat == null
          ? Container(
              width: 32,
              height: 32,
              decoration: const BoxDecoration(color: K.brand100, shape: BoxShape.circle),
              child: const Icon(Icons.savings_outlined, size: 17, color: K.brand600),
            )
          : EmojiBadge(emoji, name: name, size: 32),
      title: name,
      sub: amount == null ? 'Not set' : (borrowed ? 'From the monthly budget' : since),
      trailing: amount == null
          ? (can ? Text('Set', style: T.label.copyWith(color: K.blue)) : null)
          : MoneyText(amount, currency: currency, style: T.bodyStrong.copyWith(color: borrowed ? K.muted : K.ink)),
      onTap: can ? () => _edit(cat, name) : null,
    );
  }
}
