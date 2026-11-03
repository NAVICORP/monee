import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/book.dart';
import '../accounts/account_edit.dart' show openAccountEditor;
import '../money.dart';
import '../theme.dart';
import '../widgets.dart';
import 'configuration.dart';
import 'more_common.dart';

/// More > Accounts settings: account groups, accounts, what was deleted,
/// Transfer-Expense accounts, and how card spending counts.
class AccountSettingsPage extends StatefulWidget {
  const AccountSettingsPage({super.key});

  @override
  State<AccountSettingsPage> createState() => _AccountSettingsPageState();
}

class _AccountSettingsPageState extends State<AccountSettingsPage> {
  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: Me.instance, builder: (context, _) => _body(context));

  Widget _body(BuildContext context) {
    final me = Me.instance;
    final b = me.book;
    if (b == null) return const Scaffold(body: Loading());
    final groups = me.groups.where((g) => !g.deleted).length;
    final gone = me.groups.where((g) => g.deleted).length + me.accounts.where((a) => a.deleted).length;
    return Scaffold(
      appBar: AppBar(title: const Text('Accounts settings')),
      body: PageBody(children: [
        if (!b.canEdit) const ReadOnlyNote('You can look at this book but not change it.'),
        LinkGroup([
          LinkRow(Icons.folder_outlined, 'Account groups', () => openPage<void>(context, const _GroupsPage()), value: '$groups'),
          LinkRow(Icons.account_balance_wallet_outlined, 'Accounts', () => openPage<void>(context, const _AccountsPage()),
              value: '${me.liveAccounts.length}'),
          LinkRow(Icons.restore_from_trash_outlined, 'Deleted groups and accounts', () => openPage<void>(context, const _DeletedPage()),
              value: gone == 0 ? 'None' : '$gone'),
          LinkRow(Icons.savings_outlined, 'Transfer-Expense', () => openPage<void>(context, const _TransferExpensePage()),
              sub: 'Money moved into savings or a loan counts as spent'),
          LinkRow(Icons.credit_card_rounded, 'Card spending counts', b.isOwner ? () => pickCardDisplay(context) : null,
              value: cardDisplayWords(b.cardDisplay)),
        ]),
        const SizedBox(height: Sp.md),
        Text('Deleting a group or an account keeps its entries; restore it from Deleted any time.', style: T.small),
      ]),
    );
  }
}

/// A busy flag around saves that change the lists.
mixin _Busy<W extends StatefulWidget> on State<W> {
  bool busy = false;

  Future<void> run(Future<void> Function() work, {String? done}) async {
    if (busy) return;
    setState(() => busy = true);
    await attempt(context, () async {
      await work();
      await Me.instance.changed(lists: true);
    }, done: done);
    if (mounted) setState(() => busy = false);
  }
}

String _accounts(int n) => n == 1 ? '1 account' : '$n accounts';

/// Why accounts cannot be deleted for good yet: a debit card spends from
/// one of them, or a card pays itself automatically from one. Null when
/// nothing is in the way.
String? _blockers(Set<String> ids) {
  for (final x in Me.instance.accounts) {
    if (ids.contains(x.id)) continue;
    if (x.linkedAccountId != null && ids.contains(x.linkedAccountId)) {
      return 'The debit card ${x.name} spends from it. Link that card to another account, or delete the card for good first.';
    }
    if (x.autoPay && x.billingAccountId != null && ids.contains(x.billingAccountId)) {
      return 'The card ${x.name} is paid from it automatically. Change where that card is paid from first.';
    }
  }
  return null;
}

// ---------------------------------------------------------------- groups

class _GroupsPage extends StatefulWidget {
  const _GroupsPage();

  @override
  State<_GroupsPage> createState() => _GroupsPageState();
}

class _GroupsPageState extends State<_GroupsPage> with _Busy<_GroupsPage> {
  bool ordering = false;

  List<Group> get _groups => Me.instance.groups.where((g) => !g.deleted).toList()
    ..sort((a, b) => a.sort != b.sort ? a.sort.compareTo(b.sort) : a.name.compareTo(b.name));

