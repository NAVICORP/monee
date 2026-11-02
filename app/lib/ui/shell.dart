import 'package:flutter/material.dart';

import '../core/book.dart';
import 'accounts/accounts_page.dart';
import 'more/more_page.dart';
import 'stats/stats_page.dart';
import 'theme.dart';
import 'trans/trans_page.dart';
import 'widgets.dart';

/// The four tabs, like Kuree: Trans, Stats, Accounts, More in the footer on
/// phones, in a side bar on wide screens. Each tab keeps its own pile of
/// opened screens, so the footer stays below everything opened from it.
class MoneeShell extends StatefulWidget {
  const MoneeShell({super.key});

  @override
  State<MoneeShell> createState() => _MoneeShellState();
}

class _MoneeShellState extends State<MoneeShell> {
  static const _items = [
    KNavItem(Icons.receipt_long_outlined, Icons.receipt_long_rounded, 'Trans'),
    KNavItem(Icons.pie_chart_outline_rounded, Icons.pie_chart_rounded, 'Stats'),
    KNavItem(Icons.account_balance_wallet_outlined, Icons.account_balance_wallet_rounded, 'Accounts'),
    KNavItem(Icons.more_horiz_rounded, Icons.more_horiz_rounded, 'More'),
  ];
  final navs = List.generate(4, (i) => GlobalKey<NavigatorState>(debugLabel: 'tab$i'));
  final seen = <int>{0};
  int index = 0;

  void _select(int i) {
    if (i == index) {
      final nav = navs[i].currentState;
      if (nav != null && nav.canPop()) nav.popUntil((r) => r.isFirst);
      return;
    }
    setState(() {
      index = i;
      seen.add(i);
    });
  }

  Widget _root(int i) => switch (i) {
        0 => const TransPage(),
        1 => const StatsPage(),
        2 => const AccountsPage(),
        _ => const MorePage(),
      };

  Widget _stack(int i) => Navigator(
        key: navs[i],
        onGenerateRoute: (s) => MaterialPageRoute<void>(settings: s, builder: (_) => _root(i)),
      );

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 980;
    final stack = IndexedStack(
      index: index,
      sizing: StackFit.expand,
      children: [for (var i = 0; i < 4; i++) seen.contains(i) ? _stack(i) : const SizedBox.shrink()],
    );
    final pop = PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        final nav = navs[index].currentState;
        if (nav != null && nav.canPop()) {
          nav.maybePop();
        } else if (index != 0) {
          _select(0);
        }
      },
      child: stack,
    );
    if (wide) {
      return Scaffold(
        body: Row(children: [
          _SideBar(items: _items, index: index, onTap: _select),
          const VerticalDivider(width: 1),
          Expanded(child: pop),
        ]),
      );
    }
    return Scaffold(body: pop, bottomNavigationBar: KNavBar(items: _items, index: index, onTap: _select));
  }
}

class _SideBar extends StatelessWidget {
  const _SideBar({required this.items, required this.index, required this.onTap});
  final List<KNavItem> items;
  final int index;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final book = Me.instance.book;
    return Container(
      width: 240,
      color: K.surface,
      child: SafeArea(
        right: false,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 14, 6),
            child: Row(children: [
              const MoneeIcon(size: 32),
              const SizedBox(width: 10),
              Text('Monee', style: T.h2.copyWith(fontSize: 21)),
            ]),
          ),
          if (book != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 14, 14),
              child: Text(book.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: T.small.copyWith(color: K.blue, fontWeight: FontWeight.w800)),
            ),
          Expanded(
            child: ListView(padding: const EdgeInsets.symmetric(horizontal: 10), children: [
              for (var i = 0; i < items.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Material(
                    color: i == index ? K.brand100 : Colors.transparent,
                    borderRadius: BorderRadius.circular(999),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: () => onTap(i),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                        child: Row(children: [
                          Icon(i == index ? items[i].iconOn : items[i].icon, size: 21, color: i == index ? K.brand600 : K.muted),
                          const SizedBox(width: 12),
                          Expanded(child: Text(items[i].label, style: T.bodyStrong.copyWith(color: i == index ? K.ink : K.ink2))),
                        ]),
                      ),
                    ),
                  ),
                ),
            ]),
          ),
          if (book != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 14, 18),
              child: Row(children: [
                Avatar(book.memberName.isEmpty ? 'Me' : book.memberName, size: 30, color: K.deep, fg: K.heroText),
                const SizedBox(width: 10),
                Expanded(child: Text(book.memberName, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.label)),
              ]),
            ),
        ]),
      ),
    );
  }
}
