import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api.dart';
import '../../core/book.dart';
import '../../core/format.dart';
import '../money.dart';
import '../theme.dart';
import '../widgets.dart';
import 'calculator.dart';

part 'entry_fields.dart';

/// The account and the day the last entry was saved with, for this visit:
/// a new entry starts on them.
String? _lastAccountId;
DateTime? _lastDay;

/// Adds or edits a transaction on a full-screen page.
///
/// `txn` edits that transaction; with `copy` it starts a new entry filled
/// from it (after asking whether to keep its date or use today). `template`
/// is a bookmarks row to fill a new entry from, and `day` the date of a new
/// entry. True when something was saved or deleted.
Future<bool> openEntry(
  BuildContext context, {
  Txn? txn,
  String kind = 'expense',
  DateTime? day,
  Map<String, dynamic>? template,
  bool copy = false,
}) async {
  if (Me.instance.book == null) return false;
  var keepDate = false;
  if (txn != null && copy) {
    final now = Me.instance.book?.today ?? DateTime.now();
    final pick = await showPicker<bool>(context, title: 'Copy this entry', options: [
      PickOption<bool>(true, 'Keep its date', sub: '${dayLabel(txn.at)} ${txn.at.year}', icon: Icons.event_outlined),
      PickOption<bool>(false, 'Use today', sub: '${dayLabel(now)} ${now.year}', icon: Icons.today_outlined),
    ]);
    if (pick == null || !context.mounted) return false;
    keepDate = pick.value;
  }
  // On the tab's own navigator, so the footer tabs stay in view.
  final saved = await Navigator.of(context).push<bool>(MaterialPageRoute<bool>(
    fullscreenDialog: true,
    builder: (_) => _EntryPage(
      txn: txn,
      kind: kind,
      day: day,
      template: template,
      copy: copy && txn != null,
      keepDate: keepDate,
    ),
  ));
  return saved ?? false;
}

class _EntryPage extends StatefulWidget {
  const _EntryPage({this.txn, required this.kind, this.day, this.template, this.copy = false, this.keepDate = false});
  final Txn? txn;
  final String kind;
  final DateTime? day;
  final Map<String, dynamic>? template;
  final bool copy;
  final bool keepDate;

  @override
  State<_EntryPage> createState() => _EntryPageState();
}

class _EntryPageState extends State<_EntryPage> {
  late final Book book;
  final note = TextEditingController();
  final description = TextEditingController();
  final tagCtl = TextEditingController();
  final rateCtl = TextEditingController();

  bool loading = true;
  String? loadError;
  bool busy = false;

  /// Something was saved or deleted while the page was open.
  bool touched = false;

  /// The form as it was opened (or last saved), to know when it has changed.
  String baseline = '';

  String? editId;
  String kind = 'expense';
  DateTime at = DateTime.now();
  String? accountId;
  String? toAccountId;
  String? categoryId;
  num amount = 0;
  num fee = 0;

  /// What arrived on a transfer between two currencies, when typed by hand
  /// (otherwise it is worked out from the rates).
  num? toAmount;

  bool splitting = false;
  final parts = <_Part>[];
  final tags = <String>[];
  final photos = <_Photo>[];

  // A new entry's repeat or instalment.
  String? freq;
  int every = 1;
  DateTime? endsOn;
  int? months;

  // What an existing entry belongs to: shown, not changed here.
  String? repeatText;
  String? planId;
  int? planNo;
  int? planMonths;
  num? planTotal;

  // Notes used before in the same category, newest first.
  List<String> notes = const [];
  String? notesKey;

  // ---------------------------------------------------------------- what the form says

  bool get canEdit => book.canEdit;
  bool get editing => editId != null;
  bool get isTransfer => kind == 'transfer';
  Account? get account => Me.instance.account(accountId);
  Account? get toAccount => Me.instance.account(toAccountId);
  String get currency => account?.currency ?? book.currency;
  String? get toCurrency => toAccount?.currency;
  bool get foreign => currency != book.currency;
  bool get twoCurrencies => isTransfer && toCurrency != null && toCurrency != currency;
  bool get hasPlan => freq != null || months != null;

  /// How much of the main currency one unit of the account's currency is worth.
  num? get rate => foreign ? _readNum(rateCtl.text) : 1;

  /// The category the entry is filed under (a split's first part).
  String? get mainCategory => splitting && parts.isNotEmpty ? parts.first.categoryId : categoryId;

  /// What arrived on the other account: typed, or from the rates.
  num? get received => toAmount ?? _autoReceived;

  num? get _autoReceived {
    final tc = toCurrency;
    if (!twoCurrencies || tc == null || amount <= 0) return null;
    final from = rate;
    final to = Me.instance.rateOf(tc);
    if (from == null || to == null || to == 0) return null;
    return _round(amount * from / to, tc);
  }

  /// What is still to be split (below 0 when the parts are more than the whole).
  num get left => _round(_round(amount) - parts.fold<num>(0, (s, p) => s + _round(p.amount)));

  bool get splitDone => left.abs() < 0.5 / math.pow(10, currencyOf(currency).decimals);

  String? get planText {
    final m = months;
    if (m != null) return 'Instalment over $m months';
    final f = freq;
    if (f != null) return _repeatLabel(f, every, endsOn);
    return null;
  }

  bool get _dirty => canEdit && !loading && loadError == null && _signature() != baseline;

  static num? _readNum(String s) {
    final v = num.tryParse(s.trim());
    return v == null || v <= 0 ? null : v;
  }

  /// An amount rounded to the decimals its currency keeps.
  num _round(num v, [String? code]) {
    final f = math.pow(10, currencyOf(code ?? currency).decimals);
    final r = (v * f).round() / f;
    return r == r.truncateToDouble() ? r.toInt() : r;
  }

  static String _kindOk(String? k) => switch (k) {
        'income' => 'income',
        'transfer' => 'transfer',
        _ => 'expense',
      };

  String? _liveId(String? id) => id != null && Me.instance.liveAccounts.any((a) => a.id == id) ? id : null;

  String? _categoryOk(String? id) {
    final c = Me.instance.category(id);
    return c != null && !c.deleted && c.kind == kind ? c.id : null;
  }

  /// Accounts to choose from: not deleted and not hidden (the chosen one always shows).
  List<Account> _pickable(String? keep) => [
        for (final a in Me.instance.liveAccounts)
          if (a.id == keep || (!a.hidden && !(a.group?.hidden ?? false))) a,
      ];

