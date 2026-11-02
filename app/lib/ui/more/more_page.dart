import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api.dart';
import '../../core/book.dart';
import '../../core/config.dart';
import '../../core/format.dart';
import '../entry/calculator.dart' show showCalculator;
import '../theme.dart';
import '../widgets.dart';
import 'account_settings.dart';
import 'budgets.dart';
import 'categories.dart';
import 'configuration.dart';
import 'currencies.dart';
import 'excel_io.dart';
import 'more_common.dart';
import 'passcode.dart';
import 'people.dart';
import 'repeats.dart';
import 'tags.dart';

/// The app's version as people see it (pubspec: version 1.0.0+1).
const String kAppVersion = '1.0.0';

/// The More tab, like Kuree's Profile: the book and who is signed in, then
/// labelled groups of settings, tools, help and the account.
class MorePage extends StatefulWidget {
  const MorePage({super.key});

  @override
  State<MorePage> createState() => _MorePageState();
}

class _MorePageState extends State<MorePage> {
  @override
  void initState() {
    super.initState();
    Passcode.load().then((_) {
      if (mounted) setState(() {});
    });
  }

  /// Opens a page, and shows what changed (the passcode) on coming back.
  Future<void> _open(Widget page) async {
    await openPage<void>(context, page);
    if (mounted) setState(() {});
  }

