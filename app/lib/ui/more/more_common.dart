import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api.dart';
import '../../core/book.dart';
import '../../core/format.dart';
import '../entry/calculator.dart' show showCalculator;
import '../theme.dart';
import '../widgets.dart';

/// Small pieces the More screens share: opening a page, saving with a toast
/// on failure, the book's settings, and the little sheets that ask for a
/// name, an amount or a name with its emoji.

/// Opens a page in the More tab's own pile, so the footer stays.
Future<T?> openPage<T>(BuildContext context, Widget page) => Navigator.of(context).push<T>(MaterialPageRoute<T>(builder: (_) => page));

/// Runs a save. On failure the server's words show in a red toast and it
/// returns false.
Future<bool> attempt(BuildContext context, Future<void> Function() work, {String? done}) async {
  try {
    await work();
    if (done != null && context.mounted) toast(context, done);
    return true;
  } on ApiError catch (e) {
    if (context.mounted) toast(context, e.message, bad: true);
    return false;
  }
}

/// Changes the book's own settings (owner only), then loads the book again
/// so every period, total and list follows.
Future<bool> saveBook(BuildContext context, Map<String, dynamic> patch, {String? done}) {
  return attempt(context, () async {
    final b = Me.instance.book;
    if (b == null) return;
    await Api.instance.update('books', patch, where: {'id': 'eq.${b.id}'});
    await Me.instance.reloadBook();
  }, done: done);
}

/// Now, for deleted_at.
String nowStamp() => DateTime.now().toUtc().toIso8601String();

/// A number for a text field: 1500, 12.5, 0.044 (no grouping, no trailing zeros).
String plainNumber(num v) => v == v.roundToDouble() ? v.round().toString() : rateText(v);

/// What a person typed as a number: "1,500.50" as 1500.5.
num? readNumber(String s) {
  final t = s.trim().replaceAll(',', '').replaceAll(' ', '');
  if (t.isEmpty) return null;
  return num.tryParse(t);
}

/// Saves a new order after moving one row up (-1) or down (+1) among its
/// siblings: every sibling gets sort 10, 20, 30... and only the ones that
/// changed are written.
Future<void> saveOrder(String table, List<(String, int)> items, int index, int dir) async {
  final j = index + dir;
  if (index < 0 || index >= items.length || j < 0 || j >= items.length) return;
  final next = [...items];
  final moved = next[index];
  next[index] = next[j];
  next[j] = moved;
  final writes = <Future<void>>[];
  for (var i = 0; i < next.length; i++) {
    final want = (i + 1) * 10;
    final (id, sort) = next[i];
    if (sort != want) {
      writes.add(Api.instance.update(table, {'sort': want}, where: {'id': 'eq.$id'}).then((_) {}));
    }
  }
  await Future.wait(writes);
}

/// A row inside a LinkGroup with a switch.
class SwitchTile extends StatelessWidget {
  const SwitchTile({super.key, required this.title, this.sub, required this.value, required this.onChanged});
  final String title;
  final String? sub;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 10, 4),
        child: KSwitchRow(title: title, sub: sub, value: value, onChanged: onChanged),
      );
}

/// Up and down arrows for putting rows in order.
class MoveButtons extends StatelessWidget {
  const MoveButtons({super.key, this.onUp, this.onDown});
  final VoidCallback? onUp;
  final VoidCallback? onDown;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        RoundIcon(Icons.keyboard_arrow_up_rounded, size: 30, tooltip: 'Move up', onTap: onUp),
        RoundIcon(Icons.keyboard_arrow_down_rounded, size: 30, tooltip: 'Move down', onTap: onDown),
      ]);
}

/// A quiet line for people who can only look.
class ReadOnlyNote extends StatelessWidget {
  const ReadOnlyNote(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: Sp.sm), child: Notice(text, bad: false));
}

// ---------------------------------------------------------------- asking sheets

