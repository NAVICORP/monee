import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api.dart';
import '../../core/book.dart';
import '../../core/format.dart';
import '../book_gate.dart' show pickCurrency;
import '../theme.dart';
import '../widgets.dart';
import 'account_parts.dart';

/// Adds an account (in [groupId] when given) or edits [account]. True when
/// something was saved.
Future<bool> openAccountEditor(BuildContext context, {Account? account, String? groupId}) async {
  final r = await Navigator.of(context).push<bool>(
    MaterialPageRoute<bool>(builder: (_) => _AccountEditor(account: account, groupId: groupId)),
  );
  return r ?? false;
}

/// Kinds of account where money is usually owed.
const _owedKinds = {'card', 'loan', 'overdraft'};

final _amountChars = FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'));

class _AccountEditor extends StatefulWidget {
  const _AccountEditor({this.account, this.groupId});
  final Account? account;
  final String? groupId;

  @override
  State<_AccountEditor> createState() => _AccountEditorState();
}

class _AccountEditorState extends State<_AccountEditor> {
  late final TextEditingController name;
  late final TextEditingController opening;
  late final TextEditingController note;
  String? groupId;
  String currency = 'INR';
  bool owe = false;
  bool hidden = false;
  bool inTotals = true;
  bool transferExpense = false;
  String? billingId;
  int settlementDay = 1;
  int paymentDay = 10;
  bool autoPay = false;
  String? linkedId;
  bool busy = false;
  String? error;

  bool get isNew => widget.account == null;
  Group? get group => Me.instance.group(groupId);
  String get kind => group?.kind ?? 'other';
  bool get isCard => kind == 'card';
  bool get isDebit => kind == 'debit_card';

  /// Transfer-Expense only for savings, investment, loan and insurance, by
  /// the same rule as Account.canTransferExpense.
  bool get canTransferExpense => Account(<String, dynamic>{}, group).canTransferExpense;

  @override
  void initState() {
    super.initState();
    final a = widget.account;
    final live = Me.instance.groups.where((g) => !g.deleted).toList();
    groupId = a?.groupId ?? widget.groupId ?? live.firstOrNull?.id;
    name = TextEditingController(text: a?.name ?? '');
    final o = a?.opening ?? 0;
    owe = a == null ? _owedKinds.contains(kind) : o < 0;
    opening = TextEditingController(text: o == 0 ? '' : rateText(o.abs()));
    note = TextEditingController(text: a?.note ?? '');
    currency = a?.currency ?? Me.instance.book?.currency ?? 'INR';
    hidden = a?.hidden ?? false;
    inTotals = a?.inTotals ?? true;
    transferExpense = a?.transferExpense ?? false;
    billingId = a?.billingAccountId;
    settlementDay = a?.settlementDay ?? 1;
    paymentDay = a?.paymentDay ?? 10;
    autoPay = a?.autoPay ?? false;
    linkedId = a?.linkedAccountId;
  }

  @override
  void dispose() {
    name.dispose();
    opening.dispose();
    note.dispose();
    super.dispose();
  }

  /// Accounts a card can be paid from, or a debit card can spend from: live
  /// cash, bank and wallet style accounts.
  List<Account> get _moneyAccounts =>
      Me.instance.liveAccounts.where((a) => kPayingKinds.contains(a.kind) && a.id != widget.account?.id).toList();

  void _setGroup(String id) {
    setState(() {
      groupId = id;
      if (isNew && opening.text.trim().isEmpty) owe = _owedKinds.contains(kind);
      error = null;
    });
  }

  Future<void> _pickGroup() async {
    final groups = Me.instance.groups.where((g) => !g.deleted).toList();
    final p = await showPicker<String>(context, title: 'Group', selected: groupId, options: [
      for (final g in groups) PickOption(g.id, g.label, sub: kGroupKinds[g.kind]),
      const PickOption('', 'New group', icon: Icons.add_rounded),
    ]);
    if (p == null || !mounted) return;
    if (p.value.isNotEmpty) {
      _setGroup(p.value);
      return;
    }
    final id = await showKSheet<String>(context, title: 'New group', builder: (_) => const _NewGroupSheet());
    if (id == null || !mounted) return;
    _setGroup(id);
  }