  Future<void> _add() async {
    final r = await showKSheet<(String, String?, String)>(context, title: 'New group', builder: (ctx) => const _NewGroup());
    if (r == null || !mounted) return;
    var top = 0;
    for (final g in Me.instance.groups) {
      if (g.sort > top) top = g.sort;
    }
    await run(() async {
      await Api.instance.insert('account_groups', {'name': r.$1, 'emoji': r.$2, 'kind': r.$3, 'sort': top + 10});
    }, done: '${r.$1} added');
  }

  Future<void> _actions(Group g) async {
    final all = Me.instance.accounts.where((a) => a.groupId == g.id).length;
    final a = await pickAction(context, title: g.name, actions: [
      const PickOption('edit', 'Rename or change the emoji', icon: Icons.edit_outlined),
      PickOption('kind', 'What kind of group', icon: Icons.category_outlined, sub: all == 0 ? kGroupKinds[g.kind] : 'Only while it has no accounts'),
      PickOption('hide', g.hidden ? 'Show it' : 'Hide it', icon: g.hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined,
          sub: g.hidden ? 'Back on the Accounts tab' : 'Off the Accounts tab; its money still counts'),
      const PickOption('delete', 'Delete', icon: Icons.delete_outline_rounded),
    ]);
    if (!mounted || a == null) return;
    switch (a) {
      case 'edit':
        final r = await askNameEmoji(context, title: 'Edit ${g.name}', name: g.name, emoji: g.emoji);
        if (r == null || !mounted) return;
        await run(() async {
          await Api.instance.update('account_groups', {'name': r.$1, 'emoji': r.$2}, where: {'id': 'eq.${g.id}'});
        }, done: 'Saved');
      case 'kind':
        if (all > 0) {
          toast(context, 'Move its accounts to another group, or delete them for good, before changing its kind.', bad: true);
          return;
        }
        final p = await showPicker<String>(context, title: 'Kind of group', selected: g.kind, options: [
          for (final e in kGroupKinds.entries) PickOption(e.key, e.value),
        ]);
        if (p == null || p.value == g.kind || !mounted) return;
        await run(() async {
          await Api.instance.update('account_groups', {'kind': p.value}, where: {'id': 'eq.${g.id}'});
        }, done: 'Saved');
      case 'hide':
        await run(() async {
          await Api.instance.update('account_groups', {'hidden': !g.hidden}, where: {'id': 'eq.${g.id}'});
        }, done: g.hidden ? '${g.name} is shown' : '${g.name} is hidden');
      case 'delete':
        final live = Me.instance.accounts.where((x) => x.groupId == g.id && !x.deleted).length;
        final ok = await confirm(context,
            title: 'Delete ${g.name}?',
            text: '${live == 0 ? '' : 'Its ${_accounts(live)} go with it. '}Entries stay as they are, and you can restore it from Deleted.',
            yes: 'Delete',
            danger: true);
        if (!ok || !mounted) return;
        await run(() async {
          await Api.instance.update('account_groups', {'deleted_at': nowStamp()}, where: {'id': 'eq.${g.id}'});
        }, done: '${g.name} deleted');
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: Me.instance, builder: (context, _) => _body(context));

  Widget _body(BuildContext context) {
    final b = Me.instance.book;
    if (b == null) return const Scaffold(body: Loading());
    final can = b.canEdit;
    final groups = _groups;
    return Scaffold(
      appBar: AppBar(title: const Text('Account groups'), actions: [
        if (can && groups.length > 1)
          IconButton(
            tooltip: ordering ? 'Done' : 'Put in order',
            icon: Icon(ordering ? Icons.check_rounded : Icons.swap_vert_rounded, color: ordering ? K.blue : K.ink2),
            onPressed: () => setState(() => ordering = !ordering),
          ),
        const SizedBox(width: Sp.xs),
      ]),
      body: PageBody(children: [
        if (!can) const ReadOnlyNote('You can look at this book but not change it.'),
        if (ordering) const ReadOnlyNote('Use the arrows to move a group. The Accounts tab shows them in this order.'),
        if (busy) const Padding(padding: EdgeInsets.only(bottom: Sp.sm), child: LinearProgressIndicator(minHeight: 2)),
        if (groups.isEmpty)
          const KCard(child: EmptyState(icon: Icons.folder_outlined, text: 'No groups yet.'))
        else
          KGroup(children: [
            for (var i = 0; i < groups.length; i++)
              Builder(builder: (context) {
                final g = groups[i];
                final n = Me.instance.accounts.where((a) => a.groupId == g.id && !a.deleted).length;
                return KRow(
                  leading: EmojiBadge(g.emoji, name: g.name, size: 34),
                  title: g.name,
                  sub: '${kGroupKinds[g.kind] ?? g.kind}, ${_accounts(n)}${g.hidden ? ', hidden' : ''}',
                  trailing: ordering
                      ? MoveButtons(
                          onUp: i > 0 && !busy ? () => run(() => saveOrder('account_groups', [for (final x in groups) (x.id, x.sort)], i, -1)) : null,
                          onDown: i < groups.length - 1 && !busy
                              ? () => run(() => saveOrder('account_groups', [for (final x in groups) (x.id, x.sort)], i, 1))
                              : null,
                        )
                      : (can ? Icon(Icons.more_horiz_rounded, color: K.muted, size: 20) : null),
                  onTap: can && !ordering ? () => _actions(g) : null,
                );
              }),
          ]),
        if (can && !ordering) ...[
          const SizedBox(height: Sp.md),
          Center(child: KButton(label: 'Add a group', icon: Icons.add_rounded, kind: KButtonKind.secondary, small: true, onPressed: _add)),
        ],
        const SizedBox(height: Sp.md),
        Text('A group\'s kind decides how its accounts work: a credit card has a settlement and a payment day, a debit card spends from its bank account.',
            style: T.small),
      ]),
    );
  }
}

/// A new group: its name, emoji and kind.
class _NewGroup extends StatefulWidget {
  const _NewGroup();

