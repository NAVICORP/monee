import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/book.dart';
import '../../core/format.dart';
import '../money.dart';
import '../theme.dart';
import '../widgets.dart';
import 'trans_common.dart';

/// The Trans tab's filter: categories (Income and Expenses), accounts and
/// tags to show. Returns the filter json (`{}` for none), or null when closed.
Future<Map<String, dynamic>?> showFilter(BuildContext context, {required Period period, Map<String, dynamic>? current}) {
  return Navigator.of(context).push<Map<String, dynamic>>(MaterialPageRoute<Map<String, dynamic>>(
    fullscreenDialog: true,
    builder: (_) => _FilterPage(period: period, current: current ?? const <String, dynamic>{}),
  ));
}

class _FilterPage extends StatefulWidget {
  const _FilterPage({required this.period, required this.current});
  final Period period;
  final Map<String, dynamic> current;

  @override
  State<_FilterPage> createState() => _FilterPageState();
}

Set<String> _ids(Object? v) => v is List ? v.map((e) => '$e').where((e) => e.isNotEmpty).toSet() : <String>{};

class _FilterPageState extends State<_FilterPage> {
  late final Set<String> _cats = _ids(widget.current['categories']);
  late final Set<String> _accs = _ids(widget.current['accounts']);
  late final Set<String> _tags = _ids(widget.current['tags']);
  int _tab = 1;

  /// The period's transactions (no filter), for the rings and the amounts.
  List<Txn>? _txns;
  Map<String, num> _catSums = {};