/// One line of text in a sheet. Returns the trimmed text, or null when closed.
Future<String?> askText(BuildContext context,
    {required String title,
    required String label,
    String initial = '',
    String? hint,
    String yes = 'Save',
    String? note,
    TextCapitalization caps = TextCapitalization.sentences,
    TextInputType? keyboard,
    int maxLength = 60,
    bool allowEmpty = false}) {
  return showKSheet<String>(context,
      title: title,
      builder: (ctx) => _TextAsk(
            label: label,
            initial: initial,
            hint: hint,
            yes: yes,
            note: note,
            caps: caps,
            keyboard: keyboard,
            maxLength: maxLength,
            allowEmpty: allowEmpty,
          ));
}

class _TextAsk extends StatefulWidget {
  const _TextAsk({
    required this.label,
    required this.initial,
    this.hint,
    required this.yes,
    this.note,
    required this.caps,
    this.keyboard,
    required this.maxLength,
    required this.allowEmpty,
  });
  final String label;
  final String initial;
  final String? hint;
  final String yes;
  final String? note;
  final TextCapitalization caps;
  final TextInputType? keyboard;
  final int maxLength;
  final bool allowEmpty;

  @override
  State<_TextAsk> createState() => _TextAskState();
}

class _TextAskState extends State<_TextAsk> {
  late final TextEditingController _c = TextEditingController(text: widget.initial);
  String? error;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _done() {
    final t = _c.text.trim();
    if (t.isEmpty && !widget.allowEmpty) {
      setState(() => error = 'Type something first.');
      return;
    }
    if (t.length > widget.maxLength) {
      setState(() => error = 'Keep it to ${widget.maxLength} characters.');
      return;
    }
    Navigator.of(context).pop(t);
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (error != null) ...[Notice(error!), const SizedBox(height: Sp.md)],
      KField(
        label: widget.label,
        controller: _c,
        hint: widget.hint,
        autofocus: true,
        caps: widget.caps,
        keyboard: widget.keyboard,
        onSubmitted: (_) => _done(),
      ),
      if (widget.note != null) ...[const SizedBox(height: Sp.sm), Text(widget.note!, style: T.small)],
      const SizedBox(height: Sp.lg),
      KButton(label: widget.yes, icon: Icons.check_rounded, expand: true, onPressed: _done),
    ]);
  }
}

/// A name with an emoji in front of it (categories, account groups).
/// Returns (name, emoji or null), or null when closed.
Future<(String, String?)?> askNameEmoji(BuildContext context,
    {required String title, String name = '', String? emoji, String yes = 'Save', int maxLength = 40, String? note}) {
  return showKSheet<(String, String?)>(context,
      title: title, builder: (ctx) => _NameEmojiAsk(name: name, emoji: emoji, yes: yes, maxLength: maxLength, note: note));
}

class _NameEmojiAsk extends StatefulWidget {
  const _NameEmojiAsk({required this.name, this.emoji, required this.yes, required this.maxLength, this.note});
  final String name;
  final String? emoji;
  final String yes;
  final int maxLength;
  final String? note;

  @override
  State<_NameEmojiAsk> createState() => _NameEmojiAskState();
}

class _NameEmojiAskState extends State<_NameEmojiAsk> {
  late final TextEditingController _name = TextEditingController(text: widget.name);
  late final TextEditingController _emoji = TextEditingController(text: widget.emoji ?? '');
  String? error;

  @override
  void dispose() {
    _name.dispose();
    _emoji.dispose();
    super.dispose();
  }

