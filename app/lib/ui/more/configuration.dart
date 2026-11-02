import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/book.dart';
import '../../core/format.dart';
import '../book_gate.dart';
import '../theme.dart';
import '../widgets.dart';
import 'budgets.dart';
import 'categories.dart';
import 'currencies.dart';
import 'more_common.dart';
import 'repeats.dart';
import 'tags.dart';

/// More > Configuration: the book's own settings. Only the owner changes
/// them; everyone else sees them as they are.
class ConfigurationPage extends StatelessWidget {
  const ConfigurationPage({super.key});

  static const _weekdays = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: Me.instance, builder: (context, _) => _body(context));

  Widget _body(BuildContext context) {
    final me = Me.instance;
    final b = me.book;
    if (b == null) return const Scaffold(body: Loading());
    final own = b.isOwner;
    VoidCallback? tap(Future<void> Function() f) => own ? () => f() : null;
    final subs = me.rates.keys.toList()..sort();
    return Scaffold(
      appBar: AppBar(title: const Text('Configuration')),
      body: PageBody(bottom: 40, children: [
        if (!own) const ReadOnlyNote('Only the book\'s owner can change these settings.'),
        const GroupLabel('Book'),
        LinkGroup([
          LinkRow(Icons.menu_book_outlined, 'Book name', tap(() => _rename(context, b)), value: b.name),
          LinkRow(Icons.payments_outlined, 'Main currency', tap(() => changeMainCurrency(context)), value: '${b.main.code}, ${b.main.name}'),
          LinkRow(Icons.currency_exchange_rounded, 'Sub currencies', () => openPage<void>(context, const CurrenciesPage()),
              value: subs.isEmpty ? 'None' : subs.join(', ')),
          LinkRow(Icons.public_rounded, 'Time zone', tap(() => _timezone(context, b)), value: zoneLabel(b.timezone)),
        ]),
        const GroupLabel('Trans tab'),
        LinkGroup([
          LinkRow(Icons.calendar_view_day_outlined, 'Start screen', tap(() => _startScreen(context, b)),
              value: b.startScreen == 'calendar' ? 'Calendar' : 'Daily'),
          LinkRow(Icons.event_outlined, 'Monthly start day', tap(() => _monthStart(context, b)), value: 'Every ${b.monthStartDay}'),
          LinkRow(Icons.view_week_outlined, 'Weekly start day', tap(() => _weekStart(context, b)), value: _weekdays[b.weekStart % 7]),
          LinkRow(Icons.date_range_outlined, 'Financial year starts', tap(() => _fyStart(context, b)), value: kMonths[(b.fyStartMonth - 1) % 12]),
          SwitchTile(
            title: 'Carry-over',
            sub: 'Adds what was left before the period into the Trans tab total',
            value: b.carryOver,
            onChanged: own ? (v) => saveBook(context, {'carry_over': v}) : null,
          ),
          LinkRow(Icons.event_repeat_rounded, 'Repeats show', tap(() => _repeatShow(context, b)),
              value: b.repeatShow == 'month_start' ? 'From the 1st' : 'On their date'),
        ]),
        const GroupLabel('Categories and repeats'),
        LinkGroup([
          LinkRow(Icons.south_west_rounded, 'Income categories', () => openPage<void>(context, const CategoriesPage(kind: 'income'))),
          LinkRow(Icons.north_east_rounded, 'Expense categories', () => openPage<void>(context, const CategoriesPage(kind: 'expense'))),
          SwitchTile(
            title: 'Subcategories',
            sub: 'Pick a subcategory under each category',
            value: b.subcategories,
            onChanged: own ? (v) => saveBook(context, {'subcategories': v}) : null,
          ),
          LinkRow(Icons.savings_outlined, 'Budgets', () => openPage<void>(context, const BudgetsPage())),
          LinkRow(Icons.sell_outlined, 'Tags', () => openPage<void>(context, const TagsPage())),
          LinkRow(Icons.event_repeat_rounded, 'Repeats', () => openPage<void>(context, const RepeatsPage())),
        ]),
        const GroupLabel('Cards'),
        LinkGroup([
          LinkRow(Icons.credit_card_rounded, 'Card spending counts', tap(() => pickCardDisplay(context)), value: cardDisplayWords(b.cardDisplay)),
        ]),
        const GroupLabel('Books'),
        LinkGroup([
          if (me.books.length > 1) LinkRow(Icons.swap_horiz_rounded, 'Switch book', () => switchBook(context), value: b.name),
          LinkRow(Icons.add_rounded, 'Start a new book', () => startNewBook(context), sub: 'Separate accounts and entries, like a business'),
          if (own) LinkRow(Icons.delete_outline_rounded, 'Delete this book', () => deleteBook(context), bad: true),
        ]),
      ]),
    );
  }

  Future<void> _rename(BuildContext context, Book b) async {
    final v = await askText(context, title: 'Book name', label: 'Name', initial: b.name, maxLength: 60, caps: TextCapitalization.words);
    if (v == null || v == b.name || !context.mounted) return;
    await saveBook(context, {'name': v}, done: 'Saved');
  }

  Future<void> _timezone(BuildContext context, Book b) async {
    final zones = [...kTimeZones];
    if (!zones.any((z) => z.$1 == b.timezone)) zones.insert(0, (b.timezone, b.timezone));
    final p = await showPicker<String>(context, title: 'Time zone', selected: b.timezone, search: true, options: [
      for (final (id, label) in zones) PickOption(id, label, sub: id),
    ]);
    if (p == null || p.value == b.timezone || !context.mounted) return;
    await saveBook(context, {'timezone': p.value}, done: 'Time zone saved');
  }

  Future<void> _startScreen(BuildContext context, Book b) async {
    final p = await showPicker<String>(context, title: 'Start screen', selected: b.startScreen, options: const [
      PickOption('daily', 'Daily', sub: 'Entries day by day'),
      PickOption('calendar', 'Calendar', sub: 'The month as a calendar'),
    ]);
    if (p == null || p.value == b.startScreen || !context.mounted) return;
    await saveBook(context, {'start_screen': p.value}, done: 'Saved');
  }

  Future<void> _monthStart(BuildContext context, Book b) async {
    final p = await showPicker<int>(context, title: 'Months start on', selected: b.monthStartDay, options: [
      for (var d = 1; d <= 31; d++) PickOption(d, 'Every $d', sub: d > 28 ? 'Shorter months start on their last day' : null),
    ]);
    if (p == null || p.value == b.monthStartDay || !context.mounted) return;
    await saveBook(context, {'month_start_day': p.value}, done: 'Months start on day ${p.value}');
  }

  Future<void> _weekStart(BuildContext context, Book b) async {
    final p = await showPicker<int>(context, title: 'Weeks start on', selected: b.weekStart, options: [
      for (var d = 0; d < 7; d++) PickOption(d, _weekdays[d]),
    ]);
    if (p == null || p.value == b.weekStart || !context.mounted) return;
    await saveBook(context, {'week_start': p.value}, done: 'Weeks start on ${_weekdays[p.value]}');
  }

  Future<void> _fyStart(BuildContext context, Book b) async {
    final p = await showPicker<int>(context, title: 'Financial year starts in', selected: b.fyStartMonth, options: [
      for (var m = 1; m <= 12; m++) PickOption(m, kMonths[m - 1], sub: m == 1 ? 'The calendar year' : (m == 4 ? 'April to March' : null)),
    ]);
    if (p == null || p.value == b.fyStartMonth || !context.mounted) return;
    await saveBook(context, {'fy_start_month': p.value}, done: 'Saved');
  }

  Future<void> _repeatShow(BuildContext context, Book b) async {
    final p = await showPicker<String>(context, title: 'Repeats show', selected: b.repeatShow, options: const [
      PickOption('on_date', 'On their date', sub: 'A repeat is recorded on its own day'),
      PickOption('month_start', 'From the first of the month', sub: 'This month\'s repeats are all recorded on the 1st'),
    ]);
    if (p == null || p.value == b.repeatShow || !context.mounted) return;
    await saveBook(context, {'repeat_show': p.value}, done: 'Saved');
  }
}