  Future<void> _calculator() async {
    final v = await showCalculator(context, currency: Me.instance.book?.currency);
    if (v == null || !mounted) return;
    final text = plainNumber(v);
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) toast(context, '$text copied');
  }

  Future<void> _link(String url) async {
    var ok = false;
    try {
      ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      ok = false;
    }
    if (!ok && mounted) toast(context, 'That page did not open. Visit $url', bad: true);
  }

  Future<void> _feedback() async {
    var ok = false;
    try {
      ok = await launchUrl(Uri.parse('mailto:$kSupportEmail?subject=${Uri.encodeComponent('Monee feedback')}'));
    } catch (_) {
      ok = false;
    }
    if (!ok && mounted) toast(context, 'Write to us at $kSupportEmail');
  }

  Future<void> _share() async {
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null || !box.hasSize ? null : box.localToGlobal(Offset.zero) & box.size;
    Passcode.holdBriefly();
    try {
      await SharePlus.instance.share(ShareParams(
        text: 'I keep track of my money with Monee: accounts, budgets and stats on my phone and my computer. $kSite',
        subject: 'Monee',
        sharePositionOrigin: origin,
      ));
    } catch (_) {
      if (mounted) toast(context, 'Sharing did not open.', bad: true);
    }
  }

  Future<void> _computer() async {
    await showKSheet<void>(context, title: 'Open on your computer', builder: (ctx) => const _ComputerSheet());
  }

  Future<void> _leave() async {
    final b = Me.instance.book;
    final uid = Me.instance.userId;
    if (b == null || uid == null) return;
    final ok = await confirm(context,
        title: 'Leave ${b.name}?',
        text: 'You can no longer open it. What you recorded in it stays, and the owner can add you again.',
        yes: 'Leave',
        danger: true);
    if (!ok || !mounted) return;
    try {
      await Api.instance.delete('book_members', where: {'user_id': 'eq.$uid'});
      await Me.instance.load();
    } on ApiError catch (e) {
      if (mounted) toast(context, e.message, bad: true);
    }
  }

  Future<void> _signOut() async {
    final ok = await confirm(context, title: 'Sign out?', text: 'You can sign in again any time. The passcode on this device is removed.', yes: 'Sign out');
    if (!ok) return;
    await Passcode.clear();
    await Api.instance.signOut();
  }

  Future<void> _deleteAccount() async {
    final first = await confirm(context,
        title: 'Delete your account?',
        text: 'Every book you own is deleted with all its entries, and you leave the books others shared with you. '
            'Your SkiFi sign-in stays for other SkiFi apps.',
        yes: 'Continue',
        danger: true);
    if (!first || !mounted) return;
    final second = await confirm(context,
        title: 'Are you sure?', text: 'This cannot be undone. Export to Excel first if you want a copy.', yes: 'Delete my account', danger: true);
    if (!second || !mounted) return;
    try {
      await Api.instance.deleteAccount();
      await Passcode.clear();
    } on ApiError catch (e) {
      if (mounted) toast(context, e.message, bad: true);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: Me.instance, builder: (context, _) => _body(context));

  Widget _body(BuildContext context) {
    final me = Me.instance;
    final b = me.book;
    if (b == null) return const Scaffold(body: Loading());
    final who = me.phone != null ? prettyPhone(me.phone) : (me.email ?? '');
    final subs = me.rates.keys.toList()..sort();
    return Scaffold(
      appBar: AppBar(titleSpacing: Sp.xl, title: const Text('More')),
      body: PageBody(bottom: 40, children: [
        KCard(
          onTap: () => _open(const ConfigurationPage()),
          child: Row(children: [
            const MoneeIcon(size: 46),
            const SizedBox(width: Sp.md + 2),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(b.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: T.h3),
                Text(
                    b.isOwner
                        ? 'Main currency ${b.main.code}'
                        : '${b.canEdit ? 'Shared with you to edit' : 'Shared with you to look at'}, ${b.main.code}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: T.small),
                if (who.isNotEmpty) Text('Signed in as $who', maxLines: 1, overflow: TextOverflow.ellipsis, style: T.small),
              ]),
            ),
            const SizedBox(width: Sp.xs),
            const Icon(Icons.chevron_right_rounded, color: K.border2),
          ]),
        ),
        if (me.books.length > 1) ...[
          const SizedBox(height: Sp.md),
          LinkGroup([
            LinkRow(Icons.swap_horiz_rounded, 'Switch book', () => switchBook(context), value: '${me.books.length} books'),
          ]),
        ],
        const GroupLabel('Book'),
        LinkGroup([
          LinkRow(Icons.tune_rounded, 'Configuration', () => _open(const ConfigurationPage()), sub: 'Currency, periods, carry-over and more'),
          LinkRow(Icons.south_west_rounded, 'Income categories', () => _open(const CategoriesPage(kind: 'income'))),
          LinkRow(Icons.north_east_rounded, 'Expense categories', () => _open(const CategoriesPage(kind: 'expense'))),
          LinkRow(Icons.savings_outlined, 'Budgets', () => _open(const BudgetsPage())),
          LinkRow(Icons.sell_outlined, 'Tags', () => _open(const TagsPage()), value: me.tags.isEmpty ? null : '${me.tags.length}'),
          LinkRow(Icons.event_repeat_rounded, 'Repeats', () => _open(const RepeatsPage())),
          LinkRow(Icons.currency_exchange_rounded, 'Currencies', () => _open(const CurrenciesPage()), value: [b.currency, ...subs].join(', ')),
        ]),
        const GroupLabel('Accounts'),
        LinkGroup([
          LinkRow(Icons.account_balance_wallet_outlined, 'Accounts settings', () => _open(const AccountSettingsPage()),
              sub: 'Groups, deleted accounts, Transfer-Expense, cards'),
        ]),
        const GroupLabel('Security'),
        LinkGroup([
          LinkRow(Icons.lock_outline_rounded, 'Passcode', () => _open(const PasscodeSettingsPage()), value: Passcode.isOn ? 'On' : 'Off'),
        ]),
        const GroupLabel('Tools'),
        LinkGroup([
          LinkRow(Icons.calculate_outlined, 'Calculator', _calculator, sub: 'The answer is copied for you'),
          LinkRow(Icons.ios_share_rounded, 'Export to Excel', () => exportToExcel(context)),
          if (b.canEdit) LinkRow(Icons.upload_file_rounded, 'Import from Excel', () => importFromExcel(context), sub: 'A Monee or Money Manager sheet'),
          LinkRow(Icons.computer_rounded, 'Open on your computer', _computer, sub: 'The same books in your browser'),
        ]),
        const GroupLabel('Sharing'),
        LinkGroup([
          if (b.isOwner)
            LinkRow(Icons.group_outlined, 'People in this book', () => _open(const PeoplePage()), sub: 'Family or a partner, all in sync')
          else
            LinkRow(Icons.logout_rounded, 'Leave this book', _leave, sub: 'Shared with you by its owner'),
        ]),
        const GroupLabel('Help'),
        LinkGroup([
          LinkRow(Icons.support_agent_rounded, 'Help and support', () => _link(kSupportUrl)),
          LinkRow(Icons.mail_outline_rounded, 'Send feedback', _feedback),
          LinkRow(Icons.favorite_border_rounded, 'Share Monee', _share),
          LinkRow(Icons.privacy_tip_outlined, 'Privacy', () => _link(kPrivacyUrl)),
          LinkRow(Icons.description_outlined, 'Terms', () => _link(kTermsUrl)),
        ]),
        const GroupLabel('Account'),
        LinkGroup([
          if (me.email != null)
            LinkRow(Icons.password_rounded, 'Choose a password', () => _open(const _PasswordPage()), sub: 'Sign in with your email and a password, no code'),
          LinkRow(Icons.logout_rounded, 'Sign out', _signOut),
          LinkRow(Icons.delete_outline_rounded, 'Delete my account', _deleteAccount, bad: true),
        ]),
        const SizedBox(height: Sp.xl),
        const Center(child: Text('Monee $kAppVersion', style: T.small)),
      ]),
    );
  }
}

