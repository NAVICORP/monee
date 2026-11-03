import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../money.dart';
import '../theme.dart';
import '../widgets.dart';
import 'search.dart';
import 'trans_common.dart';

/// The Note sub-tab: the period's income or expenses grouped by their note,
/// with how many and how much. Tapping a note searches for it.
class TransNoteView extends StatefulWidget {
  const TransNoteView({super.key, required this.period, required this.filter});
  final Period period;
  final Map<String, dynamic> filter;

  @override
  State<TransNoteView> createState() => _TransNoteViewState();
}

class _TransNoteViewState extends State<TransNoteView> with ReloadOnChange {
  static const _sorts = <String, String>{'amount': 'Amount', 'count': 'Count', 'name': 'Name'};

  String _kind = 'expense';
  String _sort = 'amount';
  List<Map<String, dynamic>> _rows = const <Map<String, dynamic>>[];
  bool _loaded = false;
  String? _error;
  int _ticket = 0;

  @override
  void didUpdateWidget(covariant TransNoteView old) {
    super.didUpdateWidget(old);
    if (!trSamePeriod(old.period, widget.period) || !identical(old.filter, widget.filter)) reload();
  }

  @override
  Future<void> reload() async {
    final t = ++_ticket;
    try {
      final r = await Api.instance.rpc('note_totals', {...widget.period.args, 'kind': _kind, 'f': widget.filter});
      if (!mounted || t != _ticket) return;
      setState(() {
        _rows = trRows(r);
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

  List<Map<String, dynamic>> get _sorted {
    final list = [..._rows];
    String name(Map<String, dynamic> r) => '${r['note'] ?? ''}'.toLowerCase();
    switch (_sort) {
      case 'count':
        list.sort((a, b) => toNum(b['count']).compareTo(toNum(a['count'])));
      case 'name':
        list.sort((a, b) {
          final x = name(a), y = name(b);
          if (x.isEmpty != y.isEmpty) return x.isEmpty ? 1 : -1;
          return x.compareTo(y);
        });
      default:
        list.sort((a, b) => toNum(b['total']).compareTo(toNum(a['total'])));
    }
    return list;
  }

  Future<void> _pickSort() async {
    final r = await showPicker<String>(
      context,
      title: 'Sort by',
      selected: _sort,
      options: [for (final e in _sorts.entries) PickOption(e.key, e.value)],
    );
    if (r != null && mounted) setState(() => _sort = r.value);
  }

  void _search(String note) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => SearchPage(query: note)));
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Loading();
    final rows = _sorted;
    final total = rows.fold<num>(0, (a, r) => a + toNum(r['total']));
    return PageBody(
      onRefresh: reload,
      bottom: 104,
      children: [
        Row(children: [
          KSegmented<String>(
            items: const [('income', 'Income'), ('expense', 'Expenses')],
            value: _kind,
            onChanged: (v) {
              if (v == _kind) return;
              setState(() {
                _kind = v;
                _loaded = false;
              });
              reload();
            },
          ),
          const Spacer(),
          Material(
            color: K.surface,
            shape: StadiumBorder(side: BorderSide(color: K.border)),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: _pickSort,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.sort_rounded, size: 16, color: K.ink2),
                  const SizedBox(width: 6),
                  Text(_sorts[_sort] ?? 'Amount', style: T.label),
                ]),
              ),
            ),
          ),
        ]),
        const SizedBox(height: Sp.md),
        if (_error != null) ...[Notice(_error!), const SizedBox(height: Sp.md)],
        if (rows.isEmpty && _error == null)
          EmptyState(icon: Icons.notes_rounded, text: _kind == 'income' ? 'No income in this period.' : 'No expenses in this period.')
        else if (rows.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(4, 0, 4, Sp.sm),
            child: Row(children: [
              Expanded(child: Text('${rows.length} ${rows.length == 1 ? 'note' : 'notes'}', style: T.small)),
              MoneyText(total, kind: _kind, style: T.label),
            ]),
          ),
          KGroup(children: [
            for (final r in rows) _row(r),
          ]),
        ],
      ],
    );
  }

  Widget _row(Map<String, dynamic> r) {
    final note = '${r['note'] ?? ''}'.trim();
    final count = toNum(r['count']).toInt();
    return KRow(
      title: note.isEmpty ? 'No note' : note,
      onTap: note.isEmpty ? null : () => _search(note),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        Pill.grey('$count'),
        const SizedBox(width: Sp.sm),
        MoneyText(toNum(r['total']), kind: _kind, style: T.bodyStrong.copyWith(fontSize: 14)),
      ]),
    );
  }
}
