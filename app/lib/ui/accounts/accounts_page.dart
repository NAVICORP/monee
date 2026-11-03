import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/book.dart';
import '../../core/format.dart';
import '../money.dart';
import '../more/account_settings.dart' show AccountSettingsPage;
import '../more/currencies.dart' show CurrenciesPage;
import '../theme.dart';
import '../widgets.dart';
import 'account_edit.dart';
import 'account_page.dart';
import 'account_parts.dart';
import 'asset_trend.dart';

/// The Accounts tab: Assets, Liabilities and Total, then every group with
/// its accounts and their balances. Cards show what is payable and what is
/// outstanding.
class AccountsPage extends StatefulWidget {
  const AccountsPage({super.key});

  @override
  State<AccountsPage> createState() => _AccountsPageState();
}

class _AccountsPageState extends State<AccountsPage> with ReloadOnChange<AccountsPage> {
  /// Kept while the app runs, so the choice survives switching tabs.
  static bool _showHidden = false;

  Map<String, dynamic>? data;
  String? error;
  int _seq = 0;

  /// Collapsed or open, as just tapped (before, or instead of, the server).
  final Map<String, bool> _collapsed = {};

  @override
  Future<void> reload() async {
    if (Me.instance.book == null) return;
    final seq = ++_seq;
    try {
      final r = await Api.instance.rpc('accounts_overview', {'include_deleted': false});
      if (!mounted || seq != _seq) return;
      setState(() {
        data = jsonMap(r) ?? <String, dynamic>{};
        error = null;
      });
    } on ApiError catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() => error = e.message);
    }
  }

  bool _isCollapsed(Map<String, dynamic> g) => _collapsed[g['id'] as String] ?? (g['collapsed'] == true);

  Future<void> _toggle(Map<String, dynamic> g) async {
    final id = g['id'] as String;
    final now = !_isCollapsed(g);
    setState(() => _collapsed[id] = now);
    if (!(Me.instance.book?.canEdit ?? false)) return;
    try {
      await Api.instance.update('account_groups', {'collapsed': now}, where: {'id': 'eq.$id'});
      await Me.instance.changed(lists: true);
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() => _collapsed.remove(id));
      toast(context, e.message, bad: true);
    }
  }

  void _push(Widget page) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

  void _openAccount(String id) => _push(AccountPage(accountId: id));

  /// A long press on an account: open, edit or delete it.
  Future<void> _accountMenu(String id) async {
    final a = Me.instance.account(id);
    if (a == null) return;
    final canEdit = Me.instance.book?.canEdit ?? false;
    final p = await showPicker<String>(context, title: a.name, options: [
      const PickOption('open', 'Open', icon: Icons.open_in_new_rounded),
      if (canEdit) ...[
        const PickOption('edit', 'Edit', icon: Icons.edit_outlined),
        const PickOption('delete', 'Delete', icon: Icons.delete_outline_rounded),
      ],
    ]);
    if (p == null || !mounted) return;
    switch (p.value) {
      case 'open':
        _openAccount(id);
      case 'edit':
        await openAccountEditor(context, account: a);
      case 'delete':
        if (await deleteAccountAsked(context, a)) await Me.instance.changed(lists: true);
    }
  }

  void _openCurrencies() => _push(const CurrenciesPage());

  Future<void> _add() async {
    await openAccountEditor(context);
  }

  Future<void> _menu() async {
    final p = await showPicker<String>(context, title: 'Accounts', options: [
      PickOption('hidden', 'Show hidden accounts',
          icon: _showHidden ? Icons.visibility_rounded : Icons.visibility_off_outlined, trailing: _showHidden ? 'On' : 'Off'),
      const PickOption('settings', 'Account settings', icon: Icons.tune_rounded),
      const PickOption('currencies', 'Currencies', icon: Icons.currency_exchange),
    ]);
    if (p == null || !mounted) return;
    switch (p.value) {
      case 'hidden':
        setState(() => _showHidden = !_showHidden);
      case 'settings':
        _push(const AccountSettingsPage());
      case 'currencies':
        _openCurrencies();
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = Me.instance.book;
    if (b == null) return const SizedBox.shrink();
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(Sp.page + 4, Sp.xs, Sp.xs, Sp.xs),
            child: Row(children: [
              Expanded(child: Text('Accounts', maxLines: 1, overflow: TextOverflow.ellipsis, style: T.h1)),
              RoundIcon(Icons.show_chart_rounded, tooltip: 'Asset trend', onTap: () => _push(const AssetTrendPage())),
              if (b.canEdit) RoundIcon(Icons.add_rounded, tooltip: 'Add account', onTap: _add),
              RoundIcon(Icons.more_vert_rounded, tooltip: 'More', onTap: _menu),
            ]),
          ),
          Expanded(child: _body(b)),
        ]),
      ),
    );
  }

  Widget _body(Book b) {
    final d = data;
    if (d == null) return error != null ? LoadFailed(message: error!, onRetry: reload) : const Loading();
    final main = d['currency'] as String? ?? b.currency;
    final missing = ((d['missing_rates'] as List?) ?? const []).map((e) => '$e').toList();
    final shown = <(Map<String, dynamic>, List<Map<String, dynamic>>)>[];
    for (final g in jsonRows(d['groups'])) {
      if (g['hidden'] == true && !_showHidden) continue;
      final accounts = jsonRows(g['accounts']).where((a) => _showHidden || a['hidden'] != true).toList();
      if (accounts.isEmpty) continue;
      shown.add((g, accounts));
    }
    return Column(children: [
      _TotalsStrip(assets: toNum(d['assets']), liabilities: toNum(d['liabilities']), total: toNum(d['total']), currency: main),
      Expanded(
        child: PageBody(onRefresh: reload, children: [
          const SizedBox(height: Sp.sm),
          if (missing.isNotEmpty) ...[
            Semantics(
              button: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _openCurrencies,
                child: Notice('Add exchange rates for ${andList(missing)} to count them in the totals.', bad: false),
              ),
            ),
            const SizedBox(height: Sp.md),
          ],
          if (shown.isEmpty)
            EmptyState(
              icon: Icons.account_balance_wallet_outlined,
              text: 'No accounts yet.',
              action: b.canEdit ? KButton(label: 'Add account', icon: Icons.add_rounded, kind: KButtonKind.secondary, small: true, onPressed: _add) : null,
            ),
          for (final (g, accounts) in shown) ...[
            _GroupCard(
              group: g,
              accounts: accounts,
              mainCurrency: main,
              collapsed: _isCollapsed(g),
              onToggle: () => _toggle(g),
              onOpen: _openAccount,
              onMenu: _accountMenu,
            ),
            const SizedBox(height: Sp.md),
          ],
        ]),
      ),
    ]);
  }
}