  void _done() {
    final n = _name.text.trim();
    final e = _emoji.text.trim();
    if (n.isEmpty) {
      setState(() => error = 'Give it a name.');
      return;
    }
    if (n.length > widget.maxLength) {
      setState(() => error = 'Keep the name to ${widget.maxLength} characters.');
      return;
    }
    if (e.length > 16) {
      setState(() => error = 'Use one emoji.');
      return;
    }
    Navigator.of(context).pop((n, e.isEmpty ? null : e));
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (error != null) ...[Notice(error!), const SizedBox(height: Sp.md)],
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        SizedBox(width: 84, child: KField(label: 'Emoji', controller: _emoji, hint: '🙂', caps: TextCapitalization.none)),
        const SizedBox(width: Sp.md),
        Expanded(
          child: KField(label: 'Name', controller: _name, autofocus: true, caps: TextCapitalization.sentences, onSubmitted: (_) => _done()),
        ),
      ]),
      if (widget.note != null) ...[const SizedBox(height: Sp.sm), Text(widget.note!, style: T.small)],
      const SizedBox(height: Sp.lg),
      KButton(label: widget.yes, icon: Icons.check_rounded, expand: true, onPressed: _done),
    ]);
  }
}

/// What came back from an amount sheet: the amount, or a clear.
class AmountAnswer {
  const AmountAnswer(this.amount);
  const AmountAnswer.clear() : amount = null;

  /// Null when the person asked to clear it.
  final num? amount;
}

/// An amount in a sheet, with the calculator a tap away. Returns the
/// amount, AmountAnswer.clear() when [clearLabel] was tapped, or null when
/// closed.
Future<AmountAnswer?> askAmount(BuildContext context,
    {required String title, String label = 'Amount', num? initial, String? currency, String yes = 'Save', String? note, String? clearLabel}) {
  return showKSheet<AmountAnswer>(context,
      title: title,
      builder: (ctx) => _AmountAsk(label: label, initial: initial, currency: currency, yes: yes, note: note, clearLabel: clearLabel));
}

class _AmountAsk extends StatefulWidget {
  const _AmountAsk({required this.label, this.initial, this.currency, required this.yes, this.note, this.clearLabel});
  final String label;
  final num? initial;
  final String? currency;
  final String yes;
  final String? note;
  final String? clearLabel;

  @override
  State<_AmountAsk> createState() => _AmountAskState();
}

class _AmountAskState extends State<_AmountAsk> {
  late final TextEditingController _c = TextEditingController(text: widget.initial == null || widget.initial == 0 ? '' : plainNumber(widget.initial!));
  String? error;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _calc() async {
    final v = await showCalculator(context, start: readNumber(_c.text), currency: widget.currency);
    if (v != null && mounted) setState(() => _c.text = plainNumber(v));
  }

  void _done() {
    final v = readNumber(_c.text);
    if (v == null || v < 0) {
      setState(() => error = 'Enter an amount.');
      return;
    }
    Navigator.of(context).pop(AmountAnswer(v));
  }

  @override
  Widget build(BuildContext context) {
    final cur = widget.currency == null ? null : currencyOf(widget.currency);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (error != null) ...[Notice(error!), const SizedBox(height: Sp.md)],
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          child: KField(
            label: widget.label,
            controller: _c,
            autofocus: true,
            keyboard: const TextInputType.numberWithOptions(decimal: true),
            formatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            prefix: cur == null ? null : '${cur.symbol} ',
            onSubmitted: (_) => _done(),
          ),
        ),
        const SizedBox(width: Sp.xs),
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: RoundIcon(Icons.calculate_outlined, tooltip: 'Calculator', size: 40, color: K.blue, onTap: _calc),
        ),
      ]),
      if (widget.note != null) ...[const SizedBox(height: Sp.sm), Text(widget.note!, style: T.small)],
      const SizedBox(height: Sp.lg),
      KButton(label: widget.yes, icon: Icons.check_rounded, expand: true, onPressed: _done),
      if (widget.clearLabel != null) ...[
        const SizedBox(height: Sp.sm),
        Center(
          child: KButton(
            label: widget.clearLabel!,
            kind: KButtonKind.ghost,
            small: true,
            onPressed: () => Navigator.of(context).pop(const AmountAnswer.clear()),
          ),
        ),
      ],
    ]);
  }
}

/// Actions for a row, in a sheet: returns the key of the one tapped.
Future<String?> pickAction(BuildContext context, {required String title, required List<PickOption<String>> actions}) async {
  final p = await showPicker<String>(context, title: title, options: actions);
  return p?.value;
}