  String _signature() => [
        kind,
        isoStamp(at),
        accountId,
        toAccountId,
        categoryId,
        amount,
        fee,
        toAmount,
        rateCtl.text.trim(),
        note.text.trim(),
        description.text.trim(),
        tags.join('|'),
        splitting,
        for (final p in parts) '${p.categoryId}:${p.amount}:${p.note.text.trim()}',
        photos.where((p) => p.id == null).length,
        freq,
        every,
        endsOn,
        months,
      ].join(';');

  // ---------------------------------------------------------------- opening

  @override
  void initState() {
    super.initState();
    book = Me.instance.book!;
    _start();
  }

  @override
  void dispose() {
    note.dispose();
    description.dispose();
    tagCtl.dispose();
    rateCtl.dispose();
    for (final p in parts) {
      p.note.dispose();
    }
    super.dispose();
  }

  void _start() {
    final t = widget.txn;
    if (t == null) {
      _fresh();
    } else {
      unawaited(_load(t.id));
    }
  }

  /// A new entry: from a bookmark, or blank on the last used account and day.
  void _fresh() {
    final tpl = widget.template;
    final now = DateTime.now();
    final d = widget.day ?? _lastDay ?? Me.instance.book?.today ?? now;
    kind = _kindOk((tpl?['kind'] as String?) ?? widget.kind);
    at = DateTime(d.year, d.month, d.day, now.hour, now.minute);
    accountId = _liveId(tpl?['account_id'] as String?) ?? _liveId(_lastAccountId) ?? _pickable(null).firstOrNull?.id;
    if (tpl != null) {
      if (kind == 'transfer') toAccountId = _liveId(tpl['to_account_id'] as String?);
      if (kind != 'transfer') categoryId = _categoryOk(tpl['category_id'] as String?);
      final a = tpl['amount'];
      amount = a == null ? 0 : toNum(a);
      fee = kind == 'transfer' ? toNum(tpl['fee']) : 0;
      note.text = (tpl['note'] as String?) ?? '';
      description.text = (tpl['description'] as String?) ?? '';
    }
    if (toAccountId == accountId) toAccountId = null;
    _resetRate();
    loading = false;
    baseline = _signature();
    _loadNotes();
  }

  /// An entry to edit or copy: its full row, split parts, tags and photos.
  Future<void> _load(String id) async {
    try {
      final rows = await Api.instance.select('txns', where: {'id': 'eq.$id'});
      if (rows.isEmpty) throw ApiError('This entry is not here any more. It may have been deleted.');
      final r = rows.first;
      final more = await Future.wait([
        Api.instance.select('txn_splits', where: {'txn_id': 'eq.$id'}),
        Api.instance.select('txn_tags', columns: 'tag_id', where: {'txn_id': 'eq.$id'}),
        if (!widget.copy) Api.instance.select('txn_photos', where: {'txn_id': 'eq.$id'}, order: 'created_at'),
      ]);
      final tagIds = [for (final l in more[1]) '${l['tag_id']}'];
      final tagRows = tagIds.isEmpty
          ? <Map<String, dynamic>>[]
          : await Api.instance.select('tags', columns: 'id,name', where: {'id': 'in.(${tagIds.join(',')})'}, order: 'name');
      final rid = widget.copy ? null : r['repeat_id'] as String?;
      final pid = widget.copy ? null : r['plan_id'] as String?;
      Map<String, dynamic>? rule;
      Map<String, dynamic>? plan;
      if (rid != null) rule = (await Api.instance.select('repeat_rules', where: {'id': 'eq.$rid'})).firstOrNull;
      if (pid != null) plan = (await Api.instance.select('instalment_plans', where: {'id': 'eq.$pid'})).firstOrNull;
      if (!mounted) return;
      final stored = parseStamp(r['at']) ?? DateTime.now();
      final now = DateTime.now();
      final today = Me.instance.book?.today ?? now;
      setState(() {
        editId = widget.copy ? null : id;
        kind = _kindOk(r['kind'] as String?);
        at = widget.copy && !widget.keepDate ? DateTime(today.year, today.month, today.day, now.hour, now.minute) : stored;
        accountId = r['account_id'] as String?;
        toAccountId = kind == 'transfer' ? r['to_account_id'] as String? : null;
        categoryId = kind == 'transfer' ? null : r['category_id'] as String?;
        amount = toNum(r['amount']);
        fee = kind == 'transfer' ? toNum(r['fee']) : 0;
        toAmount = twoCurrencies && r['to_amount'] != null ? toNum(r['to_amount']) : null;
        note.text = (r['note'] as String?) ?? '';
        description.text = (r['description'] as String?) ?? '';
        tags
          ..clear()
          ..addAll([for (final g in tagRows) '${g['name']}']);
        for (final p in parts) {
          _disposeLater(p.note);
        }
        parts.clear();
        if (kind != 'transfer') {
          for (final s in more[0]) {
            parts.add(_Part(categoryId: s['category_id'] as String?, amount: toNum(s['amount']), text: (s['note'] as String?) ?? ''));
          }
        }
        splitting = parts.isNotEmpty;
        photos.clear();
        if (!widget.copy) {
          photos.addAll([for (final p in more[2]) _Photo(id: '${p['id']}', path: '${p['path']}')]);
        }
        // The rate the entry was made at; a copy on today's date takes today's.
        final storedRate = r['rate'] == null ? null : toNum(r['rate']);
        final nowRate = Me.instance.rateOf(currency);
        final useRate = widget.copy && !widget.keepDate ? (nowRate ?? storedRate) : (storedRate ?? nowRate);
        rateCtl.text = foreign && useRate != null ? rateText(useRate) : '';
        repeatText = rid == null
            ? null
            : (rule == null
                ? 'Made by a repeat'
                : _repeatLabel((rule['freq'] as String?) ?? 'month', (rule['every'] as num?)?.toInt() ?? 1, parseDay(rule['ends_on'])));
        planId = pid;
        planNo = pid == null ? null : (r['plan_no'] as num?)?.toInt();
        planMonths = plan == null ? null : (plan['months'] as num?)?.toInt();
        planTotal = plan == null ? null : toNum(plan['total']);
        loading = false;
        loadError = null;
      });
      baseline = _signature();
      _loadNotes();
      for (final p in photos) {
        unawaited(_loadPhoto(p));
      }
    } on ApiError catch (e) {
      if (mounted) {
        setState(() {
          loading = false;
          loadError = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          loading = false;
          loadError = 'This entry could not be opened. Try again.';
        });
      }
    }
  }