/// Assets in green, Liabilities in red, and the Total, in the main currency.
class _TotalsStrip extends StatelessWidget {
  const _TotalsStrip({required this.assets, required this.liabilities, required this.total, required this.currency});
  final num assets;
  final num liabilities;
  final num total;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final style = T.bodyStrong.copyWith(fontSize: 15);
    Widget cell(String label, Widget amount) => Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(children: [
              Text(label, style: T.tiny),
              const SizedBox(height: 2),
              FittedBox(fit: BoxFit.scaleDown, child: amount),
            ]),
          ),
        );
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(color: K.surface, border: Border(top: BorderSide(color: K.border), bottom: BorderSide(color: K.border))),
      child: Row(children: [
        cell('Assets', MoneyText(assets, currency: currency, kind: 'income', symbol: false, style: style)),
        cell('Liabilities', MoneyText(liabilities, currency: currency, kind: 'expense', symbol: false, style: style)),
        cell('Total', MoneyText(total, currency: currency, symbol: false, style: style)),
      ]),
    );
  }
}

/// A group: its header (tap to fold it away) and its accounts.
class _GroupCard extends StatelessWidget {
  const _GroupCard({
    required this.group,
    required this.accounts,
    required this.mainCurrency,
    required this.collapsed,
    required this.onToggle,
    required this.onOpen,
    required this.onMenu,
  });
  final Map<String, dynamic> group;
  final List<Map<String, dynamic>> accounts;
  final String mainCurrency;
  final bool collapsed;
  final VoidCallback onToggle;
  final ValueChanged<String> onOpen;
  final ValueChanged<String> onMenu;

