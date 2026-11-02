import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/book.dart';
import '../../core/format.dart';
import '../entry/entry_page.dart';
import '../money.dart';
import '../theme.dart';
import '../widgets.dart';
import 'bookmarks.dart';
import 'calendar_view.dart';
import 'daily_view.dart';
import 'filter.dart';
import 'monthly_view.dart';
import 'note_view.dart';
import 'search.dart';
import 'total_view.dart';
import 'trans_common.dart';

/// The Trans tab: the period switcher with Bookmarks, Search and Filter, the
/// Daily, Calendar, Monthly, Total and Note sub-tabs, the period's totals,
/// and the + button.
class TransPage extends StatefulWidget {
  const TransPage({super.key});

  @override
  State<TransPage> createState() => _TransPageState();
}

class _TransPageState extends State<TransPage> with ReloadOnChange {
  static const _tabs = ['Daily', 'Calendar', 'Monthly', 'Total', 'Note'];

  Book? _book;
  int _tab = 0;
  Period _period = Period(PeriodKind.month, DateTime(2000), DateTime(2000));

  /// The Monthly sub-tab's year: the year its first month is labelled in.
  int _fy = 2000;
  Map<String, dynamic> _filter = const <String, dynamic>{};

  /// The calendar day last opened (the + button adds on it).
  DateTime? _picked;
  num _income = 0;
  num _expense = 0;
  num _total = 0;
  num? _carry;
  int _ticket = 0;

  @override
  void initState() {
    _setUp(Me.instance.book);
    super.initState();
  }

  void _setUp(Book? b) {
    _book = b;
    if (b == null) return;
    _tab = b.startScreen == 'calendar' ? 1 : 0;
    _period = Period.monthOf(b, b.today);
    _fy = _fyOf(b, b.today);
    _filter = const <String, dynamic>{};
    _picked = null;
  }

  /// The book's settings were loaded again: a new book starts afresh; the same
  /// book keeps showing the same month (or week) under its new settings.
  void _follow(Book b) {
    final old = _book;
    if (old == null || old.id != b.id) {
      _setUp(b);
      return;
    }
    _book = b;
    if (_period.kind == PeriodKind.month && old.monthStartDay != b.monthStartDay) {
      final (y, m) = old.monthOf(_period.from);
      final (f, t) = b.month(y, m);
      _period = Period(PeriodKind.month, f, t);
    } else if (_period.kind == PeriodKind.week && old.weekStart != b.weekStart) {
      _period = Period.weekOf(b, _period.from);
    }
  }

  /// The year (by its first month's label) a day's month belongs to.
  int _fyOf(Book b, DateTime d) {
    final (y, m) = b.monthOf(d);
    return m >= b.fyStartMonth ? y : y - 1;
  }

  /// The Monthly sub-tab's year: from its first month's first day to the
  /// day before the next year's first month.
  Period _yearPeriod(Book b) {
    final from = b.month(_fy, b.fyStartMonth).$1;
    final next = b.month(_fy + 1, b.fyStartMonth).$1;
    return Period(PeriodKind.year, from, addDays(next, -1));
  }

  Period _visible(Book b) => _tab == 2 ? _yearPeriod(b) : _period;

  @override
  Future<void> reload() async {
    final b = Me.instance.book;
    if (b == null) return;
    if (!identical(b, _book)) {
      _follow(b);
      if (mounted) setState(() {});
    }
    final p = _visible(b);
    final t = ++_ticket;
    try {
      final r = trMap(await Api.instance.rpc('period_totals', {...p.args, 'f': _filter}));
      if (!mounted || t != _ticket) return;
      setState(() {
        _income = toNum(r['income']);
        _expense = toNum(r['expense']);
        _total = toNum(r['total']);
        _carry = r['carry_over'] == true ? toNum(r['carry']) : null;
      });
    } catch (_) {
      // The strip keeps what it showed; the list below says what went wrong.
    }
  }

  void _setTab(int i) {
    final b = _book;
    if (b == null || i == _tab) return;
    setState(() {
      if (i == 2) {
        _fy = _fyOf(b, _period.from);
      } else if (_tab == 2) {
        // Back from Monthly: stay in the year it showed.
        final y = _yearPeriod(b);
        if (!y.contains(_period.from)) {
          final today = b.today;
          _period = Period.monthOf(b, y.contains(today) ? today : (today.isBefore(y.from) ? y.from : y.to));
        }
      }
      if (i == 1 && _period.kind != PeriodKind.month) _period = Period.monthOf(b, _period.from);
      _tab = i;
    });
    reload();
  }

