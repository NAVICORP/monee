import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/book.dart';
import '../../core/format.dart';
import '../entry/entry_page.dart';
import '../money.dart';
import '../theme.dart';
import '../widgets.dart';
import 'trans_common.dart';

/// The saved entries: tap one to start a new entry from it. Bookmarks are
/// saved from the entry page.
Future<void> showBookmarks(BuildContext context) {
  return showKSheet<void>(
    context,
    title: 'Bookmarks',
    builder: (ctx) => _Bookmarks(
      onPick: (m) {
        Navigator.of(ctx).pop();
        openEntry(context, template: m);
      },
    ),
  );
}

class _Bookmarks extends StatefulWidget {
  const _Bookmarks({required this.onPick});
  final ValueChanged<Map<String, dynamic>> onPick;

  @override
  State<_Bookmarks> createState() => _BookmarksState();
}

class _BookmarksState extends State<_Bookmarks> with ReloadOnChange {
  List<Map<String, dynamic>> _rows = const <Map<String, dynamic>>[];
  bool _loaded = false;
  String? _error;
  int _ticket = 0;

  @override
  Future<void> reload() async {
    final t = ++_ticket;
    try {
      final r = await Api.instance.select('bookmarks', order: 'sort,created_at');
      if (!mounted || t != _ticket) return;
      setState(() {
        _rows = r;
        _loaded = true;
        _error = null;
      });
    } catch (e) {
      if (!mounted || t != _ticket) return;
      setState(() {
        _loaded = true;
        _error = trError(e);
      });
    }
  }

  Future<void> _delete(Map<String, dynamic> m) async {
    final ok = await confirm(context, title: 'Delete this bookmark?', text: 'Entries made from it stay as they are.', yes: 'Delete', danger: true);
    if (!ok || !mounted) return;
    try {
      await Api.instance.delete('bookmarks', where: {'id': 'eq.${m['id']}'});
      await Me.instance.changed();
    } on ApiError catch (e) {
      if (mounted) toast(context, e.message, bad: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Padding(padding: EdgeInsets.symmetric(vertical: 32), child: Loading());
    final edit = Me.instance.book?.canEdit ?? false;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (_error != null) ...[Notice(_error!), const SizedBox(height: Sp.md)],
      if (_rows.isEmpty && _error == null)
        const EmptyState(icon: Icons.star_border_rounded, text: 'No bookmarks yet.')
      else if (_rows.isNotEmpty)
        KGroup(children: [for (final m in _rows) _row(m, edit)]),
      if (edit) ...[
        const SizedBox(height: Sp.md),
        const Text('Save a bookmark from the star on the entry page.', textAlign: TextAlign.center, style: T.small),
      ],
    ]);
  }

  Widget _row(Map<String, dynamic> m, bool edit) {
    final me = Me.instance;
    final kind = m['kind'] as String? ?? 'expense';
    final acc = me.account(m['account_id'] as String?);
    final to = me.account(m['to_account_id'] as String?);
    final cat = me.category(m['category_id'] as String?);
    final parent = cat == null ? null : me.category(cat.parentId);
    final note = '${m['note'] ?? ''}'.trim();
    final catText = kind == 'transfer'
        ? 'Transfer'
        : (cat == null ? 'Uncategorised' : (parent == null ? cat.name : '${parent.name} / ${cat.name}'));
    final where = kind == 'transfer' ? '${acc?.name ?? 'Any account'} → ${to?.name ?? 'Any account'}' : (acc?.name ?? '');
    final sub = [if (note.isNotEmpty) catText, if (where.isNotEmpty) where].join(', ');
    final amount = m['amount'] == null ? null : toNum(m['amount']);
    return KRow(
      leading: EmojiBadge(cat?.emoji ?? parent?.emoji, name: catText),
      title: note.isNotEmpty ? note : catText,
      sub: sub,
      onTap: edit ? () => widget.onPick(m) : null,
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (amount != null) MoneyText(amount, currency: acc?.currency, kind: kind, style: T.bodyStrong.copyWith(fontSize: 14)),
        if (edit)
          IconButton(
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline_rounded, size: 19, color: K.muted),
            onPressed: () => _delete(m),
          ),
      ]),
    );
  }
}