String cardDisplayWords(String v) => v == 'lump_sum' ? 'On payment day' : 'At the time';

/// How card spending counts: on the day it was spent, or as one lump on the
/// day the card is paid. Owner only.
Future<void> pickCardDisplay(BuildContext context) async {
  final b = Me.instance.book;
  if (b == null) return;
  if (!b.isOwner) {
    toast(context, 'Only the book\'s owner can change this.', bad: true);
    return;
  }
  final p = await showPicker<String>(context, title: 'Card spending counts', selected: b.cardDisplay, options: const [
    PickOption('at_time', 'At the time', sub: 'Each card spend is an expense on the day it was spent'),
    PickOption('lump_sum', 'On payment day', sub: 'A card\'s spending counts as one expense on the day it is paid'),
  ]);
  if (p == null || p.value == b.cardDisplay || !context.mounted) return;
  await saveBook(context, {'card_display': p.value}, done: 'Saved');
}

String _roleWords(String role) => switch (role) { 'owner' => 'Yours', 'viewer' => 'You can look', _ => 'You can edit' };

/// Opens another of this person's books.
Future<void> switchBook(BuildContext context) async {
  final me = Me.instance;
  final cur = me.book;
  final p = await showPicker<String>(context, title: 'Your books', selected: cur?.id, options: [
    for (final x in me.books) PickOption(x.id, x.name, sub: '${_roleWords(x.role)}, ${x.currency}', icon: Icons.menu_book_outlined),
  ]);
  if (p == null || p.value == cur?.id) return;
  try {
    await me.choose(p.value);
  } on ApiError catch (e) {
    if (context.mounted) toast(context, e.message, bad: true);
  }
}

