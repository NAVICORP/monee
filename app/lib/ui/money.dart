import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/book.dart';
import '../core/format.dart';
import 'glass.dart';
import 'theme.dart';
import 'widgets.dart';

/// Money's colour by what a row counts as: income green, expense red,
/// transfers (and card spending that waits for payment day) grey.
Color moneyColor(String countsAs) => switch (countsAs) {
      'income' => K.income,
      'expense' => K.expense,
      _ => K.transfer,
    };

/// An amount in its currency, coloured by what it counts as.
class MoneyText extends StatelessWidget {
  const MoneyText(this.amount, {super.key, this.currency, this.kind, this.style, this.sign = false, this.symbol = true, this.align});
  final num amount;

  /// The amount's currency; the book's main currency when null.
  final String? currency;

  /// income, expense, transfer, card, or null for ink.
  final String? kind;
  final TextStyle? style;
  final bool sign;
  final bool symbol;
  final TextAlign? align;

  @override
  Widget build(BuildContext context) {
    final c = currencyOf(currency ?? Me.instance.book?.currency);
    final base = (style ?? T.bodyStrong).merge(T.tabular);
    return Text(c.format(amount, symbol: symbol, sign: sign),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: align,
        style: kind == null ? base : base.copyWith(color: moneyColor(kind!)));
  }
}

/// How a period is chosen on the Trans and Stats tabs.
enum PeriodKind { week, month, year, custom }

/// A period being looked at, and how to step it.
class Period {
  const Period(this.kind, this.from, this.to);
  final PeriodKind kind;
  final DateTime from;
  final DateTime to;

  static Period monthOf(Book b, DateTime day) {
    final (y, m) = b.monthOf(day);
    final (f, t) = b.month(y, m);
    return Period(PeriodKind.month, f, t);
  }

  static Period weekOf(Book b, DateTime day) {
    final (f, t) = b.week(day);
    return Period(PeriodKind.week, f, t);
  }

  static Period yearOf(Book b, DateTime day) {
    final (f, t) = b.year(day);
    return Period(PeriodKind.year, f, t);
  }

  static Period of(Book b, PeriodKind k, DateTime day) => switch (k) {
        PeriodKind.week => weekOf(b, day),
        PeriodKind.year => yearOf(b, day),
        _ => monthOf(b, day),
      };

  /// The period before (-1) or after (+1).
  Period step(Book b, int n) {
    switch (kind) {
      case PeriodKind.week:
        return weekOf(b, addDays(from, 7 * n));
      case PeriodKind.month:
        final (y, m) = b.monthOf(from);
        var mm = m + n, yy = y;
        while (mm > 12) {
          mm -= 12;
          yy++;
        }
        while (mm < 1) {
          mm += 12;
          yy--;
        }
        final (f, t) = b.month(yy, mm);
        return Period(PeriodKind.month, f, t);
      case PeriodKind.year:
        return yearOf(b, DateTime(from.year + n, from.month, from.day));
      case PeriodKind.custom:
        final days = to.difference(from).inDays + 1;
        return Period(PeriodKind.custom, addDays(from, days * n), addDays(to, days * n));
    }
  }

  bool contains(DateTime d) => !d.isBefore(from) && !d.isAfter(to);

  /// Oct 2026; 25.10 ~ 31.10; 2026; 1 Oct to 15 Oct 2026.
  String label(Book b) {
    switch (kind) {
      case PeriodKind.month:
        final (y, m) = b.monthOf(from);
        return '${kMonthsShort[m - 1]} $y';
      case PeriodKind.week:
        return '${dotDay(from)} ~ ${dotDay(to)}';
      case PeriodKind.year:
        return from.month == 1 ? '${from.year}' : '${from.year}-${(to.year % 100).toString().padLeft(2, '0')}';
      case PeriodKind.custom:
        return periodLabel(from, to);
    }
  }

  Map<String, String> get args => {'date_from': isoDay(from), 'date_to': isoDay(to)};
}

/// `<  Oct 2026  >`: steps back and forth; tapping the label picks a month or
/// a day. Sits at the top of the Trans and Stats tabs.
class PeriodBar extends StatelessWidget {
  const PeriodBar({super.key, required this.period, required this.onChanged, this.trailing = const []});
  final Period period;
  final ValueChanged<Period> onChanged;
  final List<Widget> trailing;

