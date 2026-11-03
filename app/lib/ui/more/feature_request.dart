import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../theme.dart';
import '../widgets.dart';
import 'more_page.dart' show kAppVersion;

// Asking for something new from inside the app, and the team's inbox of
// every request. The same as Kuree's: request_feature, my_feature_requests,
// all_feature_requests and set_feature_request_status on the server.

String _statusLabel(String s) => switch (s) {
      'planned' => 'Planned',
      'done' => 'Done',
      'declined' => 'Declined',
      _ => 'New',
    };

String _importanceLabel(String? s) => switch (s) {
      'nice' => 'Nice to have',
      'important' => 'Important',
      'must' => 'Must have',
      _ => '',
    };

/// One request as the server sends it.
class FeatureRequest {
  FeatureRequest(this.j);
  final Map<String, dynamic> j;

  int get id => (j['id'] as num).toInt();
  String get title => (j['title'] as String?) ?? '';
  String get details => (j['details'] as String?) ?? '';
  String? get importance => j['importance'] as String?;
  String get status => (j['status'] as String?) ?? 'new';
  String get note => (j['owner_note'] as String?) ?? '';
  DateTime get created => DateTime.tryParse((j['created_at'] as String?) ?? '')?.toLocal() ?? DateTime.now();
  String get name => (j['name'] as String?) ?? '';
  String get email => (j['email'] as String?) ?? '';
  String get phone => (j['phone'] as String?) ?? '';
  String get platform => (j['platform'] as String?) ?? '';
  String get version => (j['app_version'] as String?) ?? '';
  bool get signedUp => j['signed_up'] != false;

  static List<FeatureRequest> list(dynamic j) =>
      j is List ? [for (final x in j) if (x is Map) FeatureRequest(Map<String, dynamic>.from(x))] : const [];
}