  @override
  State<_NewGroup> createState() => _NewGroupState();
}

class _NewGroupState extends State<_NewGroup> {
  final _name = TextEditingController();
  final _emoji = TextEditingController();
  String kind = 'other';
  String? error;

  @override
  void dispose() {
    _name.dispose();
    _emoji.dispose();
    super.dispose();
  }

  Future<void> _pickKind() async {
    final p = await showPicker<String>(context, title: 'Kind of group', selected: kind, options: [
      for (final e in kGroupKinds.entries) PickOption(e.key, e.value),
    ]);
    if (p != null && mounted) setState(() => kind = p.value);
  }

  void _done() {
    final n = _name.text.trim();
    final e = _emoji.text.trim();
    if (n.isEmpty || n.length > 40) {
      setState(() => error = 'Give the group a name (up to 40 characters).');
      return;
    }
    Navigator.of(context).pop((n, e.isEmpty ? null : e, kind));
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (error != null) ...[Notice(error!), const SizedBox(height: Sp.md)],
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        SizedBox(width: 84, child: KField(label: 'Emoji', controller: _emoji, hint: '🏦', caps: TextCapitalization.none)),
        const SizedBox(width: Sp.md),
        Expanded(child: KField(label: 'Name', controller: _name, autofocus: true, caps: TextCapitalization.words)),
      ]),
      const SizedBox(height: Sp.md),
      KChoice(label: 'Kind', value: kGroupKinds[kind] ?? kind, icon: Icons.category_outlined, onTap: _pickKind),
      const SizedBox(height: Sp.lg),
      KButton(label: 'Add', icon: Icons.check_rounded, expand: true, onPressed: _done),
    ]);
  }
}

// ---------------------------------------------------------------- accounts

class _AccountsPage extends StatefulWidget {
  const _AccountsPage();

  @override
  State<_AccountsPage> createState() => _AccountsPageState();
}