/// A new book with its own accounts and categories, opened at once.
Future<void> startNewBook(BuildContext context) async {
  await showKSheet<bool>(context, title: 'Start a new book', builder: (ctx) => const _NewBook());
}

class _NewBook extends StatefulWidget {
  const _NewBook();

  @override
  State<_NewBook> createState() => _NewBookState();
}

class _NewBookState extends State<_NewBook> {
  final _name = TextEditingController();
  String currency = Me.instance.book?.currency ?? guessCurrency();
  bool busy = false;
  String? error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final c = await pickCurrency(context, selected: currency, title: 'Main currency');
    if (c != null && mounted) setState(() => currency = c);
  }

  Future<void> _make() async {
    final name = _name.text.trim();
    if (name.isEmpty || name.length > 60) {
      setState(() => error = 'Give the book a name (up to 60 characters).');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    final nav = Navigator.of(context);
    try {
      final b = Me.instance.book;
      final r = await Api.instance.rpc('create_book', {
        'name': name,
        'currency': currency,
        'timezone': b?.timezone ?? guessTimezone(),
        'my_name': b?.memberName ?? '',
      });
      final id = r is Map ? r['book_id'] as String? : null;
      if (id != null) await Api.instance.chooseBook(id);
      await Me.instance.load();
      if (!mounted) return;
      toast(context, '$name is open');
      nav.pop(true);
    } on ApiError catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cur = currencyOf(currency);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (error != null) ...[Notice(error!), const SizedBox(height: Sp.md)],
      const Text('A separate set of accounts, categories and entries: for a business, a trip, or someone else\'s money. Switch books from More.',
          style: T.small),
      const SizedBox(height: Sp.md),
      KField(label: 'Book name', controller: _name, hint: 'Shop', autofocus: true, caps: TextCapitalization.words),
      const SizedBox(height: Sp.md),
      KChoice(label: 'Main currency', value: '${cur.code}, ${cur.name}', icon: Icons.payments_outlined, onTap: busy ? null : _pick),
      const SizedBox(height: Sp.lg),
      KButton(label: 'Start the book', icon: Icons.arrow_forward_rounded, expand: true, busy: busy, onPressed: _make),
    ]);
  }
}

/// Deletes the book being worked in (owner only), after its name is typed.
Future<void> deleteBook(BuildContext context) async {
  final b = Me.instance.book;
  if (b == null || !b.isOwner) return;
  await showKSheet<bool>(context, title: 'Delete this book?', builder: (ctx) => _DeleteBook(name: b.name));
}

class _DeleteBook extends StatefulWidget {
  const _DeleteBook({required this.name});
  final String name;

  @override
  State<_DeleteBook> createState() => _DeleteBookState();
}

class _DeleteBookState extends State<_DeleteBook> {
  final _c = TextEditingController();
  bool busy = false;
  String? error;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  bool get _matches => _c.text.trim().toLowerCase() == widget.name.trim().toLowerCase();

