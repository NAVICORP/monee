import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/book.dart';
import '../../core/format.dart';
import '../money.dart';
import '../theme.dart';
import '../widgets.dart';

/// Kinds of account a card is paid from, or a debit card spends from.
const kPayingKinds = {'cash', 'bank', 'prepaid', 'savings', 'overdraft', 'other'};

/// A list of json objects from the server, or an empty list.
List<Map<String, dynamic>> jsonRows(Object? j) =>
    (j is List ? j : const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();

/// A json object from the server, or null.
Map<String, dynamic>? jsonMap(Object? j) => j is Map ? Map<String, dynamic>.from(j) : null;

/// Jan .. Dec from a month number (1 to 12).
String shortMonth(Object? m) {
  final i = toNum(m).toInt();
  return kMonthsShort[i < 1 || i > 12 ? 0 : i - 1];
}

/// 12.5K, 3M: for the top of a chart.
String chartMoney(num v, String currency) {
  final c = currencyOf(currency);
  final a = v.abs();
  String one(num x) {
    final s = x.toStringAsFixed(1);
    return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
  }

  final String n;
  if (a >= 1e9) {
    n = '${one(a / 1e9)}B';
  } else if (a >= 1e6) {
    n = '${one(a / 1e6)}M';
  } else if (a >= 1e3) {
    n = '${one(a / 1e3)}K';
  } else {
    n = '${a.round()}';
  }
  final s = c.spaced ? '${c.symbol} $n' : '${c.symbol}$n';
  return v < 0 ? '-$s' : s;
}

/// A balance in its currency: above zero green, below zero red, zero muted.
class BalanceText extends StatelessWidget {
  const BalanceText(this.amount, {super.key, required this.currency, this.style = T.bodyStrong, this.symbol = true, this.align});
  final num amount;
  final String currency;
  final TextStyle style;
  final bool symbol;
  final TextAlign? align;

  @override
  Widget build(BuildContext context) {
    return MoneyText(
      amount,
      currency: currency,
      kind: amount > 0 ? 'income' : (amount < 0 ? 'expense' : null),
      style: amount == 0 ? style.copyWith(color: K.muted) : style,
      symbol: symbol,
      align: align,
    );
  }
}

/// Money owed on a card: owed in red, nothing muted, a credit in green.
class OwedText extends StatelessWidget {
  const OwedText(this.amount, {super.key, required this.currency, this.style = T.bodyStrong});
  final num amount;
  final String currency;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return MoneyText(
      amount,
      currency: currency,
      kind: amount > 0 ? 'expense' : (amount < 0 ? 'income' : null),
      style: amount == 0 ? style.copyWith(color: K.muted) : style,
    );
  }
}

/// Scales its child down (never up) to fit, so an amount never spills out.
/// Give it loose room (a Column, an Align): in a box of a fixed width it would
/// grow taller to keep its shape.
class FitEnd extends StatelessWidget {
  const FitEnd({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      FittedBox(fit: BoxFit.scaleDown, alignment: AlignmentDirectional.centerEnd, child: child);
}

/// "USD", "USD and EUR", "USD, EUR and GBP".
String andList(List<String> items) {
  if (items.isEmpty) return '';
  if (items.length == 1) return items.first;
  return '${items.sublist(0, items.length - 1).join(', ')} and ${items.last}';
}

/// Asks, then deletes an account: it leaves the Accounts tab and the totals,
/// and can be restored from Account settings. True when it was deleted; the
/// caller then calls Me.instance.changed(lists: true).
Future<bool> deleteAccountAsked(BuildContext context, Account a) async {
  final ok = await confirm(
    context,
    title: 'Delete ${a.name}?',
    text: 'It leaves the Accounts tab and the totals. Its transactions stay. You can restore it from Account settings.',
    yes: 'Delete',
    danger: true,
  );
  if (!ok || !context.mounted) return false;
  try {
    await Api.instance.update('accounts', {'deleted_at': DateTime.now().toUtc().toIso8601String()}, where: {'id': 'eq.${a.id}'});
    if (context.mounted) toast(context, '${a.name} deleted');
    return true;
  } on ApiError catch (e) {
    if (context.mounted) toast(context, e.message, bad: true);
    return false;
  }
}