  void _onPeriod(Period p) {
    setState(() {
      if (_tab == 2) {
        // PeriodBar steps and picks years from their first day.
        _fy = p.from.year;
      } else {
        _period = p;
      }
      _picked = null;
    });
    reload();
  }

  /// A month or week tapped in Monthly: show it in Daily.
  void _openPeriod(Period p) {
    setState(() {
      _period = p;
      _tab = 0;
      _picked = null;
    });
    reload();
  }

  void _setFilter(Map<String, dynamic> f) {
    setState(() => _filter = f);
    reload();
  }

  Future<void> _openFilter() async {
    final b = _book;
    if (b == null) return;
    final r = await showFilter(context, period: _visible(b), current: _filter);
    if (r == null || !mounted) return;
    _setFilter(r);
  }

  void _openSearch() {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SearchPage()));
  }

  void _add() {
    final b = _book;
    if (b == null) return;
    final picked = _picked;
    final day = _tab == 1 && picked != null && _period.contains(picked) ? picked : b.today;
    openEntry(context, day: day);
  }

  String _filterWords() {
    int n(String k) {
      final v = _filter[k];
      return v is List ? v.length : 0;
    }

    String w(int c, String one, String many) => '$c ${c == 1 ? one : many}';
    final parts = <String>[
      if (n('categories') > 0) w(n('categories'), 'category', 'categories'),
      if (n('accounts') > 0) w(n('accounts'), 'account', 'accounts'),
      if (n('tags') > 0) w(n('tags'), 'tag', 'tags'),
    ];
    return parts.isEmpty ? 'Filter on' : 'Only ${parts.join(', ')}';
  }

  Widget _filterButton() {
    final on = _filter.isNotEmpty;
    return Stack(clipBehavior: Clip.none, children: [
      RoundIcon(Icons.tune_rounded, tooltip: on ? 'Filter is on' : 'Filter', onTap: _openFilter, color: on ? K.blue : null),
      if (on)
        PositionedDirectional(
          end: 7,
          top: 7,
          child: IgnorePointer(
            child: Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(color: K.blue, shape: BoxShape.circle, border: Border.all(color: K.paper, width: 1.5)),
            ),
          ),
        ),
    ]);
  }

  Widget _filterBar() {
    return Container(
      color: K.brand100,
      padding: const EdgeInsetsDirectional.fromSTEB(Sp.page, 2, 6, 2),
      child: Row(children: [
        const Icon(Icons.tune_rounded, size: 15, color: K.brand600),
        const SizedBox(width: 6),
        Expanded(
          child: Text(_filterWords(), maxLines: 1, overflow: TextOverflow.ellipsis, style: T.tiny.copyWith(color: K.brand600)),
        ),
        InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () => _setFilter(const <String, dynamic>{}),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Text('Clear', style: T.label.copyWith(color: K.blue)),
          ),
        ),
      ]),
    );
  }

  Widget _body(Period p) => switch (_tab) {
        1 => TransCalendarView(period: p, filter: _filter, onPick: (d) => _picked = d),
        2 => TransMonthlyView(year: p, filter: _filter, onOpen: _openPeriod),
        3 => TransTotalView(period: p, filter: _filter),
        4 => TransNoteView(period: p, filter: _filter),
        _ => TransDailyView(period: p, filter: _filter),
      };

  @override
  Widget build(BuildContext context) {
    final b = _book;
    if (b == null) return const Scaffold(backgroundColor: K.paper, body: Loading());
    final visible = _visible(b);
    final edit = b.canEdit;
    return Scaffold(
      backgroundColor: K.paper,
      floatingActionButton: edit
          ? FloatingActionButton(
              heroTag: 'monee-trans-add',
              tooltip: 'Add',
              onPressed: _add,
              backgroundColor: K.blue,
              foregroundColor: Colors.white,
              elevation: 2,
              highlightElevation: 4,
              shape: const CircleBorder(),
              child: const Icon(Icons.add_rounded, size: 28),
            )
          : null,
      body: SafeArea(
        bottom: false,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          PeriodBar(
            period: visible,
            onChanged: _onPeriod,
            trailing: [
              if (edit) RoundIcon(Icons.star_border_rounded, tooltip: 'Bookmarks', onTap: () => showBookmarks(context)),
              RoundIcon(Icons.search_rounded, tooltip: 'Search', onTap: _openSearch),
              _filterButton(),
            ],
          ),
          PillTabs(labels: _tabs, index: _tab, onChanged: _setTab),
          if (_filter.isNotEmpty) _filterBar(),
          SummaryStrip(income: _income, expense: _expense, total: _total, carry: _carry),
          Expanded(child: _body(visible)),
        ]),
      ),
    );
  }
}