/// The web app's address, to open the same books on a computer.
class _ComputerSheet extends StatefulWidget {
  const _ComputerSheet();

  @override
  State<_ComputerSheet> createState() => _ComputerSheetState();
}

class _ComputerSheetState extends State<_ComputerSheet> {
  bool copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: kWebAppUrl));
    if (mounted) setState(() => copied = true);
  }

  Future<void> _openIt() async {
    try {
      await launchUrl(Uri.parse(kWebAppUrl), mode: LaunchMode.externalApplication);
    } catch (_) {
      // The address is on screen to type.
    }
  }

  @override
  Widget build(BuildContext context) {
    final how = Me.instance.email != null ? 'email' : 'WhatsApp number';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Monee works in any browser. Open this address on your computer and sign in with the same $how: '
          'your books, accounts and entries are the same there, and changes show on both.',
          style: T.body.copyWith(color: K.ink2)),
      const SizedBox(height: Sp.md),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(color: K.surface, borderRadius: BorderRadius.circular(K.rMd), border: Border.all(color: K.border2)),
        child: SelectableText(kWebAppUrl, style: T.bodyStrong.copyWith(color: K.blue)),
      ),
      const SizedBox(height: Sp.md),
      Row(children: [
        Expanded(
          child: KButton(
            label: copied ? 'Copied' : 'Copy',
            icon: copied ? Icons.check_rounded : Icons.copy_rounded,
            kind: KButtonKind.secondary,
            expand: true,
            onPressed: _copy,
          ),
        ),
        const SizedBox(width: Sp.sm),
        Expanded(child: KButton(label: 'Open', icon: Icons.open_in_new_rounded, expand: true, onPressed: _openIt)),
      ]),
      const SizedBox(height: Sp.sm),
      const Text('It takes the place of a PC manager: no Wi-Fi pairing, and it works from anywhere.', style: T.small),
    ]);
  }
}

/// A password for the signed-in email, to sign in without a code.
class _PasswordPage extends StatefulWidget {
  const _PasswordPage();

  @override
  State<_PasswordPage> createState() => _PasswordPageState();
}

class _PasswordPageState extends State<_PasswordPage> {
  final _a = TextEditingController();
  final _b = TextEditingController();
  bool busy = false;
  String? error;

  @override
  void dispose() {
    _a.dispose();
    _b.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_a.text.length < 8) {
      setState(() => error = 'Choose a password of at least 8 characters.');
      return;
    }
    if (_a.text != _b.text) {
      setState(() => error = 'The two passwords are not the same.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await Api.instance.setPassword(_a.text);
      if (!mounted) return;
      toast(context, 'Password saved');
      Navigator.of(context).pop();
    } on ApiError catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Choose a password')),
      body: PageBody(maxWidth: 440, children: [
        Text('Next time, sign in with ${Me.instance.email ?? 'your email'} and this password instead of a code.', style: T.body.copyWith(color: K.muted)),
        const SizedBox(height: Sp.lg),
        KCard(
          padding: const EdgeInsets.all(Sp.xl),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (error != null) ...[Notice(error!), const SizedBox(height: Sp.md)],
            KField(label: 'New password', controller: _a, obscure: true, caps: TextCapitalization.none, autofill: const [AutofillHints.newPassword]),
            const SizedBox(height: Sp.md),
            KField(label: 'Once more', controller: _b, obscure: true, caps: TextCapitalization.none, onSubmitted: (_) => _save()),
            const SizedBox(height: Sp.lg),
            KButton(label: 'Save my password', icon: Icons.check_rounded, expand: true, busy: busy, onPressed: _save),
          ]),
        ),
      ]),
    );
  }
}