  @override
  Widget build(BuildContext context) {
    final isCard = group['kind'] == 'card';
    final emoji = (group['emoji'] as String? ?? '').trim();
    final name = group['name'] as String? ?? '';
    final title = emoji.isEmpty ? name : '$emoji $name';
    return Container(
      decoration: BoxDecoration(color: K.surface, borderRadius: BorderRadius.circular(K.r), border: Border.all(color: K.border)),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: LayoutBuilder(builder: (context, box) {
          // The card columns: wide enough for "Outstanding" and an amount.
          final col = isCard ? (box.maxWidth * 0.27).clamp(84.0, 120.0).toDouble() : 0.0;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            InkWell(
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(10, 11, 14, 11),
                child: isCard ? _cardHeader(title, col) : _header(title),
              ),
            ),
            if (!collapsed)
              for (final a in accounts) ...[
                const Divider(height: 1),
                if (isCard)
                  _CardRow(
                    account: a,
                    col: col,
                    onTap: () => onOpen(a['id'] as String),
                    onLongPress: () => onMenu(a['id'] as String),
                  )
                else
                  _AccountRow(
                    account: a,
                    mainCurrency: mainCurrency,
                    maxTrailing: box.maxWidth * 0.55,
                    onTap: () => onOpen(a['id'] as String),
                    onLongPress: () => onMenu(a['id'] as String),
                  ),
              ],
          ]);
        }),
      ),
    );
  }

  Widget _titleRow(String title) => Row(children: [
        Icon(collapsed ? Icons.chevron_right_rounded : Icons.expand_more_rounded, size: 20, color: K.muted),
        const SizedBox(width: 4),
        Flexible(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.label.copyWith(color: K.ink2, fontSize: 13.5))),
        if (group['hidden'] == true) ...[const SizedBox(width: 6), const Pill.grey('Hidden')],
      ]);

  Widget _header(String title) {
    final total = toNum(group['total_main']);
    return Row(children: [
      Expanded(child: _titleRow(title)),
      const SizedBox(width: Sp.sm),
      BalanceText(total, currency: mainCurrency, style: T.label.copyWith(fontSize: 13.5)),
    ]);
  }

  Widget _cardHeader(String title, double col) {
    Widget column(String label, num v) => SizedBox(
          width: col,
          child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.tiny),
            const SizedBox(height: 2),
            FitEnd(child: OwedText(v, currency: mainCurrency, style: T.label.copyWith(fontSize: 13.5))),
          ]),
        );
    return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      Expanded(child: _titleRow(title)),
      const SizedBox(width: Sp.sm),
      column('Payable', toNum(group['payable_main'])),
      const SizedBox(width: Sp.sm),
      column('Outstanding', toNum(group['outstanding_main'])),
    ]);
  }
}

/// An account: its name and its balance in its own currency. Debit cards
/// show what was spent on them this month.
class _AccountRow extends StatelessWidget {
  const _AccountRow({required this.account, required this.mainCurrency, required this.maxTrailing, required this.onTap, this.onLongPress});
  final Map<String, dynamic> account;
  final String mainCurrency;

  /// The most the amount on the right may take, so long names keep the rest.
  final double maxTrailing;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final a = account;
    final cur = a['currency'] as String? ?? mainCurrency;
    final debit = jsonMap(a['debit']);
    final notes = [
      if (a['hidden'] == true) 'Hidden',
      if (a['in_totals'] == false) 'Not in totals',
    ];
    final Widget trailing;
    final String sub;
    if (debit != null) {
      final linked = Me.instance.account(debit['linked_account_id'] as String?);
      sub = [if (linked != null) 'From ${linked.name}', ...notes].join(', ');
      trailing = Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text('Spent this month', style: T.tiny),
        FitEnd(child: MoneyText(toNum(debit['spent_this_month']), currency: cur, kind: 'expense', style: T.bodyStrong)),
      ]);
    } else {
      final balance = toNum(a['balance']);
      final inMain = a['balance_main'];
      sub = notes.join(', ');
      trailing = Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        FitEnd(child: BalanceText(balance, currency: cur)),
        if (cur != mainCurrency && inMain != null && balance != 0) FitEnd(child: Text(money(toNum(inMain), mainCurrency), style: T.tiny)),
      ]);
    }
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(14, 11, 14, 11),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(a['name'] as String? ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: T.body),
              if (sub.isNotEmpty) Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.tiny.copyWith(fontWeight: FontWeight.w500)),
            ]),
          ),
          const SizedBox(width: Sp.md),
          ConstrainedBox(constraints: BoxConstraints(maxWidth: maxTrailing), child: trailing),
        ]),
      ),
    );
  }
}

/// A card: its name and due date, then Payable and Outstanding in its own
/// currency, under the group's column titles.
class _CardRow extends StatelessWidget {
  const _CardRow({required this.account, required this.col, required this.onTap, this.onLongPress});
  final Map<String, dynamic> account;
  final double col;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final a = account;
    final cur = a['currency'] as String? ?? Me.instance.book?.currency ?? 'INR';
    final c = jsonMap(a['card']) ?? <String, dynamic>{};
    final payable = toNum(c['payable']);
    final outstanding = toNum(c['outstanding']);
    final due = parseDay(c['due']);
    final overdue = c['overdue'] == true;
    final notes = [
      if (payable > 0 && due != null) 'Due ${shortDate(due)}',
      if (a['hidden'] == true) 'Hidden',
      if (a['in_totals'] == false) 'Not in totals',
    ];
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(14, 11, 14, 11),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(a['name'] as String? ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: T.body),
              if (notes.isNotEmpty)
                Text(notes.join(', '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: T.tiny.copyWith(fontWeight: FontWeight.w500, color: overdue && payable > 0 ? K.bad : K.muted)),
            ]),
          ),
          const SizedBox(width: Sp.sm),
          SizedBox(width: col, child: Align(alignment: AlignmentDirectional.centerEnd, child: FitEnd(child: OwedText(payable, currency: cur)))),
          const SizedBox(width: Sp.sm),
          SizedBox(width: col, child: Align(alignment: AlignmentDirectional.centerEnd, child: FitEnd(child: OwedText(outstanding, currency: cur)))),
        ]),
      ),
    );
  }
}