/// The calls behind the pages.
class FeatureRequests {
  static String get platform {
    if (kIsWeb) return 'web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      _ => 'other',
    };
  }

  /// True for the people who make Pursee, who may read every request (the
  /// inbox shows only for them).
  static Future<bool> isOwner() async {
    try {
      return await Api.instance.rpc('feature_owner') == true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> send({required String title, required String details, String? importance}) async {
    await Api.instance.rpc('request_feature', {
      'title': title,
      'details': details,
      'importance': importance,
      'app_version': kAppVersion,
      'platform': platform,
      'language': 'en',
    });
  }

  static Future<List<FeatureRequest>> mine() async => FeatureRequest.list(await Api.instance.rpc('my_feature_requests'));

  static Future<(Map<String, int>, List<FeatureRequest>)> all({String? status}) async {
    final r = await Api.instance.rpc('all_feature_requests', {'status': status});
    final counts = <String, int>{};
    if (r is Map && r['counts'] is Map) {
      for (final e in (r['counts'] as Map).entries) {
        counts['${e.key}'] = e.value is num ? (e.value as num).toInt() : 0;
      }
    }
    return (counts, FeatureRequest.list(r is Map ? r['requests'] : null));
  }

  static Future<void> setStatus(int id, String status, String note) async {
    await Api.instance.rpc('set_feature_request_status', {'id': id, 'status': status, 'note': note});
  }
}

// ---------------------------------------------------------------- asking

/// Where anyone asks for something new and follows what happened to it.
class FeatureRequestPage extends StatefulWidget {
  const FeatureRequestPage({super.key});

  @override
  State<FeatureRequestPage> createState() => _FeatureRequestPageState();
}

class _FeatureRequestPageState extends State<FeatureRequestPage> {
  final _title = TextEditingController();
  final _details = TextEditingController();
  String? _importance;
  bool _sending = false;
  bool _sent = false;
  String? _error;
  List<FeatureRequest>? _mine;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _title.dispose();
    _details.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final m = await FeatureRequests.mine();
      if (mounted) setState(() => _mine = m);
    } catch (_) {
      if (mounted) setState(() => _mine ??= const []);
    }
  }

  Future<void> _send() async {
    final title = _title.text.trim();
    if (title.length < 3) {
      setState(() => _error = 'Give your idea a short title.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await FeatureRequests.send(title: title, details: _details.text.trim(), importance: _importance);
      if (!mounted) return;
      setState(() {
        _sending = false;
        _sent = true;
        _title.clear();
        _details.clear();
        _importance = null;
      });
      _load();
    } on ApiError catch (e) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = 'That did not send. Check the connection and try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final mine = _mine;
    return Scaffold(
      appBar: AppBar(title: const Text('Request a feature')),
      body: PageBody(bottom: 40, children: [
        HeroCard(
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(color: K.glow, borderRadius: BorderRadius.circular(15)),
              child: Icon(Icons.lightbulb_outline_rounded, color: K.deep, size: 25),
            ),
            const SizedBox(width: Sp.md + 2),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Tell us what would help', style: T.h2.copyWith(color: Colors.white)),
                const SizedBox(height: 6),
                Text('An idea, something that gets in the way, a feature you miss. We read every request.',
                    style: T.body.copyWith(color: K.heroText)),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: Sp.lg),
        AnimatedSwitcher(duration: const Duration(milliseconds: 240), child: _sent ? _thanks() : _form()),
        const SectionTitle('Your requests'),
        if (mine == null)
          const Padding(padding: EdgeInsets.all(24), child: Loading())
        else if (mine.isEmpty)
          KCard(child: EmptyState(icon: Icons.inbox_outlined, text: 'Your requests will show here, with what the team decides.'))
        else
          for (final r in mine) Padding(padding: const EdgeInsets.only(bottom: 10), child: _RequestCard(r)),
      ]),
    );
  }

  Widget _form() {
    return KCard(
      key: const ValueKey('form'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        KField(
          label: 'Your idea in a few words',
          controller: _title,
          hint: 'For example: split one bill between cash and card',
          formatters: [LengthLimitingTextInputFormatter(100)],
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
        ),
        const SizedBox(height: Sp.md),
        KField(
          label: 'Tell us more (optional)',
          controller: _details,
          hint: 'How would you use it? What happens today?',
          maxLines: 6,
          keyboard: TextInputType.multiline,
          formatters: [LengthLimitingTextInputFormatter(2000)],
        ),
        const SizedBox(height: Sp.lg),
        Text('How much would it help?', style: T.label),
        const SizedBox(height: Sp.sm),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final v in const ['nice', 'important', 'must'])
            _Choice(
              label: _importanceLabel(v),
              selected: _importance == v,
              onTap: () => setState(() => _importance = _importance == v ? null : v),
            ),
        ]),
        if (_error != null) ...[const SizedBox(height: Sp.md), Notice(_error!)],
        const SizedBox(height: Sp.lg),
        KButton(label: 'Send request', icon: Icons.send_rounded, expand: true, busy: _sending, onPressed: _send),
      ]),
    );
  }

  Widget _thanks() {
    return KCard(
      key: const ValueKey('thanks'),
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 22),
      child: Column(children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(color: K.brand100, shape: BoxShape.circle),
          child: Icon(Icons.favorite_rounded, color: K.blue, size: 28),
        ),
        const SizedBox(height: Sp.md),
        Text('Thank you!', style: T.h2, textAlign: TextAlign.center),
        const SizedBox(height: 6),
        Text('Your request reached the Pursee team. You can follow it below.',
            style: T.body.copyWith(color: K.muted), textAlign: TextAlign.center),
        const SizedBox(height: Sp.lg),
        KButton(label: 'Send another', icon: Icons.add_rounded, kind: KButtonKind.secondary, onPressed: () => setState(() => _sent = false)),
      ]),
    );
  }
}

