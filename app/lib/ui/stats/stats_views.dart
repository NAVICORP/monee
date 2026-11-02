import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../charts.dart';
import '../money.dart';
import '../theme.dart';
import '../widgets.dart';

/// A list of json objects from the server, or an empty list.
List<Map<String, dynamic>> rowsOf(Object? j) =>
    (j is List ? j : const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();

/// A json object from the server, or null.
Map<String, dynamic>? mapOf(Object? j) => j is Map ? Map<String, dynamic>.from(j) : null;

/// 12.5K, 3M: for the top of a chart.
String compactMoney(num v, String currency) {
  final c = currencyOf(currency);
  final a = v.abs();
  String one(num x) {
    final s = x.toStringAsFixed(1);
    return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
  }

  final String n;
  if (a >= 1e9) {
    n = '${one(a / 1e9)}B';
  } else if (a >= 1e6) {
    n = '${one(a / 1e6)}M';
  } else if (a >= 1e3) {
    n = '${one(a / 1e3)}K';
  } else {
    n = '${a.round()}';
  }
  final s = c.spaced ? '${c.symbol} $n' : '${c.symbol}$n';
  return v < 0 ? '-$s' : s;
}

/// Jan .. Dec from a month number (1 to 12).
String monthShort(Object? m) {
  final i = toNum(m).toInt();
  return kMonthsShort[i < 1 || i > 12 ? 0 : i - 1];
}

/// What category_totals() answers: the total and one row per category.
class CategoryTotals {
  const CategoryTotals(this.total, this.rows);
  final num total;
  final List<Map<String, dynamic>> rows;

  static CategoryTotals from(Object? j) {
    final m = mapOf(j) ?? <String, dynamic>{};
    return CategoryTotals(toNum(m['total']), rowsOf(m['rows']));
  }
}

/// "🍔 Food", or the name alone.
String categoryLabel(Map<String, dynamic> r) {
  final e = (r['emoji'] as String? ?? '').trim();
  final n = r['name'] as String? ?? '';
  return e.isEmpty ? n : '$e $n';
}

/// The colour of the n-th slice and its pill.
Color sliceColor(int i) => K.chart[i % K.chart.length];

/// The week, month or year menu at the end of the period bar: a small pill
/// that shows how the period is chosen.
class PeriodMenuButton extends StatelessWidget {
  const PeriodMenuButton({super.key, required this.kind, required this.onTap});
  final PeriodKind kind;
  final VoidCallback onTap;

  static String nameOf(PeriodKind k) => switch (k) {
        PeriodKind.week => 'Weekly',
        PeriodKind.month => 'Monthly',
        PeriodKind.year => 'Yearly',
        PeriodKind.custom => 'Period',
      };

  @override
  Widget build(BuildContext context) {
    return Material(
      color: K.surface,
      shape: const StadiumBorder(side: BorderSide(color: K.border2)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(12, 6, 8, 6),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(nameOf(kind), style: T.label),
            const SizedBox(width: 2),
            const Icon(Icons.expand_more_rounded, size: 18, color: K.muted),
          ]),
        ),
      ),
    );
  }
}

/// Income | Expenses, each with its total; the one on show is underlined in
/// its colour.
class KindSwitch extends StatelessWidget {
  const KindSwitch({super.key, required this.kind, required this.income, required this.expense, required this.onChanged});
  final String kind;
  final num? income;
  final num? expense;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget cell(String k, String label, num? total) {
      final on = k == kind;
      return Expanded(
        child: Semantics(
          button: true,
          selected: on,
          child: InkWell(
            onTap: () => onChanged(k),
            child: Container(
              padding: const EdgeInsets.fromLTRB(Sp.sm, 10, Sp.sm, 8),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: on ? moneyColor(k) : Colors.transparent, width: 2.5))),
              // Centred, so the box stays as tall as its text.
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(label, style: T.label.copyWith(color: on ? K.ink : K.muted)),
                    if (total != null) ...[
                      const SizedBox(width: 6),
                      MoneyText(total, kind: on ? k : null, style: on ? T.bodyStrong : T.bodyStrong.copyWith(color: K.muted)),
                    ],
                  ]),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Material(
      color: K.surface,
      child: Container(
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: K.border))),
        child: Row(children: [
          cell('income', 'Income', income),
          cell('expense', 'Expenses', expense),
        ]),
      ),
    );
  }
}