  /// Notes used before in this category (or of this kind), newest first.
  Future<void> _loadNotes() async {
    if (!canEdit) return;
    final cat = isTransfer ? null : mainCategory;
    final key = cat ?? 'kind:$kind';
    if (key == notesKey) return;
    notesKey = key;
    notes = const [];
    try {
      final rows = await Api.instance.select('txns',
          columns: 'note',
          where: cat != null ? {'category_id': 'eq.$cat', 'note': 'not.is.null'} : {'kind': 'eq.$kind', 'note': 'not.is.null'},
          order: 'at.desc',
          limit: 300);
      if (!mounted || notesKey != key) return;
      final seen = <String>{};
      final out = <String>[];
      for (final row in rows) {
        final n = '${row['note'] ?? ''}'.trim();
        if (n.isNotEmpty && seen.add(n.toLowerCase())) out.add(n);
      }
      setState(() => notes = out);
    } catch (_) {
      // Suggestions only help; a note can always be typed.
    }
  }

  void _resetRate() {
    final r = foreign ? Me.instance.rateOf(currency) : null;
    rateCtl.text = r == null ? '' : rateText(r);
  }

  /// A text field's controller, let go once the field has left the screen.
  void _disposeLater(TextEditingController c) => WidgetsBinding.instance.addPostFrameCallback((_) => c.dispose());

  void _dropParts() {
    for (final p in parts) {
      _disposeLater(p.note);
    }
    parts.clear();
    splitting = false;
  }

  void _clearPlan() {
    freq = null;
    every = 1;
    endsOn = null;
    months = null;
  }

  // ---------------------------------------------------------------- choosing

  void _setKind(String k) {
    if (k == kind) return;
    setState(() {
      kind = k;
      if (_categoryOk(categoryId) == null) categoryId = null;
      if (k == 'transfer') {
        _dropParts();
        if (toAccountId == accountId) toAccountId = null;
      } else {
        for (final p in parts) {
          if (Me.instance.category(p.categoryId)?.kind != k) p.categoryId = null;
        }
      }
      if (k == 'income') months = null;
      toAmount = null;
    });
    _loadNotes();
  }

  Future<void> _tapAmount() async {
    final v = await showCalculator(context, start: amount > 0 ? amount : null, currency: currency, title: 'Amount');
    if (v == null || !mounted) return;
    if (v < 0) {
      toast(context, 'Enter the amount above 0. Income, Expense or Transfer says which way it goes.', bad: true);
      return;
    }
    setState(() => amount = v);
  }

  Future<void> _tapDate() async {
    final d = await pickDate(context, initial: at, title: 'Date');
    if (d == null || !mounted) return;
    setState(() {
      at = DateTime(d.year, d.month, d.day, at.hour, at.minute);
      final e = endsOn;
      if (e != null && e.isBefore(dayOnly(at))) endsOn = null;
    });
  }

  Future<void> _tapTime() async {
    final t = await _pickTime(context, at);
    if (t == null || !mounted) return;
    setState(() => at = DateTime(at.year, at.month, at.day, t.$1, t.$2));
  }

  Future<void> _tapRepeat() async {
    if (splitting) {
      toast(context, 'A split entry cannot repeat. Remove the split first.', bad: true);
      return;
    }
    final current = months != null ? 'inst' : (freq == null ? 'none' : '$freq$every');
    final p = await showPicker<String>(context, title: 'Repeat', selected: current, options: [
      const PickOption<String>('none', 'None', sub: 'Just this once'),
      const PickOption<String>('day1', 'Every day'),
      const PickOption<String>('week1', 'Every week'),
      const PickOption<String>('week2', 'Every 2 weeks'),
      const PickOption<String>('month1', 'Every month'),
      const PickOption<String>('year1', 'Every year'),
      if (kind != 'income') const PickOption<String>('inst', 'Instalment', sub: 'Spread the amount over 2 to 36 months'),
    ]);
    if (p == null || !mounted) return;
    final v = p.value;
    if (v == 'none') {
      setState(_clearPlan);
      return;
    }
    if (v == 'inst') {
      final m = await showPicker<int>(context, title: 'Instalment', selected: months, options: [
        for (var n = 2; n <= 36; n++) PickOption<int>(n, '$n months', sub: amount > 0 ? '${money(amount / n, currency)} a month' : null),
      ]);
      if (m == null || !mounted) return;
      setState(() {
        _clearPlan();
        months = m.value;
      });
      return;
    }
    final f = v.replaceAll(RegExp(r'[0-9]'), '');
    final e = int.tryParse(v.replaceAll(RegExp(r'[^0-9]'), '')) ?? 1;
    final ends = endsOn;
    final end = await showPicker<String>(context, title: 'Ends', selected: ends == null ? 'never' : 'date', options: [
      const PickOption<String>('never', 'No end date', sub: 'Keeps going until it is stopped'),
      PickOption<String>('date', 'On a date', sub: ends == null ? 'Pick the last day' : 'Until ${dateLabel(ends)}'),
    ]);
    if (end == null || !mounted) return;
    DateTime? until;
    if (end.value == 'date') {
      final start = dayOnly(at);
      until = await pickDate(context, initial: ends ?? DateTime(start.year + 1, start.month, start.day), first: start, title: 'Last day');
      if (until == null || !mounted) return;
    }
    setState(() {
      _clearPlan();
      freq = f;
      every = e;
      endsOn = until;
    });
  }

  Future<void> _tapAccount({bool to = false}) async {
    final current = to ? toAccountId : accountId;
    final other = isTransfer ? (to ? accountId : toAccountId) : null;
    final list = [
      for (final a in _pickable(current))
        if (a.id != other) a,
    ];
    final p = await showPicker<String>(
      context,
      title: to ? 'To account' : (isTransfer ? 'From account' : 'Account'),
      selected: current,
      search: true,
      options: [for (final a in list) PickOption<String>(a.id, a.name, sub: a.group?.label ?? 'Accounts', trailing: a.currency)],
    );
    if (p == null || !mounted) return;
    setState(() {
      if (to) {
        toAccountId = p.value;
      } else {
        final before = currency;
        accountId = p.value;
        if (currency != before) _resetRate();
      }
      toAmount = null;
    });
  }

  void _swap() {
    setState(() {
      final before = currency;
      final a = accountId;
      accountId = toAccountId;
      toAccountId = a;
      toAmount = null;
      if (currency != before) _resetRate();
    });
  }

  String? _subsLine(String id) {
    final s = Me.instance.subsOf(id);
    if (s.isEmpty) return null;
    final names = s.take(3).map((c) => c.name).join(', ');
    return s.length > 3 ? '$names and ${s.length - 3} more' : names;
  }

