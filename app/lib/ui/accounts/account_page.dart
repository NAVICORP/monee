import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/book.dart';
import '../../core/format.dart';
import '../charts.dart';
import '../money.dart';
import '../theme.dart';
import '../txn_list.dart';
import '../widgets.dart';
import 'account_edit.dart';
import 'account_parts.dart';
import 'pay_card.dart';

/// One account: its balance, a card's payable and outstanding amounts with a
/// Pay button, the balance month by month, and a month of its transactions.
class AccountPage extends StatefulWidget {
  const AccountPage({super.key, required this.accountId});
  final String accountId;

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> with ReloadOnChange<AccountPage> {
  Period? _period;
  num balance = 0;
  Map<String, dynamic>? card;
  List<Map<String, dynamic>>? trend;
  List<Txn>? txns;
  String? error;
  int _seq = 0;
  int _txSeq = 0;

  Period get period => _period ??= Period.monthOf(Me.instance.book!, Me.instance.book!.today);
  Account? get account => Me.instance.account(widget.accountId);

  Future<dynamic> _txnCall(Period p) => Api.instance.rpc('txn_list', {
        ...p.args,
        'f': {
          'accounts': [widget.accountId],
        },
      });

  @override
  Future<void> reload() async {
    final b = Me.instance.book;
    if (b == null) return;
    final a = account;
    final isCard = a?.isCard ?? false;
    final p = period;
    final seq = ++_seq;
    final txSeq = ++_txSeq;
    try {
      final r = await Future.wait<dynamic>([
        Api.instance.rpc('balance_at', {'account': widget.accountId, 'until': isoDay(b.today)}),
        Api.instance.rpc('account_trend', {'account': widget.accountId, 'months': 12}),
        _txnCall(p),
        if (isCard) Api.instance.rpc('card_status', {'card': widget.accountId}),
      ]);
      if (!mounted || seq != _seq) return;
      setState(() {
        balance = toNum(r[0]);
        trend = jsonRows(r[1]);
        if (txSeq == _txSeq) txns = jsonRows(r[2]).map(Txn.new).toList();
        card = isCard ? jsonMap(r[3]) : null;
        error = null;
      });
    } on ApiError catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() => error = e.message);
    }
  }

  Future<void> _setPeriod(Period p) async {
    final seq = ++_txSeq;
    setState(() {
      _period = p;
      txns = null;
    });
    try {
      final r = await _txnCall(p);
      if (!mounted || seq != _txSeq) return;
      setState(() => txns = jsonRows(r).map(Txn.new).toList());
    } on ApiError catch (e) {
      if (!mounted || seq != _txSeq) return;
      setState(() => txns = const <Txn>[]);
      toast(context, e.message, bad: true);
    }
  }

  Future<void> _edit(Account a) async {
    await openAccountEditor(context, account: a);
  }

  Future<void> _delete(Account a) async {
    final deleted = await deleteAccountAsked(context, a);
    if (!deleted) return;
    if (mounted) Navigator.of(context).pop();
    await Me.instance.changed(lists: true);
  }

  Future<void> _pay(Account a) async {
    final c = card;
    if (c == null) return;
    final paid = await showPayCard(context, card: a, status: c);
    if (paid && mounted) toast(context, 'Card payment saved');
  }

  @override
  Widget build(BuildContext context) {
    final b = Me.instance.book;
    final a = account;
    if (b == null) return const SizedBox.shrink();
    if (a == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: EmptyState(icon: Icons.account_balance_wallet_outlined, text: 'This account is not in the book any more.')),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (b.canEdit && !a.deleted) ...[
            RoundIcon(Icons.edit_outlined, tooltip: 'Edit', size: 34, onTap: () => _edit(a)),
            RoundIcon(Icons.delete_outline_rounded, tooltip: 'Delete', size: 34, color: K.bad, onTap: () => _delete(a)),
          ],
          const SizedBox(width: Sp.sm),
        ],
      ),
      body: _body(b, a),
    );
  }

  Widget _body(Book b, Account a) {
    final t = trend;
    if (t == null) return error != null ? LoadFailed(message: error!, onRetry: reload) : const Loading();
    final list = txns;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: TxnDayList(
          txns: list ?? const <Txn>[],
          onRefresh: reload,
          header: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Sp.page, Sp.sm, Sp.page, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _hero(b, a, t),
                if (a.isCard && card != null) ...[const SizedBox(height: Sp.md), _cardBlock(b, a, card!)],
                if (t.isNotEmpty) ...[const SizedBox(height: Sp.md), _chart(a, t)],
              ]),
            ),
            const SizedBox(height: Sp.sm),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: PeriodBar(period: period, onChanged: _setPeriod)),
            if (list == null)
              const Padding(padding: EdgeInsets.all(Sp.xxl), child: Loading())
            else
              _FlowStrip(account: a, txns: list),
          ]),
          empty: list == null
              ? null
              : EmptyState(icon: Icons.receipt_long_outlined, text: 'Nothing in ${period.label(b)}.'),
        ),
      ),
    );
  }

  Widget _hero(Book b, Account a, List<Map<String, dynamic>> t) {
    final tags = [
      a.group?.label ?? '',
      if (a.hidden) 'Hidden',
      if (!a.inTotals) 'Not in totals',
      if (a.deleted) 'Deleted',
    ].where((s) => s.isNotEmpty).join(', ');
    final soft = T.small.copyWith(color: K.heroText);
    if (a.isDebit) {
      final last = t.isEmpty ? null : t.last;
      final linked = Me.instance.account(a.linkedAccountId);
      return HeroCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tags, maxLines: 1, overflow: TextOverflow.ellipsis, style: soft),
          const SizedBox(height: Sp.sm),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(money(toNum(last?['out']), a.currency), style: T.amount),
          ),
          const SizedBox(height: Sp.xs),
          Text('Spent this month', style: soft),
          if (linked != null) ...[
            const SizedBox(height: Sp.md),
            Text('Spends from ${linked.name}, which has ${money(toNum(last?['balance']), linked.currency)}.', style: soft),
          ],
        ]),
      );
    }
    final inMain = a.currency == b.currency ? null : Me.instance.toMain(balance, a.currency);
    return HeroCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tags, maxLines: 1, overflow: TextOverflow.ellipsis, style: soft),
        const SizedBox(height: Sp.sm),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: Text(money(balance, a.currency), style: T.amount),
        ),
        const SizedBox(height: Sp.xs),
        Text(a.isCard && balance < 0 ? 'Owed on the card' : 'Balance today', style: soft),
        if (inMain != null) Text('About ${money(inMain, b.currency)}', style: soft),
        if ((a.note ?? '').isNotEmpty) ...[
          const SizedBox(height: Sp.sm),
          Text(a.note!, maxLines: 3, overflow: TextOverflow.ellipsis, style: soft),
        ],
      ]),
    );
  }

  Widget _cardBlock(Book b, Account a, Map<String, dynamic> c) {
    final cur = a.currency;
    final payable = toNum(c['payable']);
    final due = parseDay(c['due']);
    final next = parseDay(c['next_settlement']);
    final overdue = c['overdue'] == true && payable > 0;
    final billing = Me.instance.account(c['billing_account_id'] as String?);
    final auto = c['auto_pay'] == true;
    Widget figure(String label, num v) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: T.tiny),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: OwedText(v, currency: cur, style: T.h3),
          ),
        ]);
    Widget line(String label, String value, {bool bad = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(children: [
            Text(label, style: T.small),
            const SizedBox(width: Sp.md),
            Expanded(
              child: Text(value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: T.label.copyWith(color: bad ? K.bad : K.ink2)),
            ),
          ]),
        );
    return KCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: figure('Payable', payable)),
          const SizedBox(width: Sp.md),
          Expanded(child: figure('Outstanding', toNum(c['outstanding']))),
        ]),
        const SizedBox(height: Sp.md),
        const Divider(height: 1),
        const SizedBox(height: Sp.xs),
        line('Due', due == null ? 'Not set' : (overdue ? 'Overdue, ${dateLabel(due)}' : dateLabel(due)), bad: overdue),
        line('Next settlement', next == null ? 'Not set' : dateLabel(next)),
        line('Paid from', billing?.name ?? 'Not set'),
        line('Automatic payment', auto ? 'On, on the payment day' : 'Off'),
        if (b.canEdit && !a.deleted) ...[
          const SizedBox(height: Sp.md),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: KButton(label: 'Pay card', icon: Icons.payments_outlined, kind: KButtonKind.blue, small: true, onPressed: () => _pay(a)),
          ),
        ],
      ]),
    );
  }

  Widget _chart(Account a, List<Map<String, dynamic>> t) {
    final debit = a.isDebit;
    final points = [
      for (final m in t) ChartPoint(shortMonth(m['month']), toNum(debit ? m['out'] : m['balance'])),
    ];
    return KCard(
      padding: const EdgeInsets.fromLTRB(Sp.sm, Sp.md, Sp.sm, Sp.sm),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text(debit ? 'Spent by month' : 'Balance by month', style: T.label),
        ),
        const SizedBox(height: Sp.xs),
        if (debit)
          BarChart(points: points, color: K.expense)
        else
          LineChart(points: points, format: (v) => chartMoney(v, a.currency)),
      ]),
    );
  }
}