/// The pie of a period's categories, then the list: a % pill in the slice's
/// colour, the category and its amount.
class CategoryBreakdown extends StatelessWidget {
  const CategoryBreakdown({super.key, required this.rows, this.onTap, this.canTap});
  final List<Map<String, dynamic>> rows;
  final void Function(Map<String, dynamic> row, Color color)? onTap;
  final bool Function(Map<String, dynamic> row)? canTap;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      KCard(
        padding: const EdgeInsets.symmetric(vertical: Sp.md),
        child: PieChart(slices: [
          for (var i = 0; i < rows.length; i++) Slice(categoryLabel(rows[i]), toNum(rows[i]['amount']), sliceColor(i)),
        ]),
      ),
      const SizedBox(height: Sp.md),
      KGroup(children: [
        for (var i = 0; i < rows.length; i++) _CategoryRow(row: rows[i], color: sliceColor(i), onTap: _tapFor(rows[i], sliceColor(i))),
      ]),
    ]);
  }

  VoidCallback? _tapFor(Map<String, dynamic> r, Color c) {
    final f = onTap;
    if (f == null || (canTap != null && !canTap!(r))) return null;
    return () => f(r, c);
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({required this.row, required this.color, this.onTap});
  final Map<String, dynamic> row;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 10, 10),
        child: Row(children: [
          PercentPill(toNum(row['percent']), color: color),
          const SizedBox(width: Sp.md),
          Expanded(child: Text(categoryLabel(row), maxLines: 1, overflow: TextOverflow.ellipsis, style: T.body)),
          const SizedBox(width: Sp.sm),
          MoneyText(toNum(row['amount']), style: T.bodyStrong),
          if (onTap != null) ...[
            const SizedBox(width: 2),
            const Icon(Icons.chevron_right_rounded, size: 18, color: K.border2),
          ],
        ]),
      ),
    );
  }
}

/// One budget: its name, the amount, the bar with today's mark, and what is
/// spent and left (or how far over it is).
class BudgetLine extends StatelessWidget {
  const BudgetLine({super.key, required this.title, this.emoji, required this.budget, required this.spent, required this.percent, this.todayPercent, required this.currency});
  final String title;
  final String? emoji;
  final num budget;
  final num spent;
  final num percent;
  final num? todayPercent;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final left = budget - spent;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        if (emoji != null && emoji!.trim().isNotEmpty) ...[
          EmojiBadge(emoji, name: title, size: 26),
          const SizedBox(width: Sp.sm),
        ],
        Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.bodyStrong)),
        const SizedBox(width: Sp.sm),
        MoneyText(budget, currency: currency, style: T.label),
      ]),
      const SizedBox(height: 6),
      BudgetBar(percent: percent, todayPercent: todayPercent, height: 18),
      const SizedBox(height: 5),
      Row(children: [
        Expanded(child: Text('Spent ${money(spent, currency)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: T.small)),
        const SizedBox(width: Sp.sm),
        Flexible(
          child: Text(left >= 0 ? 'Left ${money(left, currency)}' : 'Over by ${money(-left, currency)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: left >= 0 ? T.small : T.small.copyWith(color: K.expense, fontWeight: FontWeight.w700)),
        ),
      ]),
    ]);
  }
}

/// The Budget view: the total budget, then one bar per category, from
/// budget_status().
class BudgetView extends StatelessWidget {
  const BudgetView({super.key, required this.data, required this.currency, this.onSettings});
  final Map<String, dynamic> data;
  final String currency;
  final VoidCallback? onSettings;