  Future<void> _pickCurrency() async {
    final c = await pickCurrency(context, selected: currency, title: 'Currency');
    if (c != null && mounted) setState(() => currency = c);
  }

  Future<void> _pickBilling() async {
    final p = await showPicker<String>(context, title: 'Billing account', selected: billingId ?? '', options: [
      const PickOption('', 'None', sub: 'Pick when you pay'),
      for (final a in _moneyAccounts) PickOption(a.id, a.name, sub: a.group?.name, trailing: a.currency),
    ]);
    if (p == null || !mounted) return;
    setState(() {
      billingId = p.value.isEmpty ? null : p.value;
      if (billingId == null) autoPay = false;
    });
  }

  Future<void> _pickLinked() async {
    final p = await showPicker<String>(context, title: 'Linked account', selected: linkedId, options: [
      for (final a in _moneyAccounts) PickOption(a.id, a.name, sub: a.group?.name, trailing: a.currency),
    ]);
    if (p == null || !mounted) return;
    setState(() => linkedId = p.value);
  }

  Future<void> _pickSettlement() async {
    final d = await _pickDay(context, title: 'Settlement day', selected: settlementDay);
    if (d != null && mounted) setState(() => settlementDay = d);
  }

  Future<void> _pickPayment() async {
    final d = await _pickDay(context, title: 'Payment day', selected: paymentDay);
    if (d != null && mounted) setState(() => paymentDay = d);
  }

  void _fail(String m) => setState(() => error = m);

