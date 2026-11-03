import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api.dart';
import '../../core/book.dart';
import '../../core/format.dart';
import '../entry/calculator.dart' show showCalculator;
import '../money.dart';
import '../theme.dart';
import '../widgets.dart';
import 'more_common.dart';

/// More > Repeats: salary, rent and subscriptions that record themselves.
/// Pause or restart one, change its amount, note or end date, or delete it
/// (entries already recorded stay).
class RepeatsPage extends StatefulWidget {
  const RepeatsPage({super.key});

  @override
  State<RepeatsPage> createState() => _RepeatsPageState();
}

class _RepeatsPageState extends State<RepeatsPage> with ReloadOnChange<RepeatsPage> {
  List<Map<String, dynamic>>? rules;
  Map<String, DateTime> next = {};
  String? error;

  @override
  Future<void> reload() async {
    final b = Me.instance.book;
    if (b == null) return;
    try {
      final today = b.today;
      final r = await Future.wait<dynamic>([
        Api.instance.select('repeat_rules', order: 'created_at'),
        Api.instance.rpc('upcoming', {'date_from': isoDay(today), 'date_to': isoDay(addDays(today, 400))}),
      ]);
      final list = (r[0] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      final n = <String, DateTime>{};
      final up = r[1];
      if (up is List) {
        for (final x in up) {
          if (x is! Map) continue;
          final id = x['repeat_id'];
          final d = parseDay(x['day']);
          if (id is String && d != null && !n.containsKey(id)) n[id] = d;
        }
      }
      if (!mounted) return;
      setState(() {
        rules = list;
        next = n;
        error = null;
      });
    } on ApiError catch (e) {
      if (mounted) setState(() => error = e.message);
    }
  }

  // ---------------------------------------------------------------- dates

  /// The n-th date of a rule (0 is the first), as the database counts:
  /// months keep their day, or the month's last day when it is shorter.
  static DateTime _date(Map<String, dynamic> r, int n) {
    final start = parseDay(r['starts_on']) ?? DateTime.now();
    final every = (r['every'] as num?)?.toInt() ?? 1;
    final k = n * every;
    return switch (r['freq']) {
      'day' => addDays(start, k),
      'week' => addDays(start, 7 * k),
      'year' => Book.monthDay(start.year + k, start.month, start.day),
      _ => Book.monthDay(start.year, start.month + k, start.day),
    };
  }

  static int _done(Map<String, dynamic> r) => (r['done'] as num?)?.toInt() ?? 0;

  /// How many dates were missed before today (while the rule was off).
  int _missed(Map<String, dynamic> r, DateTime today) {
    final end = parseDay(r['ends_on']);
    var n = _done(r), count = 0;
    while (count < 5000) {
      final d = _date(r, n);
      if (!d.isBefore(today) || (end != null && d.isAfter(end))) break;
      n++;
      count++;
    }
    return count;
  }

  static String every(Map<String, dynamic> r) {
    final n = (r['every'] as num?)?.toInt() ?? 1;
    final unit = switch (r['freq']) { 'day' => 'day', 'week' => 'week', 'year' => 'year', _ => 'month' };
    final head = n == 1 ? 'Every $unit' : 'Every $n ${unit}s';
    final start = parseDay(r['starts_on']);
    final end = parseDay(r['ends_on']);
    return '$head${start == null ? '' : ' from ${shortDate(start)}'}${end == null ? '' : ', until ${shortDate(end)}'}';
  }

  /// Next: Sat 1 Nov, Paused or Ended.
  String _status(Map<String, dynamic> r, DateTime today) {
    if (r['active'] != true) return 'Paused';
    final end = parseDay(r['ends_on']);
    final d = next[r['id']] ?? _date(r, _done(r));
    if (end != null && d.isAfter(end)) return 'Ended';
    return 'Next: ${relativeDay(d, today)}';
  }

  // ---------------------------------------------------------------- changes

  Future<void> _toggle(Map<String, dynamic> r, bool on) async {
    final b = Me.instance.book;
    if (b == null) return;
    final patch = <String, dynamic>{'active': on};
    if (on) {
      final missed = _missed(r, b.today);
      if (missed > 0) {
        final p = await showPicker<bool>(context, title: 'Turn it back on', options: [
          PickOption(false, 'Skip the missed dates', sub: '$missed date${missed == 1 ? '' : 's'} while it was off ${missed == 1 ? 'is' : 'are'} not recorded'),
          const PickOption(true, 'Record them too', sub: 'An entry for each date it missed'),
        ]);
        if (p == null || !mounted) return;
        if (!p.value) patch['done'] = _done(r) + missed;
      }
    }
    if (!mounted) return;
    await attempt(context, () async {
      await Api.instance.update('repeat_rules', patch, where: {'id': 'eq.${r['id']}'});
      if (on) {
        try {
          await Api.instance.rpc('catch_up');
        } on ApiError {
          // Recorded the next time Pursee opens.
        }
      }
      await Me.instance.changed();
    }, done: on ? 'Repeat on' : 'Repeat paused');
  }

  Future<void> _edit(Map<String, dynamic> r) async {
    final res = await showKSheet<Object>(context, title: 'Edit the repeat', builder: (ctx) => _RepeatEdit(rule: r));
    if (res == null || !mounted) return;
    if (res == 'delete') {
      await _delete(r);
      return;
    }
    if (res is! Map<String, dynamic>) return;
    await attempt(context, () async {
      await Api.instance.update('repeat_rules', res, where: {'id': 'eq.${r['id']}'});
      await Me.instance.changed();
    }, done: 'Repeat saved');
  }

  Future<void> _delete(Map<String, dynamic> r) async {
    final ok = await confirm(context,
        title: 'Delete this repeat?', text: 'Nothing more is recorded from it. Entries it already recorded stay.', yes: 'Delete', danger: true);
    if (!ok || !mounted) return;
    await attempt(context, () async {
      await Api.instance.delete('repeat_rules', where: {'id': 'eq.${r['id']}'});
      await Me.instance.changed();
    }, done: 'Repeat deleted');
  }

  // ---------------------------------------------------------------- page

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Repeats')),
      body: _body(context),
    );
  }

  Widget _body(BuildContext context) {
    final b = Me.instance.book;
    if (b == null) return const Loading();
    final list = rules;
    if (list == null) return error == null ? const Loading() : LoadFailed(message: error!, onRetry: reload);
    final can = b.canEdit;
    final active = list.where((r) => r['active'] == true).toList();
    final paused = list.where((r) => r['active'] != true).toList();
    return PageBody(onRefresh: reload, children: [
      if (!can) const ReadOnlyNote('You can look at this book but not change it.'),
      if (list.isEmpty)
        const KCard(
            child: EmptyState(
                icon: Icons.event_repeat_rounded, text: 'No repeats yet. When you add an entry, set it to repeat and it records itself on its dates.')),
      if (active.isNotEmpty) ...[
        const SectionTitle('On', top: 4),
        for (final r in active) ...[_card(r, b.today, can), const SizedBox(height: Sp.sm)],
      ],
      if (paused.isNotEmpty) ...[
        SectionTitle('Paused', top: active.isEmpty ? 4 : 20),
        for (final r in paused) ...[_card(r, b.today, can), const SizedBox(height: Sp.sm)],
      ],
      if (list.isNotEmpty)
        Padding(
          padding: EdgeInsets.only(top: Sp.sm),
          child: Text('Repeats record themselves on their dates. Deleting one keeps what it already recorded.', style: T.small),
        ),
    ]);
  }

  Widget _card(Map<String, dynamic> r, DateTime today, bool can) {
    final me = Me.instance;
    final kind = r['kind'] as String? ?? 'expense';
    final acc = me.account(r['account_id'] as String?);
    final to = me.account(r['to_account_id'] as String?);
    final catId = r['category_id'] as String?;
    final cat = me.category(catId);
    final parent = me.category(cat?.parentId);
    final title = kind == 'transfer' ? 'Transfer' : (cat == null ? 'Uncategorised' : me.categoryPath(catId));
    final where = kind == 'transfer' ? '${acc?.name ?? 'Deleted account'} to ${to?.name ?? 'Deleted account'}' : (acc?.name ?? 'Deleted account');
    final note = (r['note'] as String? ?? '').trim();
    final on = r['active'] == true;
    final status = _status(r, today);
    return KCard(
      padding: EdgeInsets.zero,
      onTap: can ? () => _edit(r) : null,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 8, 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (kind == 'transfer')
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(color: K.surface2, shape: BoxShape.circle),
              child: Icon(Icons.swap_horiz_rounded, size: 18, color: K.transfer),
            )
          else
            EmojiBadge(cat?.emoji ?? parent?.emoji, name: title, size: 34),
          const SizedBox(width: Sp.md),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.bodyStrong)),
                const SizedBox(width: Sp.sm),
                MoneyText(toNum(r['amount']), currency: acc?.currency, kind: kind),
              ]),
              Text(note.isEmpty ? where : '$where, $note', maxLines: 1, overflow: TextOverflow.ellipsis, style: T.small),
              Text(every(r), maxLines: 2, overflow: TextOverflow.ellipsis, style: T.small),
              const SizedBox(height: 6),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: on && status != 'Ended' ? Pill(status, icon: Icons.schedule_rounded) : Pill.grey(status),
              ),
            ]),
          ),
          const SizedBox(width: Sp.xs),
          Switch(value: on, onChanged: can ? (v) => _toggle(r, v) : null),
        ]),
      ),
    );
  }
}

