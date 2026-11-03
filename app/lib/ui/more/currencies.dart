import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api.dart';
import '../../core/book.dart';
import '../../core/format.dart';
import '../book_gate.dart';
import '../theme.dart';
import '../widgets.dart';
import 'more_common.dart';

/// More > Currencies: the main currency, and the other currencies accounts
/// are kept in, each with its rate (how much of the main currency one unit
/// is worth).
class CurrenciesPage extends StatefulWidget {
  const CurrenciesPage({super.key});

  @override
  State<CurrenciesPage> createState() => _CurrenciesPageState();
}

class _CurrenciesPageState extends State<CurrenciesPage> {
  Future<void> _add([String? code]) async {
    final b = Me.instance.book;
    if (b == null) return;
    final c = code ?? await pickCurrency(context, title: 'Add a currency', except: {b.currency, ...Me.instance.rates.keys});
    if (c == null || !mounted) return;
    final rate = await askRate(context, from: c, to: b.currency, title: 'Rate for $c');
    if (rate == null || !mounted) return;
    await attempt(context, () async {
      await Api.instance.insert('currency_rates', {'currency': c, 'rate': rate});
      await Me.instance.changed(lists: true);
    }, done: '$c added');
  }

  Future<void> _edit(String c) async {
    final b = Me.instance.book;
    if (b == null) return;
    final rate = await askRate(context, from: c, to: b.currency, current: Me.instance.rates[c], title: 'Rate for $c');
    if (rate == null || !mounted) return;
    await attempt(context, () async {
      await Api.instance.update('currency_rates', {'rate': rate}, where: {'currency': 'eq.$c'});
      await Me.instance.changed(lists: true);
    }, done: 'Rate saved');
  }

  Future<void> _delete(String c) async {
    final users = Me.instance.accounts.where((a) => !a.deleted && a.currency == c).toList();
    final text = users.isEmpty
        ? 'Accounts can use $c again once you add it back.'
        : '${users.first.name}${users.length > 1 ? ' and ${users.length - 1} more' : ''} ${users.length == 1 ? 'uses' : 'use'} $c. '
            'Without a rate, ${users.length == 1 ? 'its balance is' : 'their balances are'} left out of totals and new entries on '
            '${users.length == 1 ? 'it' : 'them'} cannot be saved.';
    final ok = await confirm(context, title: 'Delete $c?', text: text, yes: 'Delete', danger: true);
    if (!ok || !mounted) return;
    await attempt(context, () async {
      // currency_rates has no id column: the delete answers with the
      // currency instead (a select in `where` replaces the default one).
      await Api.instance.delete('currency_rates', where: {'currency': 'eq.$c', 'select': 'currency'});
      await Me.instance.changed(lists: true);
    }, done: '$c deleted');
  }

  Future<void> _actions(String c) async {
    final a = await pickAction(context, title: c, actions: const [
      PickOption('rate', 'Change the rate', icon: Icons.currency_exchange_rounded),
      PickOption('delete', 'Delete', icon: Icons.delete_outline_rounded),
    ]);
    if (!mounted) return;
    if (a == 'rate') await _edit(c);
    if (a == 'delete') await _delete(c);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: Me.instance, builder: (context, _) => _body(context));

  Widget _body(BuildContext context) {
    final me = Me.instance;
    final b = me.book;
    if (b == null) return const Scaffold(body: Loading());
    final main = b.main;
    final codes = me.rates.keys.toList()..sort();
    final used = {for (final a in me.accounts) if (!a.deleted) a.currency};
    final missing = used.where((c) => c != b.currency && !me.rates.containsKey(c)).toList()..sort();
    return Scaffold(
      appBar: AppBar(title: const Text('Currencies')),
      body: PageBody(children: [
        KCard(
          child: Row(children: [
            CurrencyBadge(main),
            const SizedBox(width: Sp.md),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Main currency', style: T.tiny),
                Text('${main.code}, ${main.name}', maxLines: 1, overflow: TextOverflow.ellipsis, style: T.h3),
                Text(b.isOwner ? 'Totals, budgets and stats are in ${main.code}.' : 'Only the book\'s owner can change it.', style: T.small),
              ]),
            ),
            if (b.isOwner) ...[
              const SizedBox(width: Sp.sm),
              KButton(label: 'Change', small: true, kind: KButtonKind.secondary, onPressed: () => changeMainCurrency(context)),
            ],
          ]),
        ),
        if (missing.isNotEmpty) ...[
          const SectionTitle('Rates missing'),
          Notice('${missing.join(', ')} ${missing.length == 1 ? 'has' : 'have'} no rate yet, so accounts kept in '
              '${missing.length == 1 ? 'it' : 'them'} are left out of totals.'),
          const SizedBox(height: Sp.sm),
          KGroup(children: [
            for (final c in missing)
              KRow(
                leading: CurrencyBadge(currencyOf(c)),
                title: '$c, ${currencyOf(c).name}',
                sub: 'No rate yet',
                trailing: b.canEdit ? Text('Add rate', style: T.label.copyWith(color: K.blue)) : null,
                onTap: b.canEdit ? () => _add(c) : null,
              ),
          ]),
        ],
        const SectionTitle('Other currencies'),
        if (codes.isEmpty)
          KCard(child: EmptyState(icon: Icons.currency_exchange_rounded, text: 'Only ${main.code} so far. Add a currency for accounts kept in another one.'))
        else
          KGroup(children: [
            for (final c in codes)
              KRow(
                leading: CurrencyBadge(currencyOf(c)),
                title: '$c, ${currencyOf(c).name}',
                sub: '1 $c = ${rateWords(me.rates[c]!)} ${main.code}\n1 ${main.code} = ${rateWords(1 / me.rates[c]!)} $c',
                trailing: b.canEdit ? Icon(Icons.more_horiz_rounded, color: K.muted, size: 20) : null,
                onTap: b.canEdit ? () => _actions(c) : null,
              ),
          ]),
        if (b.canEdit) ...[
          const SizedBox(height: Sp.md),
          Center(child: KButton(label: 'Add a currency', icon: Icons.add_rounded, kind: KButtonKind.secondary, small: true, onPressed: () => _add())),
        ],
        const SizedBox(height: Sp.lg),
        Text(
            'A rate is how much ${main.code} one unit is worth. Each entry keeps the rate it was saved with, so a new rate here does not change past months.',
            style: T.small),
      ]),
    );
  }
}

