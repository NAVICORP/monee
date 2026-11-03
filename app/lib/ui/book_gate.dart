import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/book.dart';
import '../core/format.dart';
import 'more/passcode.dart';
import 'shell.dart';
import 'theme.dart';
import 'widgets.dart';

/// After signing in: load who this is and their book, or start one.
class BookGate extends StatefulWidget {
  const BookGate({super.key});

  @override
  State<BookGate> createState() => _BookGateState();
}

class _BookGateState extends State<BookGate> {
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    Me.instance.addListener(_changed);
    _load();
  }

  @override
  void dispose() {
    Me.instance.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      await Me.instance.load();
    } on ApiError catch (e) {
      error = e.message;
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final book = Me.instance.book;
    if (loading && book == null) return const Scaffold(body: Loading());
    if (error != null && book == null) return Scaffold(body: SafeArea(child: LoadFailed(message: error!, onRetry: _load)));
    if (book == null) return StartBook(onMade: _load);
    return PasscodeGate(child: MoneeShell(key: ValueKey(book.id)));
  }
}

/// The IANA time zone for this device's offset, for a new book (it can be
/// changed in Settings).
String guessTimezone() {
  final m = DateTime.now().timeZoneOffset.inMinutes;
  const zones = {
    330: 'Asia/Kolkata', 345: 'Asia/Kathmandu', 360: 'Asia/Dhaka', 300: 'Asia/Karachi', 240: 'Asia/Dubai',
    180: 'Asia/Riyadh', 120: 'Africa/Cairo', 60: 'Europe/Paris', 0: 'Europe/London', 420: 'Asia/Bangkok',
    480: 'Asia/Singapore', 540: 'Asia/Tokyo', 600: 'Australia/Sydney', 720: 'Pacific/Auckland',
    -300: 'America/New_York', -360: 'America/Chicago', -420: 'America/Denver', -480: 'America/Los_Angeles', -180: 'America/Sao_Paulo',
  };
  return zones[m] ?? 'UTC';
}

/// The main currency to suggest for this device's time zone.
String guessCurrency() {
  return switch (guessTimezone()) {
    'Asia/Kolkata' => 'INR',
    'Asia/Dubai' => 'AED',
    'Asia/Riyadh' => 'SAR',
    'Asia/Karachi' => 'PKR',
    'Asia/Dhaka' => 'BDT',
    'Asia/Kathmandu' => 'NPR',
    'Europe/London' => 'GBP',
    'Europe/Paris' => 'EUR',
    'Asia/Singapore' => 'SGD',
    'Australia/Sydney' => 'AUD',
    String z when z.startsWith('America/') => 'USD',
    _ => 'INR',
  };
}

/// Signed in, but no book yet: start one.
class StartBook extends StatefulWidget {
  const StartBook({super.key, required this.onMade});
  final Future<void> Function() onMade;

  @override
  State<StartBook> createState() => _StartBookState();
}

class _StartBookState extends State<StartBook> {
  final _name = TextEditingController(text: 'My money');
  final _me = TextEditingController();
  String currency = guessCurrency();
  bool busy = false;
  String? error;

  @override
  void dispose() {
    _name.dispose();
    _me.dispose();
    super.dispose();
  }

  Future<void> _make() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final r = await Api.instance.rpc('create_book', {
        'name': _name.text.trim().isEmpty ? 'My money' : _name.text.trim(),
        'currency': currency,
        'timezone': guessTimezone(),
        'my_name': _me.text.trim(),
      });
      if (r is Map) await Api.instance.chooseBook(r['book_id'] as String?);
      await widget.onMade();
    } on ApiError catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _pickCurrency() async {
    final c = await pickCurrency(context, selected: currency, title: 'Main currency');
    if (c != null) setState(() => currency = c);
  }

  @override
  Widget build(BuildContext context) {
    final me = Me.instance;
    final who = me.phone != null ? prettyPhone(me.phone) : (me.email ?? '');
    final cur = currencyOf(currency);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Sp.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Center(child: MoneeIcon(size: 64, shadow: true)),
                const SizedBox(height: Sp.lg),
                const Text('Start your book', style: T.display, textAlign: TextAlign.center),
                const SizedBox(height: 6),
                if (who.isNotEmpty) Text('Signed in as $who.', textAlign: TextAlign.center, style: T.body.copyWith(color: K.muted)),
                const SizedBox(height: Sp.xl),
                KCard(
                  padding: const EdgeInsets.all(Sp.xl),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    if (error != null) ...[Notice(error!), const SizedBox(height: Sp.md)],
                    KField(label: 'Book name', controller: _name, hint: 'My money', caps: TextCapitalization.words),
                    const SizedBox(height: Sp.md),
                    KField(label: 'Your name', controller: _me, hint: 'Optional', caps: TextCapitalization.words),
                    const SizedBox(height: Sp.md),
                    KChoice(label: 'Main currency', value: '${cur.code}, ${cur.name}', icon: Icons.payments_outlined, onTap: _pickCurrency),
                    const SizedBox(height: Sp.sm),
                    Text('Accounts can still keep other currencies. You start with cash, a bank account and everyday categories.', style: T.small),
                    const SizedBox(height: Sp.lg),
                    KButton(label: 'Start', icon: Icons.arrow_forward_rounded, expand: true, busy: busy, onPressed: _make),
                  ]),
                ),
                const SizedBox(height: Sp.md),
                Center(child: KButton(label: 'Sign out', kind: KButtonKind.ghost, small: true, onPressed: () => Api.instance.signOut())),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// A currency to pick, from the list Pursee knows, searchable.
Future<String?> pickCurrency(BuildContext context, {String? selected, String title = 'Currency', Set<String> except = const {}}) async {
  final p = await showPicker<String>(context, title: title, selected: selected, search: true, options: [
    for (final c in kCurrencies)
      if (!except.contains(c.code)) PickOption(c.code, c.code, sub: c.name, trailing: c.symbol),
  ]);
  return p?.value;
}