  /// Per account: income, transfers in, expenses, transfers out (main currency).
  Map<String, List<num>> _accSums = {};
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Api.instance.rpc('txn_list', {...widget.period.args, 'f': const <String, dynamic>{}, 'max_rows': 10000});
      final txns = trRows(r).map(Txn.new).toList();
      if (!mounted) return;
      setState(() {
        _txns = txns;
        _sum(txns);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _txns = const <Txn>[];
        _error = trError(e);
      });
    }
  }

  void _sum(List<Txn> txns) {
    final me = Me.instance;
    final cats = <String, num>{};
    final accs = <String, List<num>>{};
    void addCat(String? id, num v) {
      if (id == null) return;
      cats[id] = (cats[id] ?? 0) + v;
      final p = me.category(id)?.parentId;
      if (p != null) cats[p] = (cats[p] ?? 0) + v;
    }

    List<num> acc(String id) => accs.putIfAbsent(id, () => <num>[0, 0, 0, 0]);
    for (final t in txns) {
      final v = t.amountMain;
      if (t.kind == 'transfer') {
        acc(t.accountId)[3] += v;
        final to = t.toAccountId;
        if (to != null) acc(to)[1] += v;
        continue;
      }
      if (t.kind == 'income') {
        acc(t.accountId)[0] += v;
      } else {
        acc(t.accountId)[2] += v;
      }
      if (t.splits.isEmpty) {
        addCat(t.categoryId, v);
      } else {
        for (final s in t.splits) {
          addCat(s['category_id'] as String?, toNum(s['amount']) * t.rate);
        }
      }
    }
    _catSums = cats;
    _accSums = accs;
  }

  bool get _any => _cats.isNotEmpty || _accs.isNotEmpty || _tags.isNotEmpty;

  /// Whether a transaction passes the filter being picked (as the database decides).
  bool _passes(Txn t) {
    final me = Me.instance;
    if (_cats.isNotEmpty) {
      final ids = <String?>[t.categoryId, for (final s in t.splits) s['category_id'] as String?];
      final ok = ids.any((id) => id != null && (_cats.contains(id) || _cats.contains(me.category(id)?.parentId)));
      if (!ok) return false;
    }
    if (_accs.isNotEmpty) {
      final linked = me.account(t.accountId)?.linkedAccountId;
      if (!_accs.contains(t.accountId) && !_accs.contains(t.toAccountId) && !(linked != null && _accs.contains(linked))) return false;
    }
    if (_tags.isNotEmpty) {
      final want = _tags.map((e) => e.toLowerCase()).toSet();
      if (!t.tags.any((g) => want.contains(g.toLowerCase()))) return false;
    }
    return true;
  }

  void _apply() {
    Navigator.of(context).pop(<String, dynamic>{
      if (_cats.isNotEmpty) 'categories': _cats.toList(),
      if (_accs.isNotEmpty) 'accounts': _accs.toList(),
      if (_tags.isNotEmpty) 'tags': _tags.toList(),
    });
  }

  // ---------------------------------------------------------------- categories

  bool? _parentValue(String id) {
    if (_cats.contains(id)) return true;
    return Me.instance.subsOf(id).any((s) => _cats.contains(s.id)) ? null : false;
  }

  void _toggleParent(String id) {
    final subs = Me.instance.subsOf(id);
    setState(() {
      if (_cats.contains(id)) {
        _cats.remove(id);
      } else {
        _cats.add(id);
      }
      for (final s in subs) {
        _cats.remove(s.id);
      }
    });
  }

  void _toggleSub(String parentId, String subId) {
    final subs = Me.instance.subsOf(parentId);
    setState(() {
      if (_cats.contains(parentId)) {
        // The whole category was on: keep its other subcategories.
        _cats.remove(parentId);
        for (final x in subs) {
          if (x.id != subId) _cats.add(x.id);
        }
      } else if (_cats.contains(subId)) {
        _cats.remove(subId);
      } else {
        _cats.add(subId);
        if (subs.every((x) => _cats.contains(x.id))) {
          for (final x in subs) {
            _cats.remove(x.id);
          }
          _cats.add(parentId);
        }
      }
    });
  }

  void _toggleAllCategories(String kind, bool on) {
    final me = Me.instance;
    setState(() {
      for (final c in me.topCategories(kind)) {
        for (final s in me.subsOf(c.id)) {
          _cats.remove(s.id);
        }
        if (on) {
          _cats.add(c.id);
        } else {
          _cats.remove(c.id);
        }
      }
    });
  }

  Widget? _catAmount(String id, String kind) {
    final v = _catSums[id];
    if (v == null || v == 0) return null;
    return MoneyText(v, kind: kind, symbol: false, style: T.small.copyWith(fontWeight: FontWeight.w600));
  }

  List<Widget> _categoryRows(String kind) {
    final me = Me.instance;
    final tops = me.topCategories(kind);
    final subsOn = me.book?.subcategories ?? true;
    if (tops.isEmpty) {
      return [EmptyState(icon: Icons.category_outlined, text: kind == 'income' ? 'No income categories yet.' : 'No expense categories yet.')];
    }
    final allOn = tops.every((c) => _cats.contains(c.id));
    final someOn = tops.any((c) => _parentValue(c.id) != false);
    return [
      _checkRow(value: allOn ? true : (someOn ? null : false), title: 'All', strong: true, onTap: () => _toggleAllCategories(kind, !allOn)),
      for (final c in tops) ...[
        _checkRow(value: _parentValue(c.id), title: c.label, onTap: () => _toggleParent(c.id), trailing: _catAmount(c.id, kind)),
        if (subsOn)
          for (final s in me.subsOf(c.id))
            _checkRow(
              value: _cats.contains(c.id) || _cats.contains(s.id),
              title: s.label,
              indent: true,
              onTap: () => _toggleSub(c.id, s.id),
              trailing: _catAmount(s.id, kind),
            ),
      ],
    ];
  }

  // ---------------------------------------------------------------- accounts

  Widget _twoLines(num? top, num? bottom, String kind) {
    return SizedBox(
      width: 84,
      child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        if (top != null && top != 0) MoneyText(top, kind: kind, symbol: false, align: TextAlign.end, style: T.tiny.copyWith(fontSize: 12)),
        if (bottom != null && bottom != 0) MoneyText(bottom, symbol: false, align: TextAlign.end, style: T.tiny.copyWith(fontWeight: FontWeight.w500)),
      ]),
    );
  }

  Widget? _accAmount(String id) {
    final v = _accSums[id];
    if (v == null) return null;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      _twoLines(v[0], v[1], 'income'),
      const SizedBox(width: Sp.sm),
      _twoLines(v[2], v[3], 'expense'),
    ]);
  }

  List<Widget> _accountRows() {
    final me = Me.instance;
    final live = me.liveAccounts;
    if (live.isEmpty) return const [EmptyState(icon: Icons.account_balance_wallet_outlined, text: 'No accounts yet.')];
    final groupIds = <String>[];
    for (final a in live) {
      if (!groupIds.contains(a.groupId)) groupIds.add(a.groupId);
    }
    final allOn = live.every((a) => _accs.contains(a.id));
    final someOn = live.any((a) => _accs.contains(a.id));
    Widget caption(String top, String bottom, Color c) => SizedBox(
          width: 84,
          child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(top, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.tiny.copyWith(color: c)),
            Text(bottom, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.tiny.copyWith(fontWeight: FontWeight.w500)),
          ]),
        );
    return [
      _checkRow(
        value: allOn ? true : (someOn ? null : false),
        title: 'All',
        strong: true,
        onTap: () => setState(() {
          if (allOn) {
            _accs.clear();
          } else {
            _accs.addAll(live.map((a) => a.id));
          }
        }),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          caption('Income', 'Transfer in', K.income),
          const SizedBox(width: Sp.sm),
          caption('Expenses', 'Transfer out', K.expense),
        ]),
      ),
      for (final gid in groupIds) ...[
        Builder(builder: (_) {
          final inGroup = live.where((a) => a.groupId == gid).toList();
          final on = inGroup.every((a) => _accs.contains(a.id));
          final some = inGroup.any((a) => _accs.contains(a.id));
          final g = me.group(gid);
          return Material(
            color: K.surface2,
            child: _checkRow(
              value: on ? true : (some ? null : false),
              title: g?.label ?? 'Accounts',
              strong: true,
              onTap: () => setState(() {
                for (final a in inGroup) {
                  if (on) {
                    _accs.remove(a.id);
                  } else {
                    _accs.add(a.id);
                  }
                }
              }),
            ),
          );
        }),
        for (final a in live.where((a) => a.groupId == gid))
          _checkRow(
            value: _accs.contains(a.id),
            title: a.name,
            onTap: () => setState(() {
              if (!_accs.remove(a.id)) _accs.add(a.id);
            }),
            trailing: _accAmount(a.id),
          ),
      ],
    ];
  }

  // ---------------------------------------------------------------- tags

  List<Widget> _tagRows() {
    final names = Me.instance.tags.map((t) => '${t['name'] ?? ''}').where((n) => n.isNotEmpty).toList();
    for (final n in _tags) {
      if (!names.contains(n)) names.add(n);
    }
    if (names.isEmpty) return const [EmptyState(icon: Icons.sell_outlined, text: 'No tags yet.')];
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(Sp.page, Sp.md, Sp.page, 0),
        child: Wrap(spacing: 6, runSpacing: 6, children: [
          for (final n in names)
            Material(
              color: _tags.contains(n) ? K.deep : K.surface,
              shape: StadiumBorder(side: BorderSide(color: _tags.contains(n) ? K.deep : K.border)),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => setState(() {
                  if (!_tags.remove(n)) _tags.add(n);
                }),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  child: Text('#$n', style: T.label.copyWith(color: _tags.contains(n) ? Colors.white : K.ink2)),
                ),
              ),
            ),
        ]),
      ),
    ];
  }

  // ---------------------------------------------------------------- parts

  Widget _checkRow({required bool? value, required String title, required VoidCallback onTap, bool indent = false, bool strong = false, Widget? trailing}) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsetsDirectional.fromSTEB(indent ? 36 : 8, 0, Sp.page, 0),
        child: Row(children: [
          Checkbox(
            value: value,
            tristate: true,
            onChanged: (_) => onTap(),
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: strong ? T.bodyStrong : T.body.copyWith(fontSize: 14)),
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: Sp.sm), trailing],
        ]),
      ),
    );
  }

  Widget _ring(String label, num part, num whole, String kind) {
    final v = whole == 0 ? 0.0 : (part / whole).clamp(0, 1).toDouble();
    final color = kind == 'income' ? K.income : K.expense;
    final track = kind == 'income' ? K.incomeBg : K.expenseBg;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(label, style: T.tiny),
      const SizedBox(height: 6),
      SizedBox(
        width: 62,
        height: 62,
        child: Stack(fit: StackFit.expand, children: [
          CircularProgressIndicator(value: v, strokeWidth: 7, color: color, backgroundColor: track),
          Center(child: Text('${(v * 100).round()}%', style: T.label)),
        ]),
      ),
      const SizedBox(height: 6),
      MoneyText(_any ? part : whole, kind: kind, symbol: false, align: TextAlign.center, style: T.label),
    ]);
  }

  Widget _header() {
    final txns = _txns;
    if (txns == null) return const SizedBox(height: 132, child: Loading());
    num inc = 0, exp = 0, selInc = 0, selExp = 0;
    final any = _any;
    for (final t in txns) {
      final ok = any && _passes(t);
      if (t.countsAs == 'income') {
        inc += t.amountMain;
        if (ok) selInc += t.amountMain;
      }
      if (t.countsAs == 'expense') {
        exp += t.amountMain;
        if (ok) selExp += t.amountMain;
      }
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(Sp.page, Sp.md, Sp.page, Sp.md),
      decoration: BoxDecoration(color: K.surface, border: Border(bottom: BorderSide(color: K.border))),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (_error != null) ...[Notice(_error!), const SizedBox(height: Sp.sm)],
        Row(children: [
          Expanded(child: _ring('Income', selInc, inc, 'income')),
          Expanded(child: _ring('Expenses', selExp, exp, 'expense')),
          Expanded(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(any ? 'Selected total' : 'Total', style: T.tiny),
              const SizedBox(height: 4),
              MoneyText(any ? selInc - selExp : inc - exp, symbol: false, align: TextAlign.center, style: T.bodyStrong),
            ]),
          ),
        ]),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final b = Me.instance.book;
    final showTags = Me.instance.tags.isNotEmpty || _tags.isNotEmpty;
    final tab = _tab == 3 && !showTags ? 1 : _tab;
    final rows = switch (tab) {
      0 => _categoryRows('income'),
      2 => _accountRows(),
      3 => _tagRows(),
      _ => _categoryRows('expense'),
    };
    return Scaffold(
      backgroundColor: K.paper,
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          const Text('Filter'),
          if (b != null) Text(widget.period.label(b), style: T.tiny),
        ]),
      ),
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _header(),
        Padding(
          padding: const EdgeInsets.fromLTRB(Sp.page, Sp.md, Sp.page, Sp.sm),
          child: KSegmented<int>(
            items: [(0, 'Income'), (1, 'Expenses'), (2, 'Accounts'), if (showTags) (3, 'Tags')],
            value: tab,
            expand: true,
            onChanged: (v) => setState(() => _tab = v),
          ),
        ),
        Expanded(
          child: Material(
            type: MaterialType.transparency,
            child: ListView(padding: const EdgeInsets.only(bottom: Sp.lg), children: rows),
          ),
        ),
        Container(
          decoration: BoxDecoration(color: K.surface, border: Border(top: BorderSide(color: K.border))),
          padding: const EdgeInsets.fromLTRB(Sp.page, Sp.md, Sp.page, Sp.md),
          child: SafeArea(
            top: false,
            child: Row(children: [
              KButton(
                label: 'Clear',
                kind: KButtonKind.secondary,
                onPressed: () => Navigator.of(context).pop(<String, dynamic>{}),
              ),
              const SizedBox(width: Sp.sm),
              Expanded(child: KButton(label: 'Apply', expand: true, onPressed: _apply)),
            ]),
          ),
        ),
      ]),
    );
  }
}