  Future<void> _pick(BuildContext context) async {
    final b = Me.instance.book!;
    if (period.kind == PeriodKind.custom) {
      final r = await pickPeriod(context, from: period.from, to: period.to);
      if (r != null) onChanged(Period(PeriodKind.custom, r.$1, r.$2));
      return;
    }
    final d = await pickDate(context, initial: period.from, title: 'Go to');
    if (d != null) onChanged(Period.of(b, period.kind, d));
  }

  @override
  Widget build(BuildContext context) {
    final b = Me.instance.book!;
    return SizedBox(
      height: 52,
      child: Row(children: [
        Expanded(
          child: Row(children: [
            IconButton(
              tooltip: 'Before',
              icon: const Icon(Icons.chevron_left_rounded, color: K.ink2),
              onPressed: () {
                HapticFeedback.selectionClick();
                onChanged(period.step(b, -1));
              },
            ),
            Flexible(
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => _pick(context),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                  child: Text(period.label(b), maxLines: 1, overflow: TextOverflow.ellipsis, style: T.h3),
                ),
              ),
            ),
            IconButton(
              tooltip: 'After',
              icon: const Icon(Icons.chevron_right_rounded, color: K.ink2),
              onPressed: () {
                HapticFeedback.selectionClick();
                onChanged(period.step(b, 1));
              },
            ),
          ]),
        ),
        ...trailing,
        const SizedBox(width: 4),
      ]),
    );
  }
}

/// Income, Expenses, Total in a row, like the strip under the Trans tab's
/// sub-tabs. A carried-over balance shows under Total.
class SummaryStrip extends StatelessWidget {
  const SummaryStrip({super.key, required this.income, required this.expense, required this.total, this.carry});
  final num income;
  final num expense;
  final num total;
  final num? carry;

  @override
  Widget build(BuildContext context) {
    Widget cell(String label, num v, String? kind, {String? under}) => Expanded(
          child: Column(children: [
            Text(label, style: T.tiny),
            const SizedBox(height: 2),
            MoneyText(v, kind: kind, symbol: false, align: TextAlign.center, style: T.bodyStrong.copyWith(fontSize: 15)),
            if (under != null) Text(under, style: T.tiny.copyWith(fontWeight: FontWeight.w500)),
          ]),
        );
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(color: K.surface, border: Border(bottom: BorderSide(color: K.border))),
      child: Row(children: [
        cell('Income', income, 'income'),
        cell('Expenses', expense, 'expense'),
        cell('Total', total, null,
            under: carry != null && carry != 0 ? 'Carried over ${currencyOf(Me.instance.book?.currency).format(carry!, symbol: false)}' : null),
      ]),
    );
  }
}

/// A row of small pill tabs (Daily, Calendar, Monthly, Total, Note), scrolling
/// sideways when they do not fit.
class PillTabs extends StatefulWidget {
  const PillTabs({super.key, required this.labels, required this.index, required this.onChanged});
  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  State<PillTabs> createState() => _PillTabsState();
}

/// The pills sit in a frosted glass track; the chosen one is a violet glass
/// drop that slides to the next pill with a small overshoot, like liquid.
class _PillTabsState extends State<PillTabs> {
  final _row = GlobalKey();
  late List<GlobalKey> _keys = _make();
  List<Rect>? _rects;

  List<GlobalKey> _make() => [for (var i = 0; i < widget.labels.length; i++) GlobalKey()];

  @override
  void didUpdateWidget(PillTabs old) {
    super.didUpdateWidget(old);
    if (old.labels.length != widget.labels.length) {
      _keys = _make();
      _rects = null;
    }
  }

