import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/book.dart';
import '../../core/format.dart';
import '../entry/entry_page.dart';
import '../money.dart';
import '../theme.dart';
import '../txn_list.dart';
import '../widgets.dart';
import 'trans_common.dart';

/// The Calendar sub-tab: the period's days in weeks from the book's week
/// start day, each with its income, expenses and net. Tapping a day opens
/// its list and memos.
class TransCalendarView extends StatefulWidget {
  const TransCalendarView({super.key, required this.period, required this.filter, this.onPick});
  final Period period;
  final Map<String, dynamic> filter;

  /// Told about the day last opened (the + button adds on it).
  final ValueChanged<DateTime>? onPick;

  @override
  State<TransCalendarView> createState() => _TransCalendarViewState();
}

class _TransCalendarViewState extends State<TransCalendarView> with ReloadOnChange {
  Map<DateTime, (num, num)> _days = {};
  Map<DateTime, (num, num)> _up = {};
  Map<DateTime, List<Color>> _memos = {};
  bool _loaded = false;
  String? _error;
  int _ticket = 0;

  /// The grid's first and last days: whole weeks around the period.
  (DateTime, DateTime) _range(Book b) {
    final p = widget.period;
    final back = (p.from.weekday % 7 - b.weekStart + 7) % 7;
    final fwd = 6 - (p.to.weekday % 7 - b.weekStart + 7) % 7;
    return (addDays(p.from, -back), addDays(p.to, fwd));
  }

  @override
  void didUpdateWidget(covariant TransCalendarView old) {
    super.didUpdateWidget(old);
    if (!trSamePeriod(old.period, widget.period) || !identical(old.filter, widget.filter)) reload();
  }