class _AccountsPageState extends State<_AccountsPage> with _Busy<_AccountsPage> {
  bool ordering = false;

  Future<void> _actions(Account a) async {
    final p = await pickAction(context, title: a.name, actions: [
      const PickOption('edit', 'Edit', icon: Icons.edit_outlined, sub: 'Name, currency, opening balance, card days'),
      PickOption('hide', a.hidden ? 'Show it' : 'Hide it', icon: a.hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined),
      PickOption('totals', a.inTotals ? 'Leave out of totals' : 'Count in totals', icon: Icons.functions_rounded),
      const PickOption('delete', 'Delete', icon: Icons.delete_outline_rounded),
    ]);
    if (!mounted || p == null) return;
    switch (p) {
      case 'edit':
        await openAccountEditor(context, account: a);
      case 'hide':
        await run(() async {
          await Api.instance.update('accounts', {'hidden': !a.hidden}, where: {'id': 'eq.${a.id}'});
        }, done: a.hidden ? '${a.name} is shown' : '${a.name} is hidden');
      case 'totals':
        await run(() async {
          await Api.instance.update('accounts', {'in_totals': !a.inTotals}, where: {'id': 'eq.${a.id}'});
        }, done: a.inTotals ? '${a.name} is left out of totals' : '${a.name} counts in totals');
      case 'delete':
        final ok = await confirm(context,
            title: 'Delete ${a.name}?',
            text: 'It goes off the Accounts tab and cannot take new entries. Its entries stay, and you can restore it from Deleted.',
            yes: 'Delete',
            danger: true);
        if (!ok || !mounted) return;
        await run(() async {
          await Api.instance.update('accounts', {'deleted_at': nowStamp()}, where: {'id': 'eq.${a.id}'});
        }, done: '${a.name} deleted');
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: Me.instance, builder: (context, _) => _body(context));

  Widget _body(BuildContext context) {
    final me = Me.instance;
    final b = me.book;
    if (b == null) return const Scaffold(body: Loading());
    final can = b.canEdit;
    final groups = me.groups.where((g) => !g.deleted).toList()
      ..sort((x, y) => x.sort != y.sort ? x.sort.compareTo(y.sort) : x.name.compareTo(y.name));
    final live = me.liveAccounts;
    return Scaffold(
      appBar: AppBar(title: const Text('Accounts'), actions: [
        if (can && live.length > 1)
          IconButton(
            tooltip: ordering ? 'Done' : 'Put in order',
            icon: Icon(ordering ? Icons.check_rounded : Icons.swap_vert_rounded, color: ordering ? K.blue : K.ink2),
            onPressed: () => setState(() => ordering = !ordering),
          ),
        const SizedBox(width: Sp.xs),
      ]),
      body: PageBody(children: [
        if (!can) const ReadOnlyNote('You can look at this book but not change it.'),
        if (ordering) const ReadOnlyNote('Use the arrows to move an account within its group.'),
        if (busy) const Padding(padding: EdgeInsets.only(bottom: Sp.sm), child: LinearProgressIndicator(minHeight: 2)),
        if (live.isEmpty) const KCard(child: EmptyState(icon: Icons.account_balance_wallet_outlined, text: 'No accounts yet.')),
        for (final g in groups)
          if (live.any((a) => a.groupId == g.id)) ...[
            SectionTitle(g.label, top: 12),
            Builder(builder: (context) {
              final list = live.where((a) => a.groupId == g.id).toList();
              return KGroup(children: [
                for (var i = 0; i < list.length; i++)
                  KRow(
                    title: list[i].name,
                    sub: [
                      list[i].currency,
                      if (list[i].hidden) 'Hidden',
                      if (!list[i].inTotals) 'Not in totals',
                      if (list[i].transferExpense) 'Transfer-Expense',
                    ].join(', '),
                    trailing: ordering
                        ? MoveButtons(
                            onUp: i > 0 && !busy ? () => run(() => saveOrder('accounts', [for (final x in list) (x.id, x.sort)], i, -1)) : null,
                            onDown: i < list.length - 1 && !busy
                                ? () => run(() => saveOrder('accounts', [for (final x in list) (x.id, x.sort)], i, 1))
                                : null,
                          )
                        : (can ? Icon(Icons.more_horiz_rounded, color: K.muted, size: 20) : null),
                    onTap: can && !ordering ? () => _actions(list[i]) : null,
                  ),
              ]);
            }),
          ],
        if (can && !ordering) ...[
          const SizedBox(height: Sp.lg),
          Center(
            child: KButton(
                label: 'Add an account', icon: Icons.add_rounded, kind: KButtonKind.secondary, small: true, onPressed: () => openAccountEditor(context)),
          ),
        ],
      ]),
    );
  }
}

// ---------------------------------------------------------------- deleted

class _DeletedPage extends StatefulWidget {
  const _DeletedPage();

