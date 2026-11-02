import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/book.dart';
import '../theme.dart';
import '../widgets.dart';
import 'more_common.dart';

/// More > Tags: every tag in the book, to add, rename or delete.
class TagsPage extends StatefulWidget {
  const TagsPage({super.key});

  @override
  State<TagsPage> createState() => _TagsPageState();
}

class _TagsPageState extends State<TagsPage> {
  final _q = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  String _clean(String s) => s.trim().replaceFirst(RegExp(r'^#+'), '').trim();

  Future<void> _add() async {
    final v = await askText(context, title: 'New tag', label: 'Tag', hint: 'trip', yes: 'Add', maxLength: 30, caps: TextCapitalization.none);
    if (v == null || !mounted) return;
    final name = _clean(v);
    if (name.isEmpty) return;
    await attempt(context, () async {
      await Api.instance.insert('tags', {'name': name});
      await Me.instance.changed(lists: true);
    }, done: '#$name added');
  }

  Future<void> _rename(Map<String, dynamic> t) async {
    final v = await askText(context,
        title: 'Rename #${t['name']}',
        label: 'Tag',
        initial: '${t['name']}',
        maxLength: 30,
        caps: TextCapitalization.none,
        note: 'Every entry with this tag follows the new name.');
    if (v == null || !mounted) return;
    final name = _clean(v);
    if (name.isEmpty || name == t['name']) return;
    await attempt(context, () async {
      await Api.instance.update('tags', {'name': name}, where: {'id': 'eq.${t['id']}'});
      await Me.instance.changed(lists: true);
    }, done: 'Renamed to #$name');
  }

  Future<void> _delete(Map<String, dynamic> t) async {
    final ok = await confirm(context,
        title: 'Delete #${t['name']}?', text: 'It comes off every entry that has it. The entries themselves stay.', yes: 'Delete', danger: true);
    if (!ok || !mounted) return;
    await attempt(context, () async {
      await Api.instance.delete('tags', where: {'id': 'eq.${t['id']}'});
      await Me.instance.changed(lists: true);
    }, done: '#${t['name']} deleted');
  }

  Future<void> _actions(Map<String, dynamic> t) async {
    final a = await pickAction(context, title: '#${t['name']}', actions: const [
      PickOption('rename', 'Rename', icon: Icons.edit_outlined),
      PickOption('delete', 'Delete', icon: Icons.delete_outline_rounded),
    ]);
    if (!mounted) return;
    if (a == 'rename') await _rename(t);
    if (a == 'delete') await _delete(t);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: Me.instance, builder: (context, _) => _body(context));

  Widget _body(BuildContext context) {
    final b = Me.instance.book;
    if (b == null) return const Scaffold(body: Loading());
    final can = b.canEdit;
    final all = [...Me.instance.tags]..sort((x, y) => '${x['name']}'.toLowerCase().compareTo('${y['name']}'.toLowerCase()));
    final q = _clean(_q.text).toLowerCase();
    final shown = q.isEmpty ? all : all.where((t) => '${t['name']}'.toLowerCase().contains(q)).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Tags')),
      body: PageBody(children: [
        if (!can) const ReadOnlyNote('You can look at this book but not change it.'),
        if (all.length > 10) ...[
          SearchField(controller: _q, hint: 'Search tags', onChanged: (_) => setState(() {})),
          const SizedBox(height: Sp.md),
        ],
        if (all.isEmpty)
          const KCard(child: EmptyState(icon: Icons.sell_outlined, text: 'No tags yet. Add tags to entries, then find them again in Search.'))
        else if (shown.isEmpty)
          const KCard(child: EmptyState(icon: Icons.search_off_rounded, text: 'No tag matches.'))
        else
          KGroup(children: [
            for (final t in shown)
              KRow(
                leading: Container(
                  width: 32,
                  height: 32,
                  decoration: const BoxDecoration(color: K.brand100, shape: BoxShape.circle),
                  child: const Icon(Icons.sell_outlined, size: 16, color: K.brand600),
                ),
                title: '#${t['name']}',
                trailing: can ? const Icon(Icons.more_horiz_rounded, color: K.muted, size: 20) : null,
                onTap: can ? () => _actions(t) : null,
              ),
          ]),
        if (can) ...[
          const SizedBox(height: Sp.md),
          Center(child: KButton(label: 'Add a tag', icon: Icons.add_rounded, kind: KButtonKind.secondary, small: true, onPressed: _add)),
        ],
      ]),
    );
  }
}