  @override
  Future<void> reload() async {
    final b = Me.instance.book;
    if (b == null) return;
    final t = ++_ticket;
    final (start, end) = _range(b);
    final f = widget.filter;
    final upFrom = trLater(start, addDays(b.today, 1));
    try {
      final r = await Future.wait<dynamic>([
        Api.instance.rpc('day_totals', {'date_from': isoDay(start), 'date_to': isoDay(end), 'f': f}),
        Api.instance.select('day_memos',
            columns: 'id,day,color', where: {'and': '(day.gte.${isoDay(start)},day.lte.${isoDay(end)})'}, order: 'day,created_at'),
        if (!upFrom.isAfter(end)) Api.instance.rpc('upcoming', {'date_from': isoDay(upFrom), 'date_to': isoDay(end)}),
      ]);
      final days = <DateTime, (num, num)>{};
      for (final x in trRows(r[0])) {
        final d = parseDay(x['day']);
        if (d != null) days[d] = (toNum(x['income']), toNum(x['expense']));
      }
      final memos = <DateTime, List<Color>>{};
      for (final x in trRows(r[1])) {
        final d = parseDay(x['day']);
        if (d != null) memos.putIfAbsent(d, () => <Color>[]).add(trHex(x['color'] as String?));
      }
      final up = <DateTime, (num, num)>{};
      if (r.length > 2) {
        for (final u in trRows(r[2])) {
          if (!trUpcomingPasses(u, f)) continue;
          final d = parseDay(u['day']);
          if (d == null) continue;
          final counts = trUpcomingTxn(u).countsAs;
          final v = toNum(u['amount_main']);
          final (num i, num e) = up[d] ?? (0, 0);
          if (counts == 'income') up[d] = (i + v, e);
          if (counts == 'expense') up[d] = (i, e + v);
        }
      }
      if (!mounted || t != _ticket) return;
      setState(() {
        _days = days;
        _memos = memos;
        _up = up;
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

  void _openDay(DateTime d) {
    widget.onPick?.call(d);
    showKSheet<void>(context, title: '${dayLabel(d)} ${d.year}', builder: (_) => TransDaySheet(day: d, filter: widget.filter));
  }

  @override
  Widget build(BuildContext context) {
    final b = Me.instance.book;
    if (b == null || !_loaded) return const Loading();
    final (start, end) = _range(b);
    final days = <DateTime>[for (var d = start; !d.isAfter(end); d = addDays(d, 1)) d];
    final names = b.weekdayNames;
    final today = b.today;
    return RefreshIndicator(
      onRefresh: reload,
      color: K.blue,
      child: ListView(physics: const AlwaysScrollableScrollPhysics(), padding: EdgeInsets.zero, children: [
        Container(
          height: 28,
          decoration: const BoxDecoration(color: K.surface, border: Border(bottom: BorderSide(color: K.border))),
          child: Row(children: [
            for (final n in names)
              Expanded(
                child: Center(
                  child: Text(n, style: T.tiny.copyWith(color: n == 'Sun' ? K.expense : (n == 'Sat' ? K.blue : K.muted))),
                ),
              ),
          ]),
        ),
        for (var w = 0; w * 7 + 6 < days.length; w++)
          Row(children: [for (var i = 0; i < 7; i++) Expanded(child: _cell(b, days[w * 7 + i], today))]),
        if (_error != null) Padding(padding: const EdgeInsets.all(Sp.page), child: Notice(_error!)),
        const SizedBox(height: 96),
      ]),
    );
  }

  Widget _cell(Book b, DateTime d, DateTime today) {
    final inside = widget.period.contains(d);
    final isToday = d == today;
    final dow = d.weekday % 7;
    final main = b.main;
    Widget line(num v, Color c, {bool dim = false}) => SizedBox(
          height: 12.5,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerEnd,
            child: Text(main.format(v, symbol: false), maxLines: 1, style: trCellStyle.copyWith(color: dim ? c.withValues(alpha: 0.45) : c)),
          ),
        );
    final lines = <Widget>[];
    final (num inc, num exp) = _days[d] ?? (0, 0);
    if (inc != 0) lines.add(line(inc, K.income));
    if (exp != 0) lines.add(line(exp, K.expense));
    if (inc != 0 && exp != 0) lines.add(line(inc - exp, K.ink));
    final (num upInc, num upExp) = _up[d] ?? (0, 0);
    if (upInc != 0) lines.add(line(upInc, K.income, dim: true));
    if (upExp != 0) lines.add(line(upExp, K.expense, dim: true));
    final memos = _memos[d] ?? const <Color>[];
    final label = d.day == 1 ? '${d.day}.${d.month}' : '${d.day}';
    final numColor = dow == 0 ? K.expense : (dow == 6 ? K.blue : K.ink2);
    return Material(
      color: isToday ? K.brand100 : (inside ? K.surface : K.surface2),
      child: InkWell(
        onTap: () => _openDay(d),
        child: Container(
          height: 64,
          padding: const EdgeInsetsDirectional.fromSTEB(4, 3, 3, 3),
          decoration: const BoxDecoration(border: Border(right: BorderSide(color: K.border), bottom: BorderSide(color: K.border))),
          child: Opacity(
            opacity: inside ? 1 : 0.4,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: isToday
                        ? Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            decoration: BoxDecoration(color: K.blue, borderRadius: BorderRadius.circular(6)),
                            child: Text(label, maxLines: 1, overflow: TextOverflow.clip, style: T.tiny.copyWith(color: Colors.white)),
                          )
                        : Text(label, maxLines: 1, overflow: TextOverflow.clip, style: T.tiny.copyWith(color: numColor)),
                  ),
                ),
                for (final c in memos.take(3))
                  Container(
                    width: 5,
                    height: 5,
                    margin: const EdgeInsetsDirectional.only(start: 2),
                    decoration: BoxDecoration(color: c, shape: BoxShape.circle),
                  ),
              ]),
              const Spacer(),
              ...lines.take(3),
            ]),
          ),
        ),
      ),
    );
  }
}

/// A day's transactions, repeats still to come, and memos, with buttons to
/// add either. Opened from a calendar day.
class TransDaySheet extends StatefulWidget {
  const TransDaySheet({super.key, required this.day, this.filter = const <String, dynamic>{}});
  final DateTime day;
  final Map<String, dynamic> filter;

  @override
  State<TransDaySheet> createState() => _TransDaySheetState();
}