  /// A category in two steps: the category, then its subcategory when the
  /// book uses them. '' for no category, null when nothing was picked.
  Future<String?> _chooseCategory(String? current) async {
    final tops = Me.instance.topCategories(kind);
    final cur = Me.instance.category(current);
    final topId = cur?.parentId ?? cur?.id;
    final subsOn = book.subcategories;
    final p = await showPicker<String>(
      context,
      title: kind == 'income' ? 'Income category' : 'Expense category',
      selected: topId,
      search: tops.length > 10,
      options: [
        for (final c in tops) PickOption<String>(c.id, c.label, sub: subsOn ? _subsLine(c.id) : null),
        const PickOption<String>('', 'No category'),
      ],
    );
    if (p == null || !mounted) return null;
    if (p.value.isEmpty) return '';
    if (!subsOn) return p.value;
    final subs = Me.instance.subsOf(p.value);
    if (subs.isEmpty) return p.value;
    final top = Me.instance.category(p.value);
    final s = await showPicker<String>(context, title: top?.label ?? 'Subcategory', selected: current, options: [
      PickOption<String>(p.value, 'No subcategory', sub: top == null ? null : 'Just ${top.name}'),
      for (final c in subs) PickOption<String>(c.id, c.label),
    ]);
    // Closing the second list keeps what was there, or the category alone.
    return s?.value ?? (topId == p.value && current != null ? current : p.value);
  }

  Future<void> _tapCategory() async {
    final id = await _chooseCategory(categoryId);
    if (id == null || !mounted) return;
    setState(() => categoryId = id.isEmpty ? null : id);
    _loadNotes();
  }

  void _startSplit() {
    setState(() {
      splitting = true;
      parts
        ..add(_Part(categoryId: categoryId))
        ..add(_Part());
    });
  }

  void _endSplit() {
    setState(() {
      final first = parts.isEmpty ? null : parts.first.categoryId;
      if (first != null) categoryId = first;
      _dropParts();
    });
    _loadNotes();
  }

  void _addPart() => setState(() => parts.add(_Part()));

  void _removePart(_Part p) {
    final wasFirst = parts.isNotEmpty && identical(parts.first, p);
    setState(() => parts.remove(p));
    _disposeLater(p.note);
    if (wasFirst) _loadNotes();
  }

  Future<void> _tapPartCategory(_Part p) async {
    final id = await _chooseCategory(p.categoryId);
    if (id == null || !mounted) return;
    setState(() => p.categoryId = id.isEmpty ? null : id);
    if (parts.isNotEmpty && identical(parts.first, p)) _loadNotes();
  }

  Future<void> _tapPartAmount(_Part p) async {
    final rest = left;
    final v = await showCalculator(context,
        start: p.amount > 0 ? p.amount : (rest > 0 ? rest : null), currency: currency, title: 'Amount of this part');
    if (v == null || !mounted) return;
    if (v < 0) {
      toast(context, 'Enter an amount above 0.', bad: true);
      return;
    }
    setState(() => p.amount = v);
  }

  Future<void> _tapFee() async {
    final v = await showCalculator(context, start: fee > 0 ? fee : null, currency: currency, title: 'Fees');
    if (v == null || !mounted) return;
    if (v < 0) {
      toast(context, 'Fees cannot be below 0.', bad: true);
      return;
    }
    setState(() => fee = v);
  }

  Future<void> _tapReceived() async {
    final tc = toCurrency;
    if (tc == null) return;
    final v = await showCalculator(context, start: received, currency: tc, title: 'Received in $tc');
    if (v == null || !mounted) return;
    if (v < 0) {
      toast(context, 'Enter an amount above 0.', bad: true);
      return;
    }
    setState(() => toAmount = v > 0 ? v : null);
  }

  // ---------------------------------------------------------------- tags

  void _addTag(String raw, {bool clear = true}) {
    var t = raw.trim().replaceFirst(RegExp(r'^#+'), '').trim();
    if (t.length > 30) t = t.substring(0, 30).trim();
    setState(() {
      if (t.isNotEmpty && !tags.any((x) => x.toLowerCase() == t.toLowerCase())) {
        final known = [for (final g in Me.instance.tags) '${g['name'] ?? ''}'].where((n) => n.toLowerCase() == t.toLowerCase()).firstOrNull;
        tags.add(known ?? t);
      }
      if (clear) tagCtl.clear();
    });
  }

  /// A comma ends a tag, so several can be typed in a row.
  void _tagTyped(String v) {
    if (v.contains(',')) {
      final bits = v.split(',');
      for (final b in bits.take(bits.length - 1)) {
        _addTag(b, clear: false);
      }
      tagCtl.text = bits.last;
      tagCtl.selection = TextSelection.collapsed(offset: tagCtl.text.length);
    }
    setState(() {});
  }

  // ---------------------------------------------------------------- photos

  Future<void> _addPhotos() async {
    final src = await showPicker<String>(context, title: 'Add photo', options: const [
      PickOption<String>('camera', 'Take a photo', icon: Icons.photo_camera_outlined),
      PickOption<String>('gallery', 'From the gallery', sub: 'Pick one or several', icon: Icons.photo_library_outlined),
    ]);
    if (src == null || !mounted) return;
    try {
      final picker = ImagePicker();
      final files = <XFile>[];
      if (src.value == 'camera') {
        final f = await picker.pickImage(source: ImageSource.camera, imageQuality: 70, maxWidth: 1600);
        if (f != null) files.add(f);
      } else {
        files.addAll(await picker.pickMultiImage(imageQuality: 70, maxWidth: 1600));
      }
      final fresh = <_Photo>[];
      for (final f in files) {
        fresh.add(_Photo(bytes: await f.readAsBytes(), mime: f.mimeType));
      }
      if (!mounted || fresh.isEmpty) return;
      setState(() => photos.addAll(fresh));
    } catch (_) {
      if (mounted) toast(context, 'The photo could not be added. Check that Monee may use the camera and photos.', bad: true);
    }
  }

  Future<void> _loadPhoto(_Photo p) async {
    final path = p.path;
    if (path == null) return;
    try {
      final b = await Api.instance.download('monee-photos', path);
      if (!mounted) return;
      setState(() => p.bytes = b is Uint8List ? b : Uint8List.fromList(b));
    } catch (_) {
      if (mounted) setState(() => p.failed = true);
    }
  }