  Future<void> _save() async {
    final g = group;
    final n = name.text.trim();
    if (g == null) {
      _fail('Pick a group.');
      return;
    }
    if (n.isEmpty) {
      _fail('Give the account a name.');
      return;
    }
    if (isDebit && linkedId == null) {
      _fail('Link the debit card to the account it spends from.');
      return;
    }
    if (isCard && autoPay && billingId == null) {
      _fail('Automatic payment needs the account the card is paid from.');
      return;
    }
    final raw = opening.text.replaceAll(',', '').trim();
    final v = raw.isEmpty ? 0 : num.tryParse(raw);
    if (v == null) {
      _fail('The opening balance should be a number.');
      return;
    }
    final linked = Me.instance.account(linkedId);
    final noteText = note.text.trim();
    final row = <String, dynamic>{
      'group_id': g.id,
      'name': n,
      'currency': isDebit ? (linked?.currency ?? currency) : currency,
      'opening_balance': isDebit ? 0 : (owe ? -v.abs() : v.abs()),
      'note': noteText.isEmpty ? null : noteText,
      'hidden': hidden,
      'in_totals': inTotals,
      'transfer_expense': canTransferExpense && transferExpense,
      'billing_account_id': isCard ? billingId : null,
      'settlement_day': isCard ? settlementDay : null,
      'payment_day': isCard ? paymentDay : null,
      'auto_pay': isCard && autoPay,
      'linked_account_id': isDebit ? linkedId : null,
    };
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final a = widget.account;
      if (a == null) {
        final sort = Me.instance.accounts.where((x) => x.groupId == g.id).fold<int>(-1, (m, x) => x.sort > m ? x.sort : m) + 1;
        await Api.instance.insert('accounts', {...row, 'sort': sort});
      } else {
        await Api.instance.update('accounts', row, where: {'id': 'eq.${a.id}'});
      }
      await Me.instance.changed(lists: true);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        busy = false;
        error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = group;
    final kindName = kGroupKinds[kind] ?? kind;
    final groupText = g == null
        ? 'Pick a group'
        : (g.name.trim().toLowerCase() == kindName.toLowerCase() ? g.label : '${g.label}, ${kindName.toLowerCase()}');
    final cur = currencyOf(currency);
    final billing = Me.instance.account(billingId);
    final linked = Me.instance.account(linkedId);
    final oweSub = switch (kind) {
      'card' => 'What you owe on the card now. It is kept as a negative balance.',
      'loan' => 'What is left to pay on a loan you took. It is kept as a negative balance.',
      'overdraft' => 'What you owe on the overdraft. It is kept as a negative balance.',
      _ => 'Turn on when the account starts below zero.',
    };
    return Scaffold(
      appBar: AppBar(title: Text(isNew ? 'New account' : 'Edit account')),
      body: PageBody(maxWidth: 560, bottom: 40, children: [
        KChoice(
          label: 'Group',
          value: groupText,
          icon: Icons.folder_outlined,
          onTap: _pickGroup,
        ),
        const SizedBox(height: Sp.md),
        KField(label: 'Name', controller: name, hint: isCard ? 'For example, Visa Gold' : 'For example, Salary account', caps: TextCapitalization.words),
        const SizedBox(height: Sp.md),
        if (isDebit) ...[
          KChoice(label: 'Linked account', value: linked?.name ?? 'Pick an account', icon: Icons.link_rounded, onTap: _pickLinked),
          const Padding(
            padding: EdgeInsetsDirectional.fromSTEB(4, 6, 4, 0),
            child: Text('Spending on the card comes off this account straight away, in its currency.', style: T.small),
          ),
          const SizedBox(height: Sp.md),
        ] else ...[
          KChoice(label: 'Currency', value: '${cur.code}, ${cur.name}', icon: Icons.payments_outlined, onTap: _pickCurrency),
          const SizedBox(height: Sp.md),
          KField(
            label: 'Opening balance',
            controller: opening,
            hint: '0',
            keyboard: const TextInputType.numberWithOptions(decimal: true),
            formatters: [_amountChars],
            prefix: owe ? '-' : null,
            suffix: cur.code,
          ),
          KSwitchRow(title: 'I owe this', sub: oweSub, value: owe, onChanged: (v) => setState(() => owe = v)),
          const SizedBox(height: Sp.sm),
        ],
        if (isCard) ...[
          const SectionTitle('Card', top: Sp.sm),
          KChoice(
            label: 'Billing account',
            value: billing == null ? 'Not set' : billing.name,
            icon: Icons.account_balance_outlined,
            onTap: _pickBilling,
          ),
          const SizedBox(height: Sp.md),
          Row(children: [
            Expanded(child: KChoice(label: 'Settlement day', value: 'Day $settlementDay', onTap: _pickSettlement)),
            const SizedBox(width: Sp.sm),
            Expanded(child: KChoice(label: 'Payment day', value: 'Day $paymentDay', onTap: _pickPayment)),
          ]),
          const Padding(
            padding: EdgeInsetsDirectional.fromSTEB(4, 6, 4, 0),
            child: Text(
              'Spending up to the settlement day is payable on the payment day. Spending after it is outstanding until the next settlement.',
              style: T.small,
            ),
          ),
          const SizedBox(height: Sp.sm),
          KSwitchRow(
            title: 'Automatic payment',
            sub: billing == null ? 'Pick the billing account first.' : 'Pays the payable amount from ${billing.name} on the payment day.',
            value: autoPay,
            onChanged: billing == null ? null : (v) => setState(() => autoPay = v),
          ),
          const SizedBox(height: Sp.sm),
        ],
        KField(label: 'Note', controller: note, hint: 'Optional', maxLines: 3),
        const SizedBox(height: Sp.md),
        KCard(
          padding: const EdgeInsetsDirectional.fromSTEB(14, 4, 8, 4),
          child: Column(children: [
            KSwitchRow(
              title: 'Include in totals',
              sub: 'Counted in Assets, Liabilities and Total.',
              value: inTotals,
              onChanged: (v) => setState(() => inTotals = v),
            ),
            KSwitchRow(
              title: 'Hidden',
              sub: 'Shown only when hidden accounts are shown.',
              value: hidden,
              onChanged: (v) => setState(() => hidden = v),
            ),
            if (canTransferExpense)
              KSwitchRow(
                title: 'Transfer-Expense',
                sub: 'Money moved into this account counts as an expense.',
                value: transferExpense,
                onChanged: (v) => setState(() => transferExpense = v),
              ),
          ]),
        ),
        const SizedBox(height: Sp.lg),
        if (error != null) ...[Notice(error!), const SizedBox(height: Sp.md)],
        KButton(label: isNew ? 'Add account' : 'Save', icon: Icons.check_rounded, expand: true, busy: busy, onPressed: _save),
      ]),
    );
  }
}