  Future<void> _delete() async {
    if (!_matches) return;
    setState(() {
      busy = true;
      error = null;
    });
    final nav = Navigator.of(context);
    try {
      await Api.instance.rpc('delete_book', {'confirm_name': _c.text.trim()});
      await Me.instance.load();
      if (!mounted) return;
      toast(context, '${widget.name} is deleted');
      nav.pop(true);
    } on ApiError catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Notice('Everything in ${widget.name} is deleted for good: accounts, entries, budgets and repeats. '
          'Anyone you shared it with loses it too. This cannot be undone.'),
      const SizedBox(height: Sp.md),
      if (error != null) ...[Notice(error!), const SizedBox(height: Sp.md)],
      KField(
        label: 'Type the book\'s name to confirm',
        controller: _c,
        hint: widget.name,
        caps: TextCapitalization.none,
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: Sp.lg),
      KButton(
        label: 'Delete for good',
        icon: Icons.delete_forever_outlined,
        kind: KButtonKind.danger,
        expand: true,
        busy: busy,
        onPressed: _matches ? _delete : null,
      ),
    ]);
  }
}

/// Common time zones, with the places people know them by.
const List<(String, String)> kTimeZones = [
  ('Asia/Kolkata', 'India'),
  ('Asia/Dubai', 'UAE and Oman'),
  ('Asia/Riyadh', 'Saudi Arabia'),
  ('Asia/Qatar', 'Qatar'),
  ('Asia/Kuwait', 'Kuwait'),
  ('Asia/Bahrain', 'Bahrain'),
  ('Asia/Muscat', 'Oman'),
  ('Asia/Karachi', 'Pakistan'),
  ('Asia/Dhaka', 'Bangladesh'),
  ('Asia/Kathmandu', 'Nepal'),
  ('Asia/Colombo', 'Sri Lanka'),
  ('Asia/Singapore', 'Singapore'),
  ('Asia/Kuala_Lumpur', 'Malaysia'),
  ('Asia/Jakarta', 'Indonesia, Jakarta'),
  ('Asia/Manila', 'Philippines'),
  ('Asia/Bangkok', 'Thailand'),
  ('Asia/Ho_Chi_Minh', 'Vietnam'),
  ('Asia/Hong_Kong', 'Hong Kong'),
  ('Asia/Shanghai', 'China'),
  ('Asia/Tokyo', 'Japan'),
  ('Asia/Seoul', 'South Korea'),
  ('Asia/Amman', 'Jordan'),
  ('Europe/Istanbul', 'Turkey'),
  ('Africa/Cairo', 'Egypt'),
  ('Africa/Nairobi', 'Kenya'),
  ('Africa/Lagos', 'Nigeria'),
  ('Africa/Accra', 'Ghana'),
  ('Africa/Johannesburg', 'South Africa'),
  ('Europe/London', 'United Kingdom'),
  ('Europe/Dublin', 'Ireland'),
  ('Europe/Paris', 'France'),
  ('Europe/Berlin', 'Germany'),
  ('Europe/Amsterdam', 'Netherlands'),
  ('Europe/Madrid', 'Spain'),
  ('Europe/Rome', 'Italy'),
  ('Europe/Zurich', 'Switzerland'),
  ('Europe/Stockholm', 'Sweden'),
  ('Europe/Warsaw', 'Poland'),
  ('Europe/Moscow', 'Moscow'),
  ('America/New_York', 'US Eastern'),
  ('America/Chicago', 'US Central'),
  ('America/Denver', 'US Mountain'),
  ('America/Los_Angeles', 'US Pacific'),
  ('America/Toronto', 'Canada, Toronto'),
  ('America/Vancouver', 'Canada, Vancouver'),
  ('America/Mexico_City', 'Mexico'),
  ('America/Sao_Paulo', 'Brazil'),
  ('Australia/Perth', 'Australia, Perth'),
  ('Australia/Sydney', 'Australia, Sydney'),
  ('Pacific/Auckland', 'New Zealand'),
  ('UTC', 'UTC'),
];

String zoneLabel(String id) {
  for (final (z, label) in kTimeZones) {
    if (z == id) return label;
  }
  return id;
}