  @override
  Widget build(BuildContext context) {
    final total = mapOf(data['total']);
    final rows = rowsOf(data['rows']);
    final today = data['today_percent'] == null ? null : toNum(data['today_percent']);
    final settings = onSettings == null
        ? null
        : KButton(label: 'Budget settings', icon: Icons.tune_rounded, kind: KButtonKind.ghost, small: true, onPressed: onSettings);
    if (total == null && rows.isEmpty) {
      return EmptyState(icon: Icons.savings_outlined, text: 'No budgets for this period yet.', action: settings);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (total != null)
        KCard(
          child: BudgetLine(
            title: 'Total budget',
            budget: toNum(total['budget']),
            spent: toNum(total['spent']),
            percent: toNum(total['percent']),
            todayPercent: today,
            currency: currency,
          ),
        ),
      if (rows.isNotEmpty) ...[
        SectionTitle('By category', top: total == null ? 4 : 20),
        KCard(
          padding: EdgeInsets.zero,
          child: Column(children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: BudgetLine(
                  title: rows[i]['name'] as String? ?? '',
                  emoji: rows[i]['emoji'] as String?,
                  budget: toNum(rows[i]['budget']),
                  spent: toNum(rows[i]['spent']),
                  percent: toNum(rows[i]['percent']),
                  todayPercent: today,
                  currency: currency,
                ),
              ),
            ],
          ]),
        ),
      ],
      if (today != null) ...[
        const SizedBox(height: Sp.sm),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text('The thin line on each bar marks today.', style: T.tiny.copyWith(fontWeight: FontWeight.w500)),
        ),
      ],
      if (settings != null) ...[
        const SizedBox(height: Sp.sm),
        Align(alignment: AlignmentDirectional.centerStart, child: settings),
      ],
    ]);
  }
}

/// The Note view: the period's entries grouped by their note, sortable by
/// amount, count or name.
class NoteView extends StatelessWidget {
  const NoteView({super.key, required this.rows, required this.kind, required this.sort, required this.onSort, this.onTap});
  final List<Map<String, dynamic>> rows;
  final String kind;

  /// amount, count or name.
  final String sort;
  final ValueChanged<String> onSort;
  final ValueChanged<String>? onTap;

  @override
  Widget build(BuildContext context) {
    String note(Map<String, dynamic> r) => (r['note'] as String? ?? '').trim();
    final sorted = [...rows]..sort((a, b) {
        switch (sort) {
          case 'count':
            final c = toNum(b['count']).compareTo(toNum(a['count']));
            return c != 0 ? c : toNum(b['total']).compareTo(toNum(a['total']));
          case 'name':
            final na = note(a), nb = note(b);
            if (na.isEmpty != nb.isEmpty) return na.isEmpty ? 1 : -1;
            return na.toLowerCase().compareTo(nb.toLowerCase());
          default:
            return toNum(b['total']).compareTo(toNum(a['total']));
        }
      });
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(
          child: Text(rows.length == 1 ? '1 note' : '${rows.length} notes', maxLines: 1, overflow: TextOverflow.ellipsis, style: T.small),
        ),
        const SizedBox(width: Sp.sm),
        KSegmented<String>(
          items: const [('amount', 'Amount'), ('count', 'Count'), ('name', 'Name')],
          value: sort,
          onChanged: onSort,
        ),
      ]),
      const SizedBox(height: Sp.md),
      KGroup(children: [
        for (final r in sorted)
          KRow(
            title: note(r).isEmpty ? 'No note' : note(r),
            sub: toNum(r['count']) == 1 ? '1 entry' : '${toNum(r['count']).round()} entries',
            trailing: MoneyText(toNum(r['total']), kind: kind, style: T.bodyStrong),
            onTap: onTap == null ? null : () => onTap!(note(r)),
          ),
      ]),
    ]);
  }
}