class _TransDaySheetState extends State<TransDaySheet> with ReloadOnChange {
  List<Txn> _txns = const <Txn>[];
  List<Txn> _up = const <Txn>[];
  List<Map<String, dynamic>> _memos = const <Map<String, dynamic>>[];
  bool _loaded = false;
  String? _error;
  int _ticket = 0;

  @override
  Future<void> reload() async {
    final b = Me.instance.book;
    if (b == null) return;
    final t = ++_ticket;
    final d = isoDay(widget.day);
    final f = widget.filter;
    try {
      final r = await Future.wait<dynamic>([
        Api.instance.rpc('txn_list', {'date_from': d, 'date_to': d, 'f': f, 'max_rows': 500}),
        Api.instance.select('day_memos', where: {'day': 'eq.$d'}, order: 'created_at'),
        if (widget.day.isAfter(b.today)) Api.instance.rpc('upcoming', {'date_from': d, 'date_to': d}),
      ]);
      if (!mounted || t != _ticket) return;
      setState(() {
        _txns = trRows(r[0]).map(Txn.new).toList();
        _memos = trRows(r[1]);
        _up = r.length > 2 ? trRows(r[2]).where((u) => trUpcomingPasses(u, f)).map(trUpcomingTxn).toList() : const <Txn>[];
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

  Future<void> _deleteMemo(Map<String, dynamic> m) async {
    final ok = await confirm(context, title: 'Delete this memo?', text: 'It comes off this day for good.', yes: 'Delete', danger: true);
    if (!ok || !mounted) return;
    try {
      await Api.instance.delete('day_memos', where: {'id': 'eq.${m['id']}'});
      await Me.instance.changed();
    } on ApiError catch (e) {
      if (mounted) toast(context, e.message, bad: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Padding(padding: EdgeInsets.symmetric(vertical: 32), child: Loading());
    final edit = Me.instance.book?.canEdit ?? false;
    num inc = 0, exp = 0;
    for (final t in _txns) {
      if (t.countsAs == 'income') inc += t.amountMain;
      if (t.countsAs == 'expense') exp += t.amountMain;
    }
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (_error != null) ...[Notice(_error!), const SizedBox(height: Sp.md)],
      if (inc != 0 || exp != 0)
        Padding(
          padding: const EdgeInsets.only(bottom: Sp.sm),
          child: Row(children: [
            if (inc != 0) ...[
              const Text('Income', style: T.tiny),
              const SizedBox(width: 4),
              Flexible(child: MoneyText(inc, kind: 'income', style: T.label)),
              const SizedBox(width: Sp.lg),
            ],
            if (exp != 0) ...[
              const Text('Expenses', style: T.tiny),
              const SizedBox(width: 4),
              Flexible(child: MoneyText(exp, kind: 'expense', style: T.label)),
            ],
          ]),
        ),
      if (_txns.isEmpty && _up.isEmpty)
        const Padding(padding: EdgeInsets.symmetric(vertical: Sp.md), child: Text('Nothing recorded on this day.', style: T.small))
      else
        KGroup(children: [
          for (final t in _txns) TxnRow(t),
          for (final t in _up) TxnRow(t, dim: true, onTap: () {}),
        ]),
      if (_memos.isNotEmpty) const SectionTitle('Memos', top: Sp.lg),
      for (final m in _memos) _memoTile(m, edit),
      if (edit) ...[
        const SizedBox(height: Sp.lg),
        Wrap(spacing: Sp.sm, runSpacing: Sp.sm, children: [
          KButton(label: 'Add transaction', icon: Icons.add_rounded, small: true, onPressed: () => openEntry(context, day: widget.day)),
          KButton(
            label: 'Add memo',
            icon: Icons.edit_note_rounded,
            small: true,
            kind: KButtonKind.secondary,
            onPressed: () => trEditMemo(context, day: widget.day),
          ),
        ]),
      ],
    ]);
  }

  Widget _memoTile(Map<String, dynamic> m, bool edit) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Sp.sm),
      child: Material(
        color: K.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(K.rMd), side: const BorderSide(color: K.border)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: edit ? () => trEditMemo(context, day: widget.day, memo: m) : null,
          child: Container(
            decoration: BoxDecoration(border: BorderDirectional(start: BorderSide(color: trHex(m['color'] as String?), width: 4))),
            child: Row(children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(12, 11, 4, 11),
                  child: Text('${m['text'] ?? ''}', style: T.body.copyWith(fontSize: 14)),
                ),
              ),
              if (edit)
                IconButton(
                  tooltip: 'Delete',
                  icon: const Icon(Icons.delete_outline_rounded, size: 19, color: K.muted),
                  onPressed: () => _deleteMemo(m),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Adds a memo to a day, or changes or deletes one.
Future<void> trEditMemo(BuildContext context, {required DateTime day, Map<String, dynamic>? memo}) {
  final memoId = memo?['id'];
  final text = TextEditingController(text: '${memo?['text'] ?? ''}');
  String? colour = memo?['color'] as String?;
  var busy = false;
  return showKSheet<void>(
    context,
    title: memoId == null ? 'New memo' : 'Edit memo',
    builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
      Future<void> save() async {
        final words = text.text.trim();
        if (words.isEmpty) {
          toast(ctx, 'Write the memo first.', bad: true);
          return;
        }
        set(() => busy = true);
        try {
          final row = <String, dynamic>{'day': isoDay(day), 'text': words, 'color': colour};
          if (memoId == null) {
            await Api.instance.insert('day_memos', row);
          } else {
            await Api.instance.update('day_memos', row, where: {'id': 'eq.$memoId'});
          }
          if (ctx.mounted) Navigator.of(ctx).pop();
          await Me.instance.changed();
        } on ApiError catch (e) {
          if (ctx.mounted) {
            set(() => busy = false);
            toast(ctx, e.message, bad: true);
          }
        }
      }

      Future<void> remove() async {
        final ok = await confirm(ctx, title: 'Delete this memo?', text: 'It comes off this day for good.', yes: 'Delete', danger: true);
        if (!ok || !ctx.mounted) return;
        set(() => busy = true);
        try {
          await Api.instance.delete('day_memos', where: {'id': 'eq.$memoId'});
          if (ctx.mounted) Navigator.of(ctx).pop();
          await Me.instance.changed();
        } on ApiError catch (e) {
          if (ctx.mounted) {
            set(() => busy = false);
            toast(ctx, e.message, bad: true);
          }
        }
      }

      Widget swatch(String? hex) {
        final on = hex == null ? colour == null : colour?.toUpperCase() == hex;
        return Semantics(
          button: true,
          selected: on,
          label: hex == null ? 'No colour' : 'Colour',
          child: GestureDetector(
            onTap: () => set(() => colour = hex),
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: hex == null ? K.surface : trHex(hex),
                shape: BoxShape.circle,
                border: Border.all(color: on ? K.ink : K.border2, width: on ? 2.5 : 1),
              ),
              child: hex == null
                  ? const Icon(Icons.format_color_reset_outlined, size: 16, color: K.muted)
                  : (on ? const Icon(Icons.check_rounded, size: 18, color: Colors.white) : null),
            ),
          ),
        );
      }

      return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(dateLabel(day), style: T.small),
        const SizedBox(height: Sp.md),
        KField(label: 'Memo', controller: text, maxLines: 4, autofocus: memoId == null),
        const SizedBox(height: Sp.lg),
        const Text('Colour', style: T.label),
        const SizedBox(height: Sp.sm),
        Wrap(spacing: 10, runSpacing: 10, children: [
          swatch(null),
          for (final h in trMemoColours) swatch(h),
        ]),
        const SizedBox(height: Sp.xl),
        Row(children: [
          if (memoId != null) ...[
            KButton(label: 'Delete', kind: KButtonKind.danger, onPressed: busy ? null : remove),
            const SizedBox(width: Sp.sm),
          ],
          Expanded(child: KButton(label: 'Save', expand: true, busy: busy, onPressed: save)),
        ]),
      ]);
    }),
  );
}