/// The amount, note and end date of a repeat. Pops a patch for
/// repeat_rules, or 'delete'.
class _RepeatEdit extends StatefulWidget {
  const _RepeatEdit({required this.rule});
  final Map<String, dynamic> rule;

  @override
  State<_RepeatEdit> createState() => _RepeatEditState();
}

class _RepeatEditState extends State<_RepeatEdit> {
  late final num _was = toNum(widget.rule['amount']);
  late final TextEditingController _amount = TextEditingController(text: plainNumber(_was));
  late final TextEditingController _note = TextEditingController(text: widget.rule['note'] as String? ?? '');
  late DateTime? end = parseDay(widget.rule['ends_on']);
  String? error;

  String? get _currency => Me.instance.account(widget.rule['account_id'] as String?)?.currency;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _calc() async {
    final v = await showCalculator(context, start: readNumber(_amount.text), currency: _currency);
    if (v != null && mounted) setState(() => _amount.text = plainNumber(v));
  }

  Future<void> _pickEnd() async {
    final start = parseDay(widget.rule['starts_on']) ?? DateTime.now();
    final p = await showPicker<bool>(context, title: 'Ends', selected: end != null, options: const [
      PickOption(false, 'No end', sub: 'Keeps going until you pause or delete it'),
      PickOption(true, 'On a day', sub: 'The last day it can record'),
    ]);
    if (p == null || !mounted) return;
    if (!p.value) {
      setState(() => end = null);
      return;
    }
    final today = Me.instance.book?.today ?? DateTime.now();
    final initial = end ?? (today.isBefore(start) ? start : today);
    final d = await pickDate(context, initial: initial, first: start, title: 'Last day');
    if (d != null && mounted) setState(() => end = d);
  }

