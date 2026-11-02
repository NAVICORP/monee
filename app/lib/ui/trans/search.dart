import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api.dart';
import '../../core/book.dart';
import '../../core/format.dart';
import '../money.dart';
import '../theme.dart';
import '../txn_list.dart';
import '../widgets.dart';
import 'trans_common.dart';

/// Search every transaction of the last ten years (and those dated ahead) by
/// words, amount and tags.
class SearchPage extends StatefulWidget {
  const SearchPage({super.key, this.query});

  /// Words to start with (the Note sub-tab opens a note this way).
  final String? query;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> with ReloadOnChange {
  static const _limit = 500;

  late final TextEditingController _q = TextEditingController(text: widget.query ?? '');
  final TextEditingController _bottom = TextEditingController();
  final TextEditingController _top = TextEditingController();
  final Set<String> _tags = <String>{};
  Timer? _wait;
  List<Txn> _found = const <Txn>[];
  bool _busy = false;
  bool _started = false;
  bool _searched = false;
  String? _error;
  int _ticket = 0;

  @override
  void dispose() {
    _wait?.cancel();
    _q.dispose();
    _bottom.dispose();
    _top.dispose();
    super.dispose();
  }

  num? _amount(TextEditingController c) {
    final t = c.text.replaceAll(',', '').trim();
    return t.isEmpty ? null : num.tryParse(t);
  }

  Map<String, dynamic> get _filter {
    final q = _q.text.trim();
    final min = _amount(_bottom);
    final max = _amount(_top);
    return <String, dynamic>{
      if (q.isNotEmpty) 'q': q,
      if (min != null) 'min': min,
      if (max != null) 'max': max,
      if (_tags.isNotEmpty) 'tags': _tags.toList(),
    };
  }

  /// Searches a moment after the typing stops.
  void _later() {
    _wait?.cancel();
    _wait = Timer(const Duration(milliseconds: 350), reload);
  }

  @override
  Future<void> reload() async {
    final f = _filter;
    final t = ++_ticket;
    if (f.isEmpty) {
      _started = true;
      if (mounted && (_searched || _found.isNotEmpty || _error != null)) {
        setState(() {
          _found = const <Txn>[];
          _searched = false;
          _busy = false;
          _error = null;
        });
      }
      return;
    }
    // The first search runs while the page is being built: no spinner then.
    if (_started && mounted) setState(() => _busy = true);
    _started = true;
    final today = trToday();
    try {
      final r = await Api.instance.rpc('txn_list', {
        'date_from': isoDay(addDays(today, -3650)),
        'date_to': isoDay(addDays(today, 400)),
        'f': f,
        'max_rows': _limit,
      });
      if (!mounted || t != _ticket) return;
      setState(() {
        _found = trRows(r).map(Txn.new).toList();
        _searched = true;
        _busy = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted || t != _ticket) return;
      setState(() {
        _searched = true;
        _busy = false;
        _error = trError(e);
      });
    }
  }

  Widget _amountField(TextEditingController c, String hint) => TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
        style: T.bodyStrong,
        onChanged: (_) => _later(),
        decoration: InputDecoration(hintText: hint, isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
      );

  Widget _tagChip(String name) {
    final on = _tags.contains(name);
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 6),
      child: Material(
        color: on ? K.deep : K.surface,
        shape: StadiumBorder(side: BorderSide(color: on ? K.deep : K.border)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            setState(() {
              if (on) {
                _tags.remove(name);
              } else {
                _tags.add(name);
              }
            });
            reload();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Text('#$name', style: T.label.copyWith(color: on ? Colors.white : K.ink2)),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tags = Me.instance.tags.map((t) => '${t['name'] ?? ''}').where((n) => n.isNotEmpty).toList();
    num inc = 0, exp = 0;
    for (final t in _found) {
      if (t.countsAs == 'income') inc += t.amountMain;
      if (t.countsAs == 'expense') exp += t.amountMain;
    }
    final n = _found.length;
    return Scaffold(
      backgroundColor: K.paper,
      appBar: AppBar(title: const Text('Search')),
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Sp.page, Sp.xs, Sp.page, Sp.sm),
          child: SearchField(controller: _q, hint: 'Note, category, account or tag', onChanged: (_) => _later()),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Sp.page, 0, Sp.page, Sp.sm),
          child: Row(children: [
            Expanded(child: _amountField(_bottom, 'Amount from')),
            const SizedBox(width: Sp.sm),
            Expanded(child: _amountField(_top, 'Amount to')),
          ]),
        ),
        if (tags.isNotEmpty)
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(Sp.page, 2, Sp.page, 6),
              children: [for (final g in tags) _tagChip(g)],
            ),
          ),
        if (_busy) const LinearProgressIndicator(minHeight: 2) else const SizedBox(height: 2),
        if (_searched && _error == null)
          Container(
            padding: const EdgeInsets.fromLTRB(Sp.page, 8, Sp.page, 8),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: K.border))),
            child: Row(children: [
              Expanded(
                child: Text(n >= _limit ? 'The newest $_limit found' : (n == 1 ? '1 found' : '$n found'), style: T.small),
              ),
              if (inc != 0) Flexible(child: MoneyText(inc, kind: 'income', style: T.label)),
              if (inc != 0 && exp != 0) const SizedBox(width: Sp.md),
              if (exp != 0) Flexible(child: MoneyText(exp, kind: 'expense', style: T.label)),
            ]),
          ),
        Expanded(child: _results()),
      ]),
    );
  }

  Widget _results() {
    if (_error != null) return ListView(padding: const EdgeInsets.all(Sp.page), children: [Notice(_error!)]);
    if (!_searched) {
      return const Center(child: EmptyState(icon: Icons.search_rounded, text: 'Search by note, category, account, amount or tag.'));
    }
    if (_found.isEmpty) return const Center(child: EmptyState(icon: Icons.search_off_rounded, text: 'Nothing matches.'));
    return ListView.separated(
      padding: EdgeInsets.only(bottom: 32 + MediaQuery.paddingOf(context).bottom),
      itemCount: _found.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: Sp.page),
      itemBuilder: (_, i) => TxnRow(_found[i], showDate: true),
    );
  }
}