  void _viewPhoto(Uint8List b) {
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute<void>(builder: (_) => _PhotoView(b)));
  }

  Future<void> _deletePhoto(_Photo p) async {
    final id = p.id;
    if (id == null) {
      setState(() => photos.remove(p));
      return;
    }
    final ok = await confirm(context, title: 'Delete this photo?', text: 'It is taken off this entry for good.', yes: 'Delete', danger: true);
    if (!ok || !mounted) return;
    try {
      await Api.instance.delete('txn_photos', where: {'id': 'eq.$id'});
      if (!mounted) return;
      setState(() => photos.remove(p));
      touched = true;
      unawaited(Me.instance.changed());
    } on ApiError catch (e) {
      if (mounted) toast(context, e.message, bad: true);
    }
  }

  /// New photos into storage and onto the entry. A failed upload never undoes
  /// the entry: it is counted and told.
  Future<int> _uploadPhotos(String txnId) async {
    var failed = 0;
    for (final p in photos.where((x) => x.id == null && x.bytes != null).toList()) {
      try {
        final path = '${book.id}/$txnId/${_randomName()}.jpg';
        await Api.instance.upload('monee-photos', path, p.bytes!, p.mime ?? 'image/jpeg');
        await Api.instance.insert('txn_photos', {'txn_id': txnId, 'path': path});
      } catch (_) {
        failed++;
      }
    }
    return failed;
  }

  // ---------------------------------------------------------------- saving

  String? _problem() {
    if (accountId == null || account == null) return isTransfer ? 'Pick the account the money comes from.' : 'Pick an account.';
    if (amount <= 0) return 'Enter an amount above 0.';
    if (isTransfer) {
      if (toAccountId == null || toAccount == null) return 'Pick the account the money goes to.';
      if (toAccountId == accountId) return 'A transfer goes to a different account.';
      final r = received;
      if (twoCurrencies && (r == null || r <= 0)) return 'Enter how much arrived in ${toCurrency ?? ''}.';
    }
    if (foreign && rate == null) return 'Enter the rate: how much 1 $currency is in ${book.currency}.';
    if (!isTransfer && splitting) {
      if (parts.length < 2) return 'A split needs at least two parts.';
      if (parts.any((p) => p.amount <= 0)) return 'Give every part an amount above 0.';
      if (!splitDone) return 'The parts add up to ${money(_round(amount) - left, currency)}, not ${money(amount, currency)}.';
    }
    final e = endsOn;
    if (freq != null && e != null && e.isBefore(dayOnly(at))) return 'The repeat ends before it starts.';
    return null;
  }

  /// The entry as save_txn takes it.
  Map<String, dynamic> _payload() {
    final n = note.text.trim();
    final d = description.text.trim();
    final r = received;
    return {
      if (editId != null) 'id': editId,
      'kind': kind,
      'at': isoStamp(at),
      'account_id': accountId,
      'to_account_id': isTransfer ? toAccountId : null,
      'category_id': isTransfer ? null : mainCategory,
      'amount': _round(amount),
      'to_amount': twoCurrencies && r != null ? _round(r, toCurrency) : null,
      'fee': isTransfer ? _round(fee) : 0,
      'rate': foreign ? rate : null,
      'note': n.isEmpty ? null : n,
      'description': d.isEmpty ? null : d,
      'splits': [
        if (!isTransfer && splitting)
          for (final p in parts)
            {
              'category_id': p.categoryId,
              'amount': _round(p.amount),
              'note': p.note.text.trim().isEmpty ? null : p.note.text.trim(),
            },
      ],
      'tags': List<String>.of(tags),
    };
  }

  /// Saves, then closes; with `more` (Continue) it stays for the next entry,
  /// on the same kind, account and day.
  Future<void> _save({bool more = false}) async {
    if (busy) return;
    FocusScope.of(context).unfocus();
    final problem = _problem();
    if (problem != null) {
      toast(context, problem, bad: true);
      return;
    }
    setState(() => busy = true);
    final p = _payload();
    final known = {for (final g in Me.instance.tags) '${g['name'] ?? ''}'.toLowerCase()};
    var lists = tags.any((t) => !known.contains(t.toLowerCase()));
    // A rate the book did not have yet is kept for next time (repeats need it too).
    final rt = rate;
    if (foreign && rt != null && Me.instance.rates[currency] == null) {
      try {
        await Api.instance.insert('currency_rates', {'currency': currency, 'rate': rt});
        lists = true;
      } catch (_) {
        // The entry carries its own rate either way.
      }
    }
    String? id;
    String? message;
    try {
      if (!editing && freq != null) {
        final r = await Api.instance.rpc('add_repeat', {
          'p': p,
          'freq': freq,
          'every': every,
          'ends_on': endsOn == null ? null : isoDay(endsOn!),
        });
        final rid = r is Map ? r['repeat_id'] as String? : null;
        final recorded = r is Map ? toNum(r['recorded']).toInt() : 0;
        if (rid != null && recorded > 0) {
          final first = await Api.instance.select('txns', columns: 'id', where: {'repeat_id': 'eq.$rid'}, order: 'at.asc', limit: 1);
          id = first.isEmpty ? null : first.first['id'] as String?;
        }
        if (id != null && tags.isNotEmpty) {
          try {
            await Api.instance.rpc('save_txn', {
              'p': {'id': id, 'tags': List<String>.of(tags)},
            });
          } catch (_) {
            // The repeat is saved; its tags are a nicety.
          }
        }
        if (recorded > 1) {
          message = 'Repeat saved. $recorded entries are recorded up to today.';
        } else if (recorded == 0) {
          message = photos.any((x) => x.id == null)
              ? 'Repeat saved. Its first entry comes on ${dateLabel(at)}; add the photos to it then.'
              : 'Repeat saved. Its first entry comes on ${dateLabel(at)}.';
        }
      } else if (!editing && months != null) {
        // Each month gets its share; what arrives is worked out per month from the rates.
        final q = Map<String, dynamic>.of(p)
          ..remove('to_amount')
          ..remove('splits');
        final r = await Api.instance.rpc('add_instalments', {'p': q, 'months': months});
        final ids = r is Map ? r['ids'] : null;
        id = ids is List && ids.isNotEmpty ? '${ids.first}' : null;
      } else {
        final r = await Api.instance.rpc('save_txn', {'p': p});
        id = r is Map ? r['id'] as String? : null;
      }
    } on ApiError catch (e) {
      if (mounted) {
        setState(() => busy = false);
        toast(context, e.message, bad: true);
      }
      return;
    } catch (_) {
      if (mounted) {
        setState(() => busy = false);
        toast(context, 'That did not save. Check the list before trying again.', bad: true);
      }
      return;
    }

    // Saved. Nothing below may lose it.
    touched = true;
    _lastAccountId = accountId;
    _lastDay = dayOnly(at);
    final failed = id == null ? 0 : await _uploadPhotos(id);
    await Me.instance.changed(lists: lists);
    if (!mounted) return;
    if (failed > 0) {
      toast(
          context,
          failed == 1
              ? 'Saved, but a photo did not upload. Open the entry and add it again.'
              : 'Saved, but $failed photos did not upload. Open the entry and add them again.',
          bad: true);
    } else if (message != null) {
      toast(context, message);
    } else if (more) {
      toast(context, 'Saved');
    }
    if (!more) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      busy = false;
      amount = 0;
      categoryId = null;
      fee = 0;
      toAmount = null;
      note.clear();
      description.clear();
      tags.clear();
      tagCtl.clear();
      _dropParts();
      photos.clear();
      _clearPlan();
      notesKey = null;
    });
    baseline = _signature();
    _loadNotes();
  }

  Future<void> _bookmark() async {
    final n = note.text.trim();
    final d = description.text.trim();
    try {
      await Api.instance.insert('bookmarks', {
        'kind': kind,
        'account_id': accountId,
        'to_account_id': isTransfer ? toAccountId : null,
        'category_id': isTransfer ? null : mainCategory,
        'amount': amount > 0 ? _round(amount) : null,
        'fee': isTransfer ? _round(fee) : 0,
        'note': n.isEmpty ? null : n,
        'description': d.isEmpty ? null : d,
      });
      if (!mounted) return;
      toast(context, 'Added to bookmarks');
      unawaited(Me.instance.changed());
    } on ApiError catch (e) {
      if (mounted) toast(context, e.message, bad: true);
    }
  }

  Future<void> _delete() async {
    final id = editId;
    if (id == null) return;
    var whole = false;
    final pid = planId;
    if (pid != null) {
      final n = planNo;
      final m = planMonths;
      final p = await showPicker<String>(context, title: 'Delete instalment', options: [
        PickOption<String>('one', 'Just this month', sub: n != null && m != null ? 'Instalment $n of $m' : null),
        PickOption<String>('all', 'The whole plan', sub: m != null ? 'All $m months' : 'Every month of it'),
      ]);
      if (p == null || !mounted) return;
      whole = p.value == 'all';
    }
    final ok = await confirm(
      context,
      title: whole ? 'Delete the whole plan?' : 'Delete this entry?',
      text: whole ? 'Every month of this instalment goes from every list and total.' : 'It goes from every list and total.',
      yes: 'Delete',
      danger: true,
    );
    if (!ok || !mounted) return;
    setState(() => busy = true);
    try {
      if (whole && pid != null) {
        await Api.instance.delete('instalment_plans', where: {'id': 'eq.$pid'});
      } else {
        await Api.instance.delete('txns', where: {'id': 'eq.$id'});
      }
      touched = true;
      await Me.instance.changed();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiError catch (e) {
      if (mounted) {
        setState(() => busy = false);
        toast(context, e.message, bad: true);
      }
    }
  }

  /// A new entry filled from this one (as it is saved).
  Future<void> _copy() async {
    final t = widget.txn;
    if (t == null) return;
    final saved = await openEntry(context, txn: t, copy: true);
    if (!saved || !mounted) return;
    Navigator.of(context).pop(true);
  }

  Future<void> _close() async {
    if (busy) return;
    if (_dirty) {
      final leave = await confirm(context,
          title: 'Leave without saving?', text: 'What you changed here is not saved yet.', yes: 'Leave', no: 'Stay', danger: true);
      if (!leave || !mounted) return;
    }
    Navigator.of(context).pop(touched);
  }

  // ---------------------------------------------------------------- the page

  @override
  Widget build(BuildContext context) {
    final Widget body;
    if (loading) {
      body = const Loading();
    } else if (loadError != null) {
      body = LoadFailed(
        message: loadError!,
        onRetry: () {
          setState(() {
            loading = true;
            loadError = null;
          });
          _start();
        },
      );
    } else {
      body = _form();
    }
    final title = !canEdit ? 'Entry' : '${editing ? 'Edit' : 'New'} $kind';
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(tooltip: 'Close', icon: const Icon(Icons.close_rounded), onPressed: _close),
          title: Text(title),
        ),
        body: body,
        bottomNavigationBar: loading || loadError != null || !canEdit ? null : _actions(),
      ),
    );
  }

  Widget _actions() {
    return Container(
      decoration: const BoxDecoration(color: K.surface, border: Border(top: BorderSide(color: K.border))),
      child: SafeArea(
        top: false,
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560 + 2 * Sp.page),
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(Sp.page - 6, 10, Sp.page, 10),
              child: Row(children: [
                RoundIcon(Icons.star_border_rounded, tooltip: 'Bookmark', onTap: busy ? null : _bookmark),
                if (editing) RoundIcon(Icons.content_copy_rounded, tooltip: 'Copy', onTap: busy ? null : _copy),
                if (editing) RoundIcon(Icons.delete_outline_rounded, tooltip: 'Delete', color: K.bad, onTap: busy ? null : _delete),
                const Spacer(),
                if (!editing) ...[
                  KButton(label: 'Continue', kind: KButtonKind.secondary, onPressed: busy ? null : () => _save(more: true)),
                  const SizedBox(width: Sp.sm),
                ],
                KButton(label: 'Save', busy: busy, onPressed: () => _save()),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _form() {
    final can = canEdit;
    final cur = currencyOf(currency);
    const gap = SizedBox(height: Sp.md);
    final plan = planText;
    final info = <Widget>[
      if (plan != null)
        _Chip(label: plan, icon: Icons.repeat_rounded, selected: true, onTap: can ? _tapRepeat : null, onClear: can ? () => setState(_clearPlan) : null),
      if (repeatText != null) Pill(repeatText!, icon: Icons.repeat_rounded),
      if (planNo != null) Pill(_planLine(), icon: Icons.date_range_outlined),
    ];
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(Sp.page, Sp.sm, Sp.page, Sp.xxl + Sp.lg),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (!can) ...[const Notice('You can only look at this book. Ask its owner if something needs changing.', bad: false), gap],
              if (can && !editing && Me.instance.liveAccounts.isEmpty) ...[const Notice('Add an account first, in the Accounts tab.'), gap],
              _KindSwitch(value: kind, onChanged: can ? _setKind : null),
              gap,
              _amountCard(cur, can),
              gap,
              _dateRow(can),
              if (info.isNotEmpty) ...[const SizedBox(height: Sp.sm), Wrap(spacing: 6, runSpacing: 6, children: info)],
              gap,
              _accountRows(can),
              gap,
              if (!isTransfer) (splitting ? _splitCard(can, cur) : _categoryRow(can)),
              if (isTransfer) _transferMoney(can, cur),
              if (foreign) ...[gap, _rateRow(can)],
              const SizedBox(height: Sp.lg),
              KField(
                label: 'Note',
                controller: note,
                hint: 'Optional',
                enabled: can,
                formatters: [LengthLimitingTextInputFormatter(120)],
                onChanged: (_) => setState(() {}),
              ),
              if (can) _noteSuggestions(),
              gap,
              KField(
                label: 'Description',
                controller: description,
                hint: 'Optional',
                enabled: can,
                maxLines: 4,
                keyboard: TextInputType.multiline,
                formatters: [LengthLimitingTextInputFormatter(2000)],
              ),
              const SizedBox(height: Sp.lg),
              _tagsBlock(can),
              const SizedBox(height: Sp.lg),
              _photosBlock(can),
            ]),
          ),
        ),
      ],
    );
  }

  /// Instalment 2 of 6, 400.00 still to come.
  String _planLine() {
    final n = planNo ?? 1;
    final m = planMonths;
    if (m == null) return 'Instalment $n';
    if (n >= m) return 'Instalment $n of $m, the last one';
    final total = planTotal;
    if (total == null) return 'Instalment $n of $m';
    final part = (total / m * 100).truncate() / 100;
    return 'Instalment $n of $m, ${money(part * (m - n), currency)} still to come';
  }

  Widget _amountCard(Currency cur, bool can) {
    final has = amount > 0;
    final rt = rate;
    final m = months;
    final lines = <String>[
      if (foreign && has && rt != null) '= ${money(amount * rt, book.currency)}',
      if (m != null && has) '${money(amount / m, currency)} a month for $m months',
    ];
    return Material(
      color: K.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(K.r), side: const BorderSide(color: K.border)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: can ? _tapAmount : null,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 14, 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Expanded(child: Text('Amount', style: T.tiny)),
              Pill.grey(cur.code),
              if (can) ...[const SizedBox(width: 6), const Icon(Icons.calculate_outlined, size: 18, color: K.muted)],
            ]),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                cur.format(amount),
                maxLines: 1,
                style: T.display.copyWith(fontSize: 34, color: has ? moneyColor(kind) : K.border2).merge(T.tabular),
              ),
            ),
            for (final l in lines) ...[const SizedBox(height: 3), Text(l, style: T.small)],
          ]),
        ),
      ),
    );
  }

  Widget _dateRow(bool can) {
    final now = DateTime.now();
    final date = at.year == now.year ? dayLabel(at) : '${dayLabel(at)} ${at.year}';
    return Row(children: [
      Expanded(
        child: _FieldRow(
          label: 'Date',
          value: date,
          icon: Icons.event_outlined,
          onTap: can ? _tapDate : null,
          trailing: can && !editing ? _TinyButton('Repeat', icon: Icons.repeat_rounded, onTap: _tapRepeat) : null,
        ),
      ),
      const SizedBox(width: Sp.sm),
      _FieldRow(label: 'Time', value: clock(at), compact: true, onTap: can ? _tapTime : null),
    ]);
  }

  Widget _accountRows(bool can) {
    Widget row(String label, Account? a, VoidCallback? onTap) => _FieldRow(
          label: label,
          value: a?.name ?? 'Pick an account',
          muted: a == null,
          icon: Icons.account_balance_wallet_outlined,
          trailing: a == null ? null : Pill.grey(a.currency),
          onTap: onTap,
        );
    if (!isTransfer) return row('Account', account, can ? () => _tapAccount() : null);
    return Row(children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          row('From', account, can ? () => _tapAccount() : null),
          const SizedBox(height: Sp.sm),
          row('To', toAccount, can ? () => _tapAccount(to: true) : null),
        ]),
      ),
      if (can) ...[
        const SizedBox(width: 2),
        RoundIcon(Icons.swap_vert_rounded, tooltip: 'Swap From and To', onTap: _swap),
      ],
    ]);
  }

  Widget _categoryRow(bool can) => _FieldRow(
        label: 'Category',
        value: categoryId == null ? 'Pick a category' : Me.instance.categoryPath(categoryId),
        muted: categoryId == null,
        icon: Icons.category_outlined,
        onTap: can ? _tapCategory : null,
        trailing: can && !hasPlan ? _TinyButton('Split', icon: Icons.call_split_rounded, onTap: _startSplit) : null,
      );

  Widget _splitCard(bool can, Currency cur) {
    final l = left;
    final done = splitDone;
    final status = done ? 'All split' : (l > 0 ? 'Left to split ${cur.format(l)}' : 'Over by ${cur.format(-l)}');
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 8, 4),
      decoration: BoxDecoration(color: K.surface, borderRadius: BorderRadius.circular(K.r), border: Border.all(color: K.border2)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Icons.call_split_rounded, size: 18, color: K.ink2),
          const SizedBox(width: 8),
          const Text('Split', style: T.label),
          const SizedBox(width: Sp.sm),
          Expanded(
            child: Text(status,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: T.tiny.copyWith(color: done ? K.income : K.bad).merge(T.tabular)),
          ),
          const SizedBox(width: 4),
        ]),
        const SizedBox(height: Sp.sm),
        for (var i = 0; i < parts.length; i++) _partRow(i, can, cur),
        if (can)
          Row(children: [
            _TinyButton('Add part', icon: Icons.add_rounded, onTap: _addPart),
            const Spacer(),
            _TinyButton('Remove split', color: K.muted, onTap: _endSplit),
          ]),
      ]),
    );
  }

  Widget _partRow(int i, bool can, Currency cur) {
    final p = parts[i];
    return Padding(
      key: ObjectKey(p),
      padding: const EdgeInsetsDirectional.only(end: 4, bottom: Sp.sm),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: _FieldRow(
              label: 'Part ${i + 1}',
              value: p.categoryId == null ? 'Pick a category' : Me.instance.categoryPath(p.categoryId),
              muted: p.categoryId == null,
              onTap: can ? () => _tapPartCategory(p) : null,
            ),
          ),
          const SizedBox(width: 6),
          _FieldRow(label: 'Amount', value: cur.format(p.amount), compact: true, muted: p.amount <= 0, onTap: can ? () => _tapPartAmount(p) : null),
          if (can && parts.length > 2) RoundIcon(Icons.close_rounded, size: 28, tooltip: 'Remove this part', onTap: () => _removePart(p)),
        ]),
        const SizedBox(height: 6),
        TextField(
          controller: p.note,
          enabled: can,
          style: T.body.copyWith(fontSize: 14),
          textCapitalization: TextCapitalization.sentences,
          inputFormatters: [LengthLimitingTextInputFormatter(120)],
          decoration: const InputDecoration(
            hintText: 'Note for this part',
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
      ]),
    );
  }

  Widget _transferMoney(bool can, Currency cur) {
    final r = received;
    final tc = toCurrency;
    final two = twoCurrencies && tc != null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(
          child: _FieldRow(
            label: 'Fees',
            value: fee > 0 ? cur.format(fee) : 'None',
            muted: fee <= 0,
            icon: Icons.receipt_outlined,
            onTap: can ? _tapFee : null,
          ),
        ),
        if (two) ...[
          const SizedBox(width: Sp.sm),
          Expanded(
            child: _FieldRow(
              label: 'Received in $tc',
              value: r == null ? 'Enter it' : money(r, tc),
              muted: r == null,
              onTap: can ? _tapReceived : null,
            ),
          ),
        ],
      ]),
      if (two && toAmount == null && r != null)
        const Padding(
          padding: EdgeInsetsDirectional.only(start: 4, top: 6),
          child: Text('Received is worked out from the rates. Tap it to change.', style: T.tiny),
        ),
    ]);
  }

  Widget _rateRow(bool can) {
    final known = Me.instance.rates[currency] != null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsetsDirectional.fromSTEB(12, 7, 12, 7),
        decoration: BoxDecoration(color: K.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: K.border2)),
        child: Row(children: [
          const Icon(Icons.currency_exchange_rounded, size: 18, color: K.ink2),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              const Text('Rate', style: T.tiny),
              Row(children: [
                Text('1 $currency =', style: T.bodyStrong.copyWith(fontSize: 14)),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: rateCtl,
                    enabled: can,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')), LengthLimitingTextInputFormatter(16)],
                    onChanged: (_) => setState(() {}),
                    textAlign: TextAlign.end,
                    style: T.bodyStrong.copyWith(fontSize: 14).merge(T.tabular),
                    decoration: const InputDecoration(
                      hintText: 'Rate',
                      isDense: true,
                      filled: false,
                      contentPadding: EdgeInsets.symmetric(vertical: 4),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(book.currency, style: T.bodyStrong.copyWith(fontSize: 14)),
              ]),
            ]),
          ),
        ]),
      ),
      if (!known && can) ...[
        const SizedBox(height: 6),
        Notice('There is no rate for $currency yet. Enter how much 1 $currency is in ${book.currency}; Monee keeps it for next time.', bad: false),
      ],
    ]);
  }

  Widget _noteSuggestions() {
    final t = note.text.trim().toLowerCase();
    final list = notes.where((n) {
      final x = n.toLowerCase();
      return x != t && (t.isEmpty || x.contains(t));
    }).take(8).toList();
    if (list.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: Sp.sm),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (final n in list)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 6),
              child: _Chip(
                label: n,
                onTap: () => setState(() {
                  note.text = n;
                  note.selection = TextSelection.collapsed(offset: n.length);
                }),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _tagsBlock(bool can) {
    final typed = tagCtl.text.trim().replaceFirst(RegExp(r'^#+'), '').toLowerCase();
    final have = {for (final t in tags) t.toLowerCase()};
    final suggestions = [
      for (final g in Me.instance.tags) '${g['name'] ?? ''}',
    ].where((n) => n.isNotEmpty && !have.contains(n.toLowerCase()) && (typed.isEmpty || n.toLowerCase().contains(typed))).take(8).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Padding(padding: EdgeInsetsDirectional.only(start: 2, bottom: 6), child: Text('Tags', style: T.label)),
      if (tags.isNotEmpty)
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final t in tags)
            _Chip(label: '#$t', selected: true, onClear: can ? () => setState(() => tags.remove(t)) : null),
        ]),
      if (tags.isEmpty && !can) const Text('None', style: T.small),
      if (can) ...[
        if (tags.isNotEmpty) const SizedBox(height: Sp.sm),
        TextField(
          controller: tagCtl,
          style: T.bodyStrong,
          textInputAction: TextInputAction.done,
          inputFormatters: [LengthLimitingTextInputFormatter(40)],
          onChanged: _tagTyped,
          onSubmitted: (v) => _addTag(v),
          decoration: InputDecoration(
            hintText: 'Add a tag',
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            prefixIcon: const Icon(Icons.sell_outlined, size: 18, color: K.muted),
            suffixIcon: tagCtl.text.trim().isEmpty
                ? null
                : IconButton(tooltip: 'Add tag', icon: const Icon(Icons.add_rounded, color: K.blue), onPressed: () => _addTag(tagCtl.text)),
          ),
        ),
        if (suggestions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: Sp.sm),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final n in suggestions)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 6),
                    child: _Chip(label: '#$n', onTap: () => _addTag(n)),
                  ),
              ]),
            ),
          ),
      ],
    ]);
  }

  Widget _photosBlock(bool can) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Padding(padding: EdgeInsetsDirectional.only(start: 2, bottom: 6), child: Text('Photos', style: T.label)),
      if (photos.isEmpty && !can)
        const Text('None', style: T.small)
      else
        SizedBox(
          height: 72,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            for (final p in photos) Padding(padding: const EdgeInsetsDirectional.only(end: Sp.sm), child: _thumb(p, can)),
            if (can) _addPhotoTile(),
          ]),
        ),
      if (can && photos.isNotEmpty)
        const Padding(
          padding: EdgeInsetsDirectional.only(start: 2, top: 6),
          child: Text('Tap a photo to see it. Hold it, or tap its x, to delete it.', style: T.tiny),
        ),
    ]);
  }

  Widget _thumb(_Photo p, bool can) {
    final b = p.bytes;
    final Widget inside;
    if (b != null) {
      inside = Image.memory(
        b,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (context, error, stack) => const Center(child: Icon(Icons.broken_image_outlined, size: 20, color: K.muted)),
      );
    } else if (p.failed) {
      inside = const Center(child: Icon(Icons.broken_image_outlined, size: 20, color: K.muted));
    } else {
      inside = const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)));
    }
    return SizedBox(
      width: 72,
      height: 72,
      child: Stack(children: [
        Positioned.fill(
          child: Material(
            color: K.surface2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(K.rSm), side: const BorderSide(color: K.border)),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: b == null ? null : () => _viewPhoto(b),
              onLongPress: can ? () => _deletePhoto(p) : null,
              child: inside,
            ),
          ),
        ),
        if (can)
          PositionedDirectional(
            top: 4,
            end: 4,
            child: Semantics(
              button: true,
              label: 'Delete photo',
              child: GestureDetector(
                onTap: () => _deletePhoto(p),
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: const BoxDecoration(color: Color(0x99000000), shape: BoxShape.circle),
                  child: const Icon(Icons.close_rounded, size: 14, color: Colors.white),
                ),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _addPhotoTile() {
    return SizedBox(
      width: 72,
      height: 72,
      child: Material(
        color: K.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(K.rSm), side: const BorderSide(color: K.border2)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: busy ? null : _addPhotos,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.add_a_photo_outlined, size: 20, color: K.blue),
            const SizedBox(height: 4),
            Text('Add photo', maxLines: 1, overflow: TextOverflow.ellipsis, style: T.tiny.copyWith(color: K.blue, fontSize: 10.5)),
          ]),
        ),
      ),
    );
  }
}