  void _measure() {
    if (!mounted) return;
    final row = _row.currentContext?.findRenderObject() as RenderBox?;
    if (row == null || !row.hasSize) return;
    final rects = <Rect>[];
    for (final k in _keys) {
      final b = k.currentContext?.findRenderObject() as RenderBox?;
      if (b == null || !b.hasSize) return;
      rects.add(b.localToGlobal(Offset.zero, ancestor: row) & b.size);
    }
    final old = _rects;
    if (old != null && old.length == rects.length && Iterable.generate(rects.length).every((i) => old[i] == rects[i])) return;
    setState(() => _rects = rects);
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    final rects = _rects;
    final at = rects != null && widget.index < rects.length ? rects[widget.index] : null;
    final still = MediaQuery.disableAnimationsOf(context);
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Sp.page, vertical: 5),
        children: [
          Glass(
            padding: const EdgeInsets.all(3),
            child: Stack(children: [
              if (at != null)
                AnimatedPositioned(
                  duration: still ? Duration.zero : const Duration(milliseconds: 380),
                  curve: Curves.easeOutBack,
                  left: at.left,
                  top: at.top,
                  width: at.width,
                  height: at.height,
                  child: const IgnorePointer(child: Glass(tone: GlassTone.violet, shadow: false, child: SizedBox.expand())),
                ),
              Row(key: _row, mainAxisSize: MainAxisSize.min, children: [
                for (var i = 0; i < widget.labels.length; i++)
                  Semantics(
                    button: true,
                    selected: i == widget.index,
                    child: GestureDetector(
                      key: _keys[i],
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        if (i != widget.index) HapticFeedback.selectionClick();
                        widget.onChanged(i);
                      },
                      child: Container(
                        height: 32,
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        // Before the drop is placed (the very first frame), the
                        // chosen pill is coloured on its own.
                        decoration: at == null && i == widget.index ? const BoxDecoration(color: K.blue, borderRadius: BorderRadius.all(Radius.circular(999))) : null,
                        child: AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 200),
                          style: T.label.copyWith(color: i == widget.index ? Colors.white : K.ink2),
                          child: Text(widget.labels[i]),
                        ),
                      ),
                    ),
                  ),
              ]),
            ]),
          ),
        ],
      ),
    );
  }
}

/// A category's emoji in a soft circle (or its first letter).
class EmojiBadge extends StatelessWidget {
  const EmojiBadge(this.emoji, {super.key, this.name = '', this.size = 32, this.color = K.surface2});
  final String? emoji;
  final String name;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final e = (emoji ?? '').trim();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: e.isNotEmpty
          ? Text(e, style: TextStyle(fontSize: size * 0.5, height: 1))
          : Text(name.isEmpty ? '?' : initials(name), style: T.tiny.copyWith(color: K.ink2, fontSize: size * 0.36)),
    );
  }
}

/// A small coloured pill with a percentage, like the Stats list.
class PercentPill extends StatelessWidget {
  const PercentPill(this.percent, {super.key, required this.color});
  final num percent;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 46),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
      child: Text('${percent < 10 && percent != percent.roundToDouble() ? percent.toStringAsFixed(1) : percent.round()}%', textAlign: TextAlign.center, style: T.tiny.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
    );
  }
}

/// A budget bar: how much is used, with a mark for how far into the period today is.
class BudgetBar extends StatelessWidget {
  const BudgetBar({super.key, required this.percent, this.todayPercent, this.height = 22});
  final num percent;
  final num? todayPercent;
  final double height;

  @override
  Widget build(BuildContext context) {
    final over = percent > 100;
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      final fill = (percent.clamp(0, 100) / 100) * w;
      return SizedBox(
        height: height,
        child: Stack(children: [
          Container(decoration: BoxDecoration(color: K.surface2, borderRadius: BorderRadius.circular(8))),
          Container(width: fill, decoration: BoxDecoration(color: over ? K.expense : K.blue, borderRadius: BorderRadius.circular(8))),
          if (todayPercent != null)
            Positioned(left: (todayPercent!.clamp(0, 100) / 100) * (w - 2), top: 0, bottom: 0, child: Container(width: 2, color: K.ink2.withValues(alpha: 0.5))),
          Positioned.fill(
            child: Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text('${percent < 10 && percent != percent.roundToDouble() ? percent.toStringAsFixed(1) : percent.round()}%', style: T.tiny.copyWith(color: over || percent > 80 ? Colors.white : K.ink2, fontWeight: FontWeight.w800)),
              ),
            ),
          ),
        ]),
      );
    });
  }
}

/// A small helper for pages that show money: reload whenever anything is saved.
mixin ReloadOnChange<W extends StatefulWidget> on State<W> {
  int _seen = -1;

  /// Called first, and again after every change anywhere in the book.
  Future<void> reload();

  @override
  void initState() {
    super.initState();
    _seen = Me.instance.version;
    Me.instance.addListener(_onChange);
    reload();
  }

  void _onChange() {
    if (!mounted || Me.instance.version == _seen) return;
    _seen = Me.instance.version;
    reload();
  }

  @override
  void dispose() {
    Me.instance.removeListener(_onChange);
    super.dispose();
  }
}