  @override
  State<_DeletedPage> createState() => _DeletedPageState();
}

class _DeletedPageState extends State<_DeletedPage> with _Busy<_DeletedPage> {
  Future<void> _group(Group g) async {
    final all = Me.instance.accounts.where((a) => a.groupId == g.id).length;
    final p = await pickAction(context, title: g.name, actions: const [
      PickOption('restore', 'Restore', icon: Icons.restore_rounded, sub: 'With the accounts in it'),
      PickOption('purge', 'Delete for good', icon: Icons.delete_forever_outlined),
    ]);
    if (!mounted || p == null) return;
    if (p == 'restore') {
      await run(() async {
        await Api.instance.update('account_groups', {'deleted_at': null}, where: {'id': 'eq.${g.id}'});
      }, done: '${g.name} is back');
      return;
    }
    final blocked = _blockers({for (final a in Me.instance.accounts) if (a.groupId == g.id) a.id});
    if (blocked != null) {
      toast(context, blocked, bad: true);
      return;
    }
    final first = await confirm(context,
        title: 'Delete ${g.name} for good?',
        text: all == 0
            ? 'The group is removed for good.'
            : 'Its ${_accounts(all)} and every entry on them are deleted with it, transfers included. This cannot be undone.',
        yes: 'Continue',
        danger: true);
    if (!first || !mounted) return;
    if (all > 0) {
      final second = await confirm(context,
          title: 'Are you sure?', text: 'Last chance: ${g.name}, its accounts and their entries cannot be brought back.', yes: 'Delete for good', danger: true);
      if (!second || !mounted) return;
    }
    await run(() async {
      await Api.instance.delete('account_groups', where: {'id': 'eq.${g.id}'});
    }, done: '${g.name} deleted for good');
  }

  Future<void> _account(Account a) async {
    final groupGone = a.group?.deleted ?? false;
    final p = await pickAction(context, title: a.name, actions: [
      PickOption('restore', 'Restore', icon: Icons.restore_rounded, sub: groupGone ? 'Its group ${a.group?.name ?? ''} comes back too' : null),
      const PickOption('purge', 'Delete for good', icon: Icons.delete_forever_outlined),
    ]);
    if (!mounted || p == null) return;
    if (p == 'restore') {
      await run(() async {
        await Api.instance.update('accounts', {'deleted_at': null}, where: {'id': 'eq.${a.id}'});
        if (groupGone) await Api.instance.update('account_groups', {'deleted_at': null}, where: {'id': 'eq.${a.groupId}'});
      }, done: '${a.name} is back');
      return;
    }
    final blocked = _blockers({a.id});
    if (blocked != null) {
      toast(context, blocked, bad: true);
      return;
    }
    final first = await confirm(context,
        title: 'Delete ${a.name} for good?',
        text: 'Every entry on it is deleted with it, transfers to and from it and its repeats included. This cannot be undone.',
        yes: 'Continue',
        danger: true);
    if (!first || !mounted) return;
    final second = await confirm(context,
        title: 'Are you sure?', text: 'Last chance: ${a.name} and its entries cannot be brought back.', yes: 'Delete for good', danger: true);
    if (!second || !mounted) return;
    await run(() async {
      await Api.instance.delete('accounts', where: {'id': 'eq.${a.id}'});
    }, done: '${a.name} deleted for good');
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: Me.instance, builder: (context, _) => _body(context));

