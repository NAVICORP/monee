import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/book.dart';
import '../../core/format.dart';
import '../money.dart';
import '../theme.dart';
import '../widgets.dart';
import 'more_common.dart';

/// More > People in this book (the owner's page): who can open the book and
/// what they may do. A person added by email or WhatsApp number joins when
/// they sign in to Monee with it.
class PeoplePage extends StatefulWidget {
  const PeoplePage({super.key});

  @override
  State<PeoplePage> createState() => _PeoplePageState();
}

class _PeoplePageState extends State<PeoplePage> with ReloadOnChange<PeoplePage> {
  List<Map<String, dynamic>>? members;
  String? error;

  @override
  Future<void> reload() async {
    try {
      final r = await Api.instance.select('book_members', order: 'created_at');
      if (!mounted) return;
      setState(() {
        members = r;
        error = null;
      });
    } on ApiError catch (e) {
      if (mounted) setState(() => error = e.message);
    }
  }

  static String roleWord(String? r) => switch (r) { 'owner' => 'Owner', 'viewer' => 'Viewer', _ => 'Editor' };

  Future<void> _add() async {
    final added = await showKSheet<bool>(context, title: 'Add a person', builder: (ctx) => const _AddPerson());
    if (added == true && mounted) {
      toast(context, 'Added. They join when they sign in.');
      await Me.instance.changed();
    }
  }

  Future<void> _actions(Map<String, dynamic> m) async {
    final a = await pickAction(context, title: '${m['name']}', actions: const [
      PickOption('role', 'Change what they can do', icon: Icons.manage_accounts_outlined),
      PickOption('remove', 'Remove from this book', icon: Icons.person_remove_outlined),
    ]);
    if (!mounted) return;
    if (a == 'role') {
      final p = await showPicker<String>(context, title: 'They can', selected: m['role'] as String?, options: const [
        PickOption('editor', 'Edit', sub: 'Add, change and delete entries, accounts and categories'),
        PickOption('viewer', 'Only look', sub: 'See everything, change nothing'),
      ]);
      if (p == null || p.value == m['role'] || !mounted) return;
      await attempt(context, () async {
        await Api.instance.update('book_members', {'role': p.value}, where: {'id': 'eq.${m['id']}'});
        await Me.instance.changed();
      }, done: '${m['name']} is now ${roleWord(p.value).toLowerCase()}');
    }
    if (a == 'remove') {
      final ok = await confirm(context,
          title: 'Remove ${m['name']}?',
          text: 'They can no longer open this book. What they recorded stays.',
          yes: 'Remove',
          danger: true);
      if (!ok || !mounted) return;
      await attempt(context, () async {
        await Api.instance.delete('book_members', where: {'id': 'eq.${m['id']}'});
        await Me.instance.changed();
      }, done: '${m['name']} removed');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('People in this book')),
      body: _body(context),
    );
  }

  Widget _body(BuildContext context) {
    final b = Me.instance.book;
    if (b == null) return const Loading();
    final list = members;
    if (list == null) return error == null ? const Loading() : LoadFailed(message: error!, onRetry: reload);
    final owner = b.isOwner;
    return PageBody(onRefresh: reload, children: [
      const Notice(
          'Monee keeps one copy of this book on the server, so everyone in it sees the same accounts and entries on every device. '
          'Editors can add and change entries; viewers can only look.',
          bad: false),
      const SizedBox(height: Sp.md),
      KGroup(children: [
        for (final m in list)
          Builder(builder: (context) {
            final me = m['user_id'] != null && m['user_id'] == Me.instance.userId;
            final email = m['email'] as String?;
            final phone = m['phone'] as String?;
            final contact = email ?? (phone == null ? '' : prettyPhone(phone));
            final role = m['role'] as String?;
            return KRow(
              leading: Avatar('${m['name']}', size: 34),
              title: '${m['name']}${me ? ' (you)' : ''}',
              sub: [if (contact.isNotEmpty) contact, if (m['user_id'] == null) 'Not signed in yet'].join(', '),
              trailing: role == 'owner' ? const Pill('Owner') : (role == 'viewer' ? const Pill.grey('Viewer') : const Pill.grey('Editor')),
              onTap: owner && role != 'owner' ? () => _actions(m) : null,
            );
          }),
      ]),
      if (owner) ...[
        const SizedBox(height: Sp.md),
        Center(child: KButton(label: 'Add a person', icon: Icons.person_add_alt_rounded, kind: KButtonKind.secondary, small: true, onPressed: _add)),
        const SizedBox(height: Sp.md),
        const Text('They join when they sign in to Monee with that email or WhatsApp number. Only you, the owner, can add or remove people.', style: T.small),
      ] else
        const Padding(padding: EdgeInsets.only(top: Sp.md), child: Text('Only the book\'s owner can add or remove people.', style: T.small)),
    ]);
  }
}

class _AddPerson extends StatefulWidget {
  const _AddPerson();

  @override
  State<_AddPerson> createState() => _AddPersonState();
}

class _AddPersonState extends State<_AddPerson> {
  final _name = TextEditingController();
  final _contact = TextEditingController();
  bool byEmail = true;
  String role = 'editor';
  bool busy = false;
  String? error;

  @override
  void dispose() {
    _name.dispose();
    _contact.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final raw = _contact.text.trim();
    String? problem;
    final row = <String, dynamic>{'name': name, 'role': role};
    if (name.isEmpty || name.length > 60) problem = 'Add their name (up to 60 characters).';
    if (problem == null) {
      if (byEmail) {
        final e = raw.toLowerCase();
        if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(e)) {
          problem = 'That email does not look right.';
        } else {
          row['email'] = e;
        }
      } else {
        final d = phoneDigits(raw);
        if (d.length < 8 || d.length > 15) {
          problem = 'Type their WhatsApp number with the country code.';
        } else {
          row['phone'] = d;
        }
      }
    }
    if (problem != null) {
      setState(() => error = problem);
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await Api.instance.insert('book_members', row);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiError catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (error != null) ...[Notice(error!), const SizedBox(height: Sp.md)],
      KField(label: 'Their name', controller: _name, autofocus: true, caps: TextCapitalization.words),
      const SizedBox(height: Sp.md),
      KSegmented<bool>(
        expand: true,
        items: const [(true, 'Email'), (false, 'WhatsApp')],
        value: byEmail,
        onChanged: (v) => setState(() {
          byEmail = v;
          _contact.clear();
        }),
      ),
      const SizedBox(height: Sp.md),
      KField(
        label: byEmail ? 'Their email' : 'Their WhatsApp number',
        controller: _contact,
        hint: byEmail ? 'name@example.com' : '+91 98765 43210',
        keyboard: byEmail ? TextInputType.emailAddress : TextInputType.phone,
        caps: TextCapitalization.none,
        onSubmitted: (_) => _save(),
      ),
      const SizedBox(height: Sp.md),
      const Text('They can', style: T.label),
      const SizedBox(height: 6),
      KSegmented<String>(
        expand: true,
        items: const [('editor', 'Edit'), ('viewer', 'Only look')],
        value: role,
        onChanged: (v) => setState(() => role = v),
      ),
      const SizedBox(height: Sp.lg),
      KButton(label: 'Add', icon: Icons.person_add_alt_rounded, expand: true, busy: busy, onPressed: _save),
    ]);
  }
}