/// A day of the month, 1 to 31, from a grid.
Future<int?> _pickDay(BuildContext context, {required String title, required int selected}) {
  return showKSheet<int>(
    context,
    title: title,
    builder: (ctx) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      GridView.count(
        crossAxisCount: 7,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        childAspectRatio: 1.1,
        children: [
          for (var d = 1; d <= 31; d++)
            Padding(
              padding: const EdgeInsets.all(2),
              child: Material(
                color: d == selected ? K.blue : Colors.transparent,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => Navigator.of(ctx).pop(d),
                  child: Center(
                    child: Text('$d', style: T.bodyStrong.copyWith(color: d == selected ? Colors.white : K.ink).merge(T.tabular)),
                  ),
                ),
              ),
            ),
        ],
      ),
      const SizedBox(height: Sp.sm),
      const Text('In shorter months, days after the last day fall on the last day.', textAlign: TextAlign.center, style: T.small),
    ]),
  );
}

/// A new account group: its name, an emoji and what kind of accounts it holds.
class _NewGroupSheet extends StatefulWidget {
  const _NewGroupSheet();

  @override
  State<_NewGroupSheet> createState() => _NewGroupSheetState();
}

class _NewGroupSheetState extends State<_NewGroupSheet> {
  final name = TextEditingController();
  final emoji = TextEditingController();
  String kind = 'other';
  bool busy = false;
  String? error;

  @override
  void dispose() {
    name.dispose();
    emoji.dispose();
    super.dispose();
  }

  Future<void> _pickKind() async {
    final p = await showPicker<String>(context, title: 'Kind', selected: kind, options: [
      for (final e in kGroupKinds.entries) PickOption(e.key, e.value),
    ]);
    if (p != null && mounted) setState(() => kind = p.value);
  }

  Future<void> _add() async {
    final n = name.text.trim();
    if (n.isEmpty) {
      setState(() => error = 'Give the group a name.');
      return;
    }
    final e = emoji.text.trim();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final sort = Me.instance.groups.fold<int>(-1, (m, g) => g.sort > m ? g.sort : m) + 1;
      final row = await Api.instance.insert('account_groups', {'name': n, 'emoji': e.isEmpty ? null : e, 'kind': kind, 'sort': sort});
      await Me.instance.changed(lists: true);
      if (!mounted) return;
      Navigator.of(context).pop(row['id'] as String?);
    } on ApiError catch (x) {
      if (!mounted) return;
      setState(() {
        busy = false;
        error = x.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      KField(label: 'Name', controller: name, hint: 'For example, Wallets', caps: TextCapitalization.words, autofocus: true),
      const SizedBox(height: Sp.md),
      KField(label: 'Emoji', controller: emoji, hint: 'Optional', caps: TextCapitalization.none),
      const SizedBox(height: Sp.md),
      KChoice(label: 'Kind', value: kGroupKinds[kind] ?? kind, icon: Icons.category_outlined, onTap: _pickKind),
      const Padding(
        padding: EdgeInsetsDirectional.fromSTEB(4, 6, 4, 0),
        child: Text('The kind decides how its accounts work: cards get billing dates, debit cards spend from a linked account.', style: T.small),
      ),
      const SizedBox(height: Sp.lg),
      if (error != null) ...[Notice(error!), const SizedBox(height: Sp.md)],
      KButton(label: 'Add group', icon: Icons.add_rounded, expand: true, busy: busy, onPressed: _add),
    ]);
  }
}