  Widget _body(BuildContext context) {
    final me = Me.instance;
    final b = me.book;
    if (b == null) return const Scaffold(body: Loading());
    final can = b.canEdit;
    final groups = me.groups.where((g) => g.deleted).toList();
    final accounts = me.accounts.where((a) => a.deleted).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Deleted')),
      body: PageBody(children: [
        if (!can) const ReadOnlyNote('You can look at this book but not change it.'),
        if (busy) const Padding(padding: EdgeInsets.only(bottom: Sp.sm), child: LinearProgressIndicator(minHeight: 2)),
        if (groups.isEmpty && accounts.isEmpty) const KCard(child: EmptyState(icon: Icons.restore_from_trash_outlined, text: 'Nothing is deleted.')),
        if (groups.isNotEmpty) ...[
          const SectionTitle('Groups', top: 4),
          KGroup(children: [
            for (final g in groups)
              KRow(
                leading: EmojiBadge(g.emoji, name: g.name, size: 32),
                title: g.name,
                sub: '${kGroupKinds[g.kind] ?? g.kind}, ${_accounts(me.accounts.where((a) => a.groupId == g.id).length)}',
                trailing: can ? Icon(Icons.more_horiz_rounded, color: K.muted, size: 20) : null,
                onTap: can && !busy ? () => _group(g) : null,
              ),
          ]),
        ],
        if (accounts.isNotEmpty) ...[
          SectionTitle('Accounts', top: groups.isEmpty ? 4 : 20),
          KGroup(children: [
            for (final a in accounts)
              KRow(
                title: a.name,
                sub: '${a.group?.name ?? ''}${(a.group?.deleted ?? false) ? ' (deleted)' : ''}, ${a.currency}',
                trailing: can ? Icon(Icons.more_horiz_rounded, color: K.muted, size: 20) : null,
                onTap: can && !busy ? () => _account(a) : null,
              ),
          ]),
        ],
        const SizedBox(height: Sp.md),
        Text('Restoring brings an account back with its balance and entries. Deleting for good removes its entries too.', style: T.small),
      ]),
    );
  }
}

// ---------------------------------------------------------------- Transfer-Expense

class _TransferExpensePage extends StatefulWidget {
  const _TransferExpensePage();

  @override
  State<_TransferExpensePage> createState() => _TransferExpensePageState();
}

class _TransferExpensePageState extends State<_TransferExpensePage> with _Busy<_TransferExpensePage> {
  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: Me.instance, builder: (context, _) => _body(context));

  Widget _body(BuildContext context) {
    final me = Me.instance;
    final b = me.book;
    if (b == null) return const Scaffold(body: Loading());
    final can = b.canEdit;
    final list = me.liveAccounts.where((a) => a.canTransferExpense).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Transfer-Expense')),
      body: PageBody(children: [
        const Notice(
            'Money moved into an account switched on here counts as an expense, and money moved back out counts as income. '
            'Only savings, investment, loan and insurance accounts can do this.',
            bad: false),
        const SizedBox(height: Sp.md),
        if (list.isEmpty)
          const KCard(child: EmptyState(icon: Icons.savings_outlined, text: 'No savings, investment, loan or insurance accounts yet.'))
        else
          LinkGroup([
            for (final a in list)
              SwitchTile(
                title: a.name,
                sub: a.group?.label,
                value: a.transferExpense,
                onChanged: can && !busy
                    ? (v) => run(() async {
                          await Api.instance.update('accounts', {'transfer_expense': v}, where: {'id': 'eq.${a.id}'});
                        }, done: v ? 'Transfers into ${a.name} count as spent' : 'Transfers into ${a.name} are transfers again')
                    : null,
              ),
          ]),
      ]),
    );
  }
}
