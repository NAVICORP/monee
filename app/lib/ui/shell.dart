import 'package:flutter/material.dart';

import '../core/book.dart';
import 'accounts/accounts_page.dart';
import 'glass.dart';
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
      // A glass side bar over soft light, and the page as a rounded panel
      // beside it, like a desktop app in the new design.
      return Scaffold(
        body: AmbientLight(
          child: SafeArea(
            child: Row(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 0, 12),
                child: _SideBar(items: _items, index: index, onTap: _select),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      borderRadius: BorderRadius.all(Radius.circular(26)),
                      boxShadow: [BoxShadow(color: Color(0x141E1240), blurRadius: 30, offset: Offset(0, 10))],
                    ),
                    child: ClipRRect(borderRadius: const BorderRadius.all(Radius.circular(26)), child: pop),
                  ),
                ),
              ),
            ]),
          ),
        ),
      );
    }
    // The footer floats over the pages as glass: they run underneath it.
    return Scaffold(
      extendBody: true,
      backgroundColor: K.paper,
      body: pop,
      bottomNavigationBar: KNavBar(items: _items, index: index, onTap: _select),
    );
  }
}

class _SideBar extends StatelessWidget {
  const _SideBar({required this.items, required this.index, required this.onTap});
  final List<KNavItem> items;
  final int index;
  final ValueChanged<int> onTap;

  /// The chosen page sits in a lilac drop of glass; the others are bare.
  Widget _chosen(bool on, Widget child) => on ? Glass(tone: GlassTone.lilac, shadow: false, child: child) : child;

  @override
  Widget build(BuildContext context) {
    final book = Me.instance.book;
    return SizedBox(
      width: 240,
      child: Glass(
        radius: 26,
        blur: 24,
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
                  child: _chosen(
                    i == index,
                    Material(
                      type: MaterialType.transparency,
                      child: InkWell(
                        customBorder: const StadiumBorder(),
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