/// A rounded choice that fills in when picked.
class _Choice extends StatelessWidget {
  const _Choice({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? K.deep : K.surface,
      shape: StadiumBorder(side: BorderSide(color: selected ? K.deep : K.border2)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 42),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (selected) ...[Icon(Icons.check_rounded, size: 17, color: K.glow), const SizedBox(width: 6)],
              Text(label, style: T.label.copyWith(color: selected ? Colors.white : K.ink2)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill(this.status);
  final String status;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, icon) = switch (status) {
      'planned' => (K.warnBg, K.warn, Icons.event_available_rounded),
      'done' => (K.incomeBg, K.income, Icons.check_circle_rounded),
      'declined' => (K.surface2, K.muted, Icons.do_not_disturb_on_outlined),
      _ => (K.brand100, K.brand600, Icons.fiber_new_rounded),
    };
    return Pill(_statusLabel(status), color: bg, fg: fg, icon: icon);
  }
}

/// The team's reply under a request.
class _Reply extends StatelessWidget {
  const _Reply(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: K.ice,
        borderRadius: const BorderRadiusDirectional.only(
          topStart: Radius.circular(6),
          topEnd: Radius.circular(18),
          bottomStart: Radius.circular(18),
          bottomEnd: Radius.circular(18),
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('From the Pursee team', style: T.tiny.copyWith(color: K.brand600)),
        const SizedBox(height: 4),
        Text(text, style: T.body),
      ]),
    );
  }
}

/// One of my requests, with its status and the team's reply.
class _RequestCard extends StatelessWidget {
  const _RequestCard(this.r);
  final FeatureRequest r;

  @override
  Widget build(BuildContext context) {
    final imp = _importanceLabel(r.importance);
    return KCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Text(r.title, style: T.bodyStrong)),
          const SizedBox(width: 10),
          _StatusPill(r.status),
        ]),
        if (r.details.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(r.details, style: T.body.copyWith(color: K.ink2), maxLines: 4, overflow: TextOverflow.ellipsis),
        ],
        const SizedBox(height: 8),
        Text(imp.isEmpty ? dateLabel(r.created) : '${dateLabel(r.created)}, $imp', style: T.small),
        if (r.note.isNotEmpty) ...[const SizedBox(height: 12), _Reply(r.note)],
      ]),
    );
  }
}

// ---------------------------------------------------------------- the team's inbox

/// Every request, for the Pursee team. Opened only when
/// [FeatureRequests.isOwner] is true; the server refuses everyone else.
class FeatureInboxPage extends StatefulWidget {
  const FeatureInboxPage({super.key});

  @override
  State<FeatureInboxPage> createState() => _FeatureInboxPageState();
}

class _FeatureInboxPageState extends State<FeatureInboxPage> {
  String? _filter;
  Map<String, int> _counts = const {};
  List<FeatureRequest>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final (counts, items) = await FeatureRequests.all(status: _filter);
      if (mounted) {
        setState(() {
          _counts = counts;
          _items = items;
          _error = null;
        });
      }
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'The requests could not be loaded. Try again.');
    }
  }

  void _pick(String? f) {
    if (f == _filter) return;
    setState(() {
      _filter = f;
      _items = null;
    });
    _load();
  }

  Future<void> _open(FeatureRequest r) async {
    final changed = await showKSheet<bool>(context, title: 'Update the request', builder: (ctx) => _StatusSheet(r));
    if (changed == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    const filters = <(String?, String)>[(null, 'All'), ('new', 'New'), ('planned', 'Planned'), ('done', 'Done'), ('declined', 'Declined')];
    final items = _items;
    Widget body;
    if (_error != null && items == null) {
      body = LoadFailed(
          message: _error!,
          onRetry: () {
            setState(() => _error = null);
            _load();
          });
    } else if (items == null) {
      body = const Loading();
    } else {
      body = RefreshIndicator(
        onRefresh: _load,
        color: K.blue,
        child: ListView(
          padding: EdgeInsets.fromLTRB(Sp.page, 4, Sp.page, 40 + MediaQuery.paddingOf(context).bottom),
          children: [
            if (items.isEmpty)
              const Padding(padding: EdgeInsets.only(top: 40), child: EmptyState(icon: Icons.inbox_outlined, text: 'No requests here yet.'))
            else
              for (final r in items) Padding(padding: const EdgeInsets.only(bottom: 10), child: _InboxCard(r, onTap: () => _open(r))),
          ],
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Feature requests')),
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          height: 58,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(Sp.page, 6, Sp.page, 8),
            children: [
              for (final (v, label) in filters)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: _Choice(label: '$label ${_counts[v ?? 'all'] ?? 0}', selected: _filter == v, onTap: () => _pick(v)),
                ),
            ],
          ),
        ),
        Expanded(child: body),
      ]),
    );
  }
}

