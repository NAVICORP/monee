import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/book.dart';
import '../money.dart';
import '../theme.dart';
import '../widgets.dart';
import 'more_common.dart';

/// More > Income or Expense categories: each category with its
/// subcategories under it. Add, rename, change the emoji, put in order,
/// delete (past entries keep it) and restore.
class CategoriesPage extends StatefulWidget {
  const CategoriesPage({super.key, required this.kind});

  /// income or expense
  final String kind;

  @override
  State<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends State<CategoriesPage> {
  bool ordering = false;
  bool busy = false;

  String get kind => widget.kind == 'income' ? 'income' : 'expense';
  String get kindWord => kind == 'income' ? 'Income' : 'Expense';

  /// Runs a change, then has every page load the lists again.
  Future<void> _run(Future<void> Function() work, {String? done}) async {
    if (busy) return;
    setState(() => busy = true);
    await attempt(context, () async {
      await work();
      await Me.instance.changed(lists: true);
    }, done: done);
    if (mounted) setState(() => busy = false);
  }

  int _nextSort(Iterable<Category> list) {
    var top = 0;
    for (final c in list) {
      if (c.sort > top) top = c.sort;
    }
    return top + 10;
  }

  Future<void> _addTop() async {
    final r = await askNameEmoji(context, title: 'New ${kind == 'income' ? 'income' : 'expense'} category', yes: 'Add');
    if (r == null || !mounted) return;
    final all = Me.instance.categories.where((c) => c.kind == kind && c.parentId == null);
    final sort = _nextSort(all);
    await _run(() async {
      await Api.instance.insert('categories', {'kind': kind, 'name': r.$1, 'emoji': r.$2, 'sort': sort});
    }, done: '${r.$1} added');
  }

  Future<void> _addSub(Category parent) async {
    final r = await askNameEmoji(context, title: 'New in ${parent.name}', yes: 'Add', note: 'A subcategory of ${parent.name}. The emoji is optional.');
    if (r == null || !mounted) return;
    final sort = _nextSort(Me.instance.categories.where((c) => c.parentId == parent.id));
    await _run(() async {
      await Api.instance.insert('categories', {'kind': kind, 'parent_id': parent.id, 'name': r.$1, 'emoji': r.$2, 'sort': sort});
    }, done: '${r.$1} added');
  }

  Future<void> _edit(Category c) async {
    final r = await askNameEmoji(context, title: 'Edit ${c.name}', name: c.name, emoji: c.emoji);
    if (r == null || !mounted) return;
    await _run(() async {
      await Api.instance.update('categories', {'name': r.$1, 'emoji': r.$2}, where: {'id': 'eq.${c.id}'});
    }, done: 'Saved');
  }

  Future<void> _delete(Category c) async {
    final subs = c.parentId == null ? Me.instance.subsOf(c.id) : const <Category>[];
    final ok = await confirm(context,
        title: 'Delete ${c.name}?',
        text: '${subs.isEmpty ? '' : 'Its ${subs.length} subcategor${subs.length == 1 ? 'y goes' : 'ies go'} with it. '}'
            'Past entries keep their category; it is just no longer offered for new ones. You can restore it from Deleted, below.',
        yes: 'Delete',
        danger: true);
    if (!ok || !mounted) return;
    await _run(() async {
      await Api.instance.update('categories', {'deleted_at': nowStamp()}, where: {'id': 'eq.${c.id}'});
    }, done: '${c.name} deleted');
  }

  Future<void> _restore(Category c) async {
    await _run(() async {
      await Api.instance.update('categories', {'deleted_at': null}, where: {'id': 'eq.${c.id}'});
    }, done: '${c.name} is back');
  }

  Future<void> _purge(Category c) async {
    final hasSubs = Me.instance.categories.any((x) => x.parentId == c.id);
    final ok = await confirm(context,
        title: 'Delete ${c.name} for good?',
        text: '${hasSubs ? 'Its subcategories go too. ' : ''}Entries in it become Uncategorised, and its budgets go. This cannot be undone.',
        yes: 'Delete for good',
        danger: true);
    if (!ok || !mounted) return;
    await _run(() async {
      await Api.instance.delete('categories', where: {'id': 'eq.${c.id}'});
    }, done: '${c.name} deleted for good');
  }

  Future<void> _move(List<Category> siblings, int i, int dir) async {
    await _run(() => saveOrder('categories', [for (final c in siblings) (c.id, c.sort)], i, dir));
  }

  Future<void> _topActions(Category c) async {
    final a = await pickAction(context, title: c.name, actions: const [
      PickOption('edit', 'Rename or change the emoji', icon: Icons.edit_outlined),
      PickOption('sub', 'Add a subcategory', icon: Icons.subdirectory_arrow_right_rounded),
      PickOption('delete', 'Delete', icon: Icons.delete_outline_rounded),
    ]);
    if (!mounted) return;
    if (a == 'edit') await _edit(c);
    if (a == 'sub') await _addSub(c);
    if (a == 'delete') await _delete(c);
  }

  Future<void> _subActions(Category c) async {
    final a = await pickAction(context, title: c.name, actions: const [
      PickOption('edit', 'Rename or change the emoji', icon: Icons.edit_outlined),
      PickOption('delete', 'Delete', icon: Icons.delete_outline_rounded),
    ]);
    if (!mounted) return;
    if (a == 'edit') await _edit(c);
    if (a == 'delete') await _delete(c);
  }

  Future<void> _deletedActions(Category c) async {
    final a = await pickAction(context, title: c.name, actions: const [
      PickOption('restore', 'Restore', icon: Icons.restore_rounded),
      PickOption('purge', 'Delete for good', icon: Icons.delete_forever_outlined),
    ]);
    if (!mounted) return;
    if (a == 'restore') await _restore(c);
    if (a == 'purge') await _purge(c);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: Me.instance, builder: (context, _) => _body(context));

  Widget _body(BuildContext context) {
    final me = Me.instance;
    final b = me.book;
    if (b == null) return const Scaffold(body: Loading());
    final can = b.canEdit;
    final tops = me.topCategories(kind);
    final deleted = me.categories.where((c) => c.kind == kind && c.deleted).toList()..sort((x, y) => x.name.compareTo(y.name));
    return Scaffold(
      appBar: AppBar(title: Text('$kindWord categories'), actions: [
        if (can && tops.isNotEmpty)
          IconButton(
            tooltip: ordering ? 'Done' : 'Put in order',
            icon: Icon(ordering ? Icons.check_rounded : Icons.swap_vert_rounded, color: ordering ? K.blue : K.ink2),
            onPressed: () => setState(() => ordering = !ordering),
          ),
        const SizedBox(width: Sp.xs),
      ]),
      body: PageBody(children: [
        if (!can) const ReadOnlyNote('You can look at this book but not change it.'),
        if (can && !b.subcategories) const ReadOnlyNote('Subcategories are off, so new entries use these categories only. Turn them on in Configuration.'),
        if (ordering) const ReadOnlyNote('Use the arrows to move a category or subcategory. Tap the tick when done.'),
        if (busy) const Padding(padding: EdgeInsets.only(bottom: Sp.sm), child: LinearProgressIndicator(minHeight: 2)),
        if (tops.isEmpty) KCard(child: EmptyState(icon: Icons.category_outlined, text: 'No ${kind == 'income' ? 'income' : 'expense'} categories yet.')),
        for (var i = 0; i < tops.length; i++) ...[
          _topCard(tops, i, can),
          const SizedBox(height: Sp.sm),
        ],
        if (can && !ordering) ...[
          const SizedBox(height: Sp.xs),
          Center(child: KButton(label: 'Add a category', icon: Icons.add_rounded, kind: KButtonKind.secondary, small: true, onPressed: _addTop)),
        ],
        if (deleted.isNotEmpty && !ordering) ...[
          const SectionTitle('Deleted'),
          KGroup(children: [
            for (final c in deleted)
              KRow(
                leading: EmojiBadge(c.emoji, name: c.name, size: 32),
                title: c.parentId == null ? c.name : '${me.category(c.parentId)?.name ?? ''} / ${c.name}',
                sub: 'Past entries keep it',
                trailing: can ? Icon(Icons.more_horiz_rounded, color: K.muted, size: 20) : null,
                onTap: can ? () => _deletedActions(c) : null,
              ),
          ]),
        ],
      ]),
    );
  }

  Widget _topCard(List<Category> tops, int i, bool can) {
    final c = tops[i];
    final subs = Me.instance.subsOf(c.id);
    return KCard(
      padding: EdgeInsets.zero,
      child: Column(children: [
        KRow(
          leading: EmojiBadge(c.emoji, name: c.name, size: 34),
          title: c.name,
          sub: subs.isEmpty ? null : '${subs.length} subcategor${subs.length == 1 ? 'y' : 'ies'}',
          trailing: ordering
              ? MoveButtons(
                  onUp: i > 0 && !busy ? () => _move(tops, i, -1) : null,
                  onDown: i < tops.length - 1 && !busy ? () => _move(tops, i, 1) : null,
                )
              : (can ? Icon(Icons.more_horiz_rounded, color: K.muted, size: 20) : null),
          onTap: can && !ordering ? () => _topActions(c) : null,
        ),
        for (var j = 0; j < subs.length; j++) ...[
          const Divider(height: 1, indent: 60),
          _SubRow(
            c: subs[j],
            trailing: ordering
                ? MoveButtons(
                    onUp: j > 0 && !busy ? () => _move(subs, j, -1) : null,
                    onDown: j < subs.length - 1 && !busy ? () => _move(subs, j, 1) : null,
                  )
                : (can ? Icon(Icons.more_horiz_rounded, color: K.border2, size: 18) : null),
            onTap: can && !ordering ? () => _subActions(subs[j]) : null,
          ),
        ],
      ]),
    );
  }
}

/// A subcategory, indented under its category.
class _SubRow extends StatelessWidget {
  const _SubRow({required this.c, this.trailing, this.onTap});
  final Category c;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final e = (c.emoji ?? '').trim();
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(60, 9, 12, 9),
        child: Row(children: [
          if (e.isNotEmpty) ...[Text(e, style: const TextStyle(fontSize: 15, height: 1.2, fontFamilyFallback: T.emojiFallback)), const SizedBox(width: Sp.sm)],
          Expanded(child: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.body)),
          if (trailing != null) ...[const SizedBox(width: Sp.sm), trailing!],
        ]),
      ),
    );
  }
}