/// The month's money in and out of the account, in its own currency.
class _FlowStrip extends StatelessWidget {
  const _FlowStrip({required this.account, required this.txns});
  final Account account;
  final List<Txn> txns;

  @override
  Widget build(BuildContext context) {
    final id = account.id;
    num inn = 0, out = 0;
    for (final t in txns) {
      final fromHere = t.accountId == id || Me.instance.account(t.accountId)?.linkedAccountId == id;
      final toHere = t.toAccountId == id;
      if (t.kind == 'income') {
        if (fromHere) inn += t.amount;
      } else if (t.kind == 'transfer') {
        if (toHere && !fromHere) inn += t.toAmount ?? t.amount;
        if (fromHere && !toHere) out += t.amount + t.fee;
      } else if (fromHere) {
        out += t.amount;
      }
    }
    Widget cell(String label, Widget amount) => Expanded(
          child: Column(children: [
            Text(label, style: T.tiny),
            const SizedBox(height: 2),
            FittedBox(fit: BoxFit.scaleDown, child: amount),
          ]),
        );
    final cur = account.currency;
    final style = T.bodyStrong.copyWith(fontSize: 15);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(color: K.surface, border: Border(top: BorderSide(color: K.border), bottom: BorderSide(color: K.border))),
      child: Row(children: [
        cell('In', MoneyText(inn, currency: cur, kind: 'income', symbol: false, style: style)),
        cell('Out', MoneyText(out, currency: cur, kind: 'expense', symbol: false, style: style)),
        cell('Net', BalanceText(inn - out, currency: cur, symbol: false, style: style)),
      ]),
    );
  }
}