/// One request in the inbox: what, who, when, and its status.
class _InboxCard extends StatelessWidget {
  const _InboxCard(this.r, {required this.onTap});
  final FeatureRequest r;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final who = r.signedUp
        ? [r.name, r.email.isNotEmpty ? r.email : (r.phone.isNotEmpty ? prettyPhone(r.phone) : '')]
            .where((s) => s.isNotEmpty)
            .toSet()
            .join(', ')
        : 'Account deleted';
    final meta = [
      dateLabel(r.created),
      _importanceLabel(r.importance),
      [r.platform, r.version].where((s) => s.isNotEmpty).join(' '),
    ].where((s) => s.isNotEmpty).join(', ');
    return KCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Text(r.title, style: T.bodyStrong)),
          const SizedBox(width: 10),
          _StatusPill(r.status),
        ]),
        if (r.details.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(r.details, style: T.body.copyWith(color: K.ink2), maxLines: 5, overflow: TextOverflow.ellipsis),
        ],
        const SizedBox(height: 10),
        Row(children: [
          Icon(Icons.person_outline_rounded, size: 16, color: K.muted),
          const SizedBox(width: 6),
          Expanded(child: Text('From ${who.isEmpty ? 'someone' : who}', style: T.small, maxLines: 1, overflow: TextOverflow.ellipsis)),
        ]),
        const SizedBox(height: 4),
        Text(meta, style: T.tiny),
        if (r.note.isNotEmpty) ...[const SizedBox(height: 12), _Reply(r.note)],
      ]),
    );
  }
}

/// The team changes a request's status and leaves a note for whoever asked.
class _StatusSheet extends StatefulWidget {
  const _StatusSheet(this.r);
  final FeatureRequest r;

  @override
  State<_StatusSheet> createState() => _StatusSheetState();
}

class _StatusSheetState extends State<_StatusSheet> {
  late String _status = widget.r.status;
  late final TextEditingController _note = TextEditingController(text: widget.r.note);
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await FeatureRequests.setStatus(widget.r.id, _status, _note.text.trim());
      if (!mounted) return;
      toast(context, 'Saved');
      Navigator.of(context).pop(true);
    } on ApiError catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(widget.r.title, style: T.h3),
      if (widget.r.details.isNotEmpty) ...[
        const SizedBox(height: 6),
        Text(widget.r.details, style: T.body.copyWith(color: K.ink2)),
      ],
      const SizedBox(height: Sp.lg),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final s in const ['new', 'planned', 'done', 'declined'])
          _Choice(label: _statusLabel(s), selected: _status == s, onTap: () => setState(() => _status = s)),
      ]),
      const SizedBox(height: Sp.lg),
      KField(
          label: 'Note for the person who asked (optional)',
          controller: _note,
          hint: 'For example: coming in the next update',
          maxLines: 4,
          formatters: [LengthLimitingTextInputFormatter(500)]),
      if (_error != null) ...[const SizedBox(height: 10), Notice(_error!)],
      const SizedBox(height: Sp.md),
      KButton(label: 'Save', icon: Icons.check_rounded, expand: true, busy: _saving, onPressed: _save),
    ]);
  }
}