/// A currency's sign in a soft circle, scaled down to fit.
class CurrencyBadge extends StatelessWidget {
  const CurrencyBadge(this.c, {super.key, this.size = 36});
  final Currency c;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(6),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: K.brand100, shape: BoxShape.circle),
      child: FittedBox(fit: BoxFit.scaleDown, child: Text(c.symbol, maxLines: 1, style: T.label.copyWith(color: K.brand600))),
    );
  }
}

/// A rate for reading: 22.5, 0.04444, 0.000005263.
String rateWords(num v) {
  String trim(String s) {
    if (!s.contains('.')) return s;
    s = s.replaceFirst(RegExp(r'0+$'), '');
    return s.endsWith('.') ? s.substring(0, s.length - 1) : s;
  }

  if (v == 0) return '0';
  if (v.abs() >= 1) return trim(v.toStringAsFixed(4));
  final p = v.toStringAsPrecision(4);
  return trim(p.contains('e') ? v.toStringAsFixed(10) : p);
}

/// Asks how much one [from] is worth in [to], letting the person type it
/// either way round. Returns the [to] per one [from], or null when closed.
Future<num?> askRate(BuildContext context, {required String from, required String to, num? current, required String title, String? note, String yes = 'Save'}) {
  return showKSheet<num>(context, title: title, builder: (ctx) => _RateAsk(from: from, to: to, current: current, note: note, yes: yes));
}

class _RateAsk extends StatefulWidget {
  const _RateAsk({required this.from, required this.to, this.current, this.note, required this.yes});
  final String from;
  final String to;
  final num? current;
  final String? note;
  final String yes;

  @override
  State<_RateAsk> createState() => _RateAskState();
}

class _RateAskState extends State<_RateAsk> {
  /// True: typing "1 from = ? to". False: "1 to = ? from".
  bool forward = true;
  late final TextEditingController _c =
      TextEditingController(text: widget.current == null || widget.current! <= 0 ? '' : rateWords(widget.current!));
  String? error;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _flip(bool f) {
    if (f == forward) return;
    final v = readNumber(_c.text);
    setState(() {
      forward = f;
      if (v != null && v > 0) _c.text = rateWords(1 / v);
    });
  }

  void _done() {
    final v = readNumber(_c.text);
    if (v == null || v <= 0) {
      setState(() => error = 'Enter a rate above zero.');
      return;
    }
    Navigator.of(context).pop(forward ? v : 1 / v);
  }

  @override
  Widget build(BuildContext context) {
    final a = forward ? widget.from : widget.to;
    final z = forward ? widget.to : widget.from;
    final v = readNumber(_c.text);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (error != null) ...[Notice(error!), const SizedBox(height: Sp.md)],
      if (widget.note != null) ...[Text(widget.note!, style: T.small), const SizedBox(height: Sp.md)],
      KSegmented<bool>(
        expand: true,
        items: [(true, '1 ${widget.from} in ${widget.to}'), (false, '1 ${widget.to} in ${widget.from}')],
        value: forward,
        onChanged: _flip,
      ),
      const SizedBox(height: Sp.md),
      KField(
        label: '1 $a = ? $z',
        controller: _c,
        autofocus: true,
        keyboard: const TextInputType.numberWithOptions(decimal: true),
        formatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
        suffix: z,
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _done(),
      ),
      const SizedBox(height: Sp.sm),
      Text(v == null || v <= 0 ? 'Type it whichever way round you know it.' : 'So 1 $z = ${rateWords(1 / v)} $a.', style: T.small),
      const SizedBox(height: Sp.lg),
      KButton(label: widget.yes, icon: Icons.check_rounded, expand: true, onPressed: _done),
    ]);
  }
}

/// Changes the book's main currency (owner only), asking what one of the
/// old currency is worth in the new one so totals keep their value.
Future<void> changeMainCurrency(BuildContext context) async {
  final b = Me.instance.book;
  if (b == null) return;
  if (!b.isOwner) {
    toast(context, 'Only the book\'s owner can change the main currency.', bad: true);
    return;
  }
  final code = await pickCurrency(context, title: 'New main currency', except: {b.currency});
  if (code == null || !context.mounted) return;
  final known = Me.instance.rates[code];
  final perOld = await askRate(context,
      from: b.currency,
      to: code,
      current: known == null || known <= 0 ? null : 1 / known,
      title: 'Main currency: $code',
      yes: 'Change to $code',
      note: 'Totals, budgets and stats switch to $code. Accounts keep their own currencies, and past entries keep their value.');
  if (perOld == null || !context.mounted) return;
  await attempt(context, () async {
    await Api.instance.rpc('set_main_currency', {'new_currency': code, 'per_old': perOld});
    await Me.instance.reloadBook();
  }, done: 'Main currency is now $code');
}
