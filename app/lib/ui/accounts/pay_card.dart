import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api.dart';
import '../../core/book.dart';
import '../../core/format.dart';
import '../theme.dart';
import '../widgets.dart';
import 'account_parts.dart';

/// Pays a card off: a transfer from its billing account (or another one).
/// [status] is the card's card_status(). True when a payment was saved.
Future<bool> showPayCard(BuildContext context, {required Account card, required Map<String, dynamic> status}) async {
  final r = await showKSheet<bool>(context, title: 'Pay ${card.name}', builder: (_) => _PayCardSheet(card: card, status: status));
  return r ?? false;
}

class _PayCardSheet extends StatefulWidget {
  const _PayCardSheet({required this.card, required this.status});
  final Account card;
  final Map<String, dynamic> status;

  @override
  State<_PayCardSheet> createState() => _PayCardSheetState();
}

class _PayCardSheetState extends State<_PayCardSheet> {
  late final TextEditingController amount;
  String? fromId;
  late DateTime day;
  bool busy = false;
  String? error;

  num get payable => toNum(widget.status['payable']);
  num get outstanding => toNum(widget.status['outstanding']);

  @override
  void initState() {
    super.initState();
    final p = payable;
    amount = TextEditingController(text: p > 0 ? currencyOf(widget.card.currency).number(p).replaceAll(',', '') : '');
    final billing = widget.status['billing_account_id'] as String? ?? widget.card.billingAccountId;
    fromId = Me.instance.account(billing) == null ? null : billing;
    day = Me.instance.book?.today ?? dayOnly(DateTime.now());
  }

  @override
  void dispose() {
    amount.dispose();
    super.dispose();
  }

  List<Account> get _sources => Me.instance.liveAccounts.where((a) => kPayingKinds.contains(a.kind) && a.id != widget.card.id).toList();

  Future<void> _pickFrom() async {
    final p = await showPicker<String>(context, title: 'Pay from', selected: fromId, options: [
      for (final a in _sources) PickOption(a.id, a.name, sub: a.group?.name, trailing: a.currency),
    ]);
    if (p != null && mounted) setState(() => fromId = p.value);
  }

  Future<void> _pickDay() async {
    final d = await pickDate(context, initial: day, title: 'Payment date');
    if (d != null && mounted) setState(() => day = d);
  }

  Future<void> _pay() async {
    final v = num.tryParse(amount.text.replaceAll(',', '').trim());
    if (v == null || v <= 0) {
      setState(() => error = 'Enter the amount to pay.');
      return;
    }
    final from = fromId;
    if (from == null) {
      setState(() => error = 'Pick the account to pay from.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    final now = DateTime.now();
    try {
      await Api.instance.rpc('pay_card', {
        'card': widget.card.id,
        'amount': v,
        'from_account': from,
        'at': isoStamp(DateTime(day.year, day.month, day.day, now.hour, now.minute)),
      });
      await Me.instance.changed();
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
    final cardCur = widget.card.currency;
    final from = Me.instance.account(fromId);
    final payCur = from?.currency ?? cardCur;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Payable ${money(payable, cardCur)}, outstanding ${money(outstanding, cardCur)}.', style: T.small),
      const SizedBox(height: Sp.md),
      KField(
        label: 'Amount',
        controller: amount,
        hint: '0',
        keyboard: const TextInputType.numberWithOptions(decimal: true),
        formatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
        suffix: payCur,
      ),
      if (payCur != cardCur) ...[
        const SizedBox(height: Sp.sm),
        Notice('The amount is in $payCur, the currency of ${from?.name ?? 'that account'}. The card is in $cardCur.', bad: false),
      ],
      const SizedBox(height: Sp.md),
      KChoice(label: 'From', value: from?.name ?? 'Pick an account', icon: Icons.account_balance_outlined, onTap: _pickFrom),
      const SizedBox(height: Sp.md),
      KChoice(label: 'Date', value: dateLabel(day), icon: Icons.event_outlined, onTap: _pickDay),
      const SizedBox(height: Sp.lg),
      if (error != null) ...[Notice(error!), const SizedBox(height: Sp.md)],
      KButton(label: 'Pay', icon: Icons.check_rounded, expand: true, busy: busy, onPressed: _pay),
    ]);
  }
}