  void _save() {
    final v = readNumber(_amount.text);
    if (v == null || v <= 0) {
      setState(() => error = 'Enter an amount above zero.');
      return;
    }
    final note = _note.text.trim();
    if (note.length > 120) {
      setState(() => error = 'Keep the note to 120 characters.');
      return;
    }
    final patch = <String, dynamic>{
      'amount': v,
      'note': note.isEmpty ? null : note,
      'ends_on': end == null ? null : isoDay(end!),
    };
    // A transfer between currencies keeps the rate it had.
    final to = widget.rule['to_amount'];
    if (widget.rule['kind'] == 'transfer' && to != null && _was > 0 && v != _was) {
      patch['to_amount'] = (toNum(to) * v / _was * 10000).round() / 10000;
    }
    Navigator.of(context).pop(patch);
  }

  @override
  Widget build(BuildContext context) {
    final cur = _currency == null ? null : currencyOf(_currency);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (error != null) ...[Notice(error!), const SizedBox(height: Sp.md)],
      Text(_RepeatsPageState.every(widget.rule), style: T.small),
      const SizedBox(height: Sp.md),
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          child: KField(
            label: 'Amount',
            controller: _amount,
            keyboard: const TextInputType.numberWithOptions(decimal: true),
            formatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            prefix: cur == null ? null : '${cur.symbol} ',
          ),
        ),
        const SizedBox(width: Sp.xs),
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: RoundIcon(Icons.calculate_outlined, tooltip: 'Calculator', size: 40, color: K.blue, onTap: _calc),
        ),
      ]),
      const SizedBox(height: Sp.md),
      KField(label: 'Note', controller: _note, hint: 'Optional'),
      const SizedBox(height: Sp.md),
      KChoice(label: 'Ends', value: end == null ? 'No end' : dateLabel(end!), icon: Icons.event_busy_outlined, onTap: _pickEnd),
      const SizedBox(height: Sp.sm),
      Text('New amounts apply to the dates still to come. Entries already recorded keep theirs.', style: T.small),
      const SizedBox(height: Sp.lg),
      KButton(label: 'Save', icon: Icons.check_rounded, expand: true, onPressed: _save),
      const SizedBox(height: Sp.sm),
      Center(child: KButton(label: 'Delete this repeat', kind: KButtonKind.danger, small: true, onPressed: () => Navigator.of(context).pop('delete'))),
    ]);
  }
}
