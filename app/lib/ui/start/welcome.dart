import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api.dart';
import '../../core/config.dart';
import '../../core/format.dart';
import '../theme.dart';
import '../widgets.dart';

/// Country codes for mobile numbers.
const kCountries = <(String, String)>[
  ('91', 'India'),
  ('971', 'UAE'),
  ('966', 'Saudi Arabia'),
  ('974', 'Qatar'),
  ('965', 'Kuwait'),
  ('968', 'Oman'),
  ('973', 'Bahrain'),
  ('94', 'Sri Lanka'),
  ('977', 'Nepal'),
  ('880', 'Bangladesh'),
  ('92', 'Pakistan'),
  ('254', 'Kenya'),
  ('1', 'United States'),
  ('44', 'United Kingdom'),
  ('61', 'Australia'),
];

/// A number typed after a country code, as digits with the code. Someone who
/// types their own +44 overrides the picker.
String fullPhone(String cc, String raw) {
  final t = raw.trim();
  final own = t.startsWith('+') || t.startsWith('00');
  var d = t.replaceAll(RegExp(r'[^0-9]'), '');
  if (t.startsWith('00')) d = d.substring(2);
  if (!own) d = cc + d.replaceFirst(RegExp(r'^0+'), '');
  return d.length >= 8 && d.length <= 15 ? d : '';
}

/// The country code and the number, left to right.
class PhoneField extends StatelessWidget {
  const PhoneField({super.key, required this.cc, required this.onCc, required this.controller, this.onSubmitted, this.autofocus = true});
  final String cc;
  final ValueChanged<String> onCc;
  final TextEditingController controller;
  final VoidCallback? onSubmitted;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Row(children: [
        Material(
          color: K.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: K.border2)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () async {
              final picked = await showPicker<String>(context,
                  title: 'Country code', selected: cc, options: [for (final c in kCountries) PickOption(c.$1, c.$2, trailing: '+${c.$1}')]);
              if (picked != null) onCc(picked.value);
            },
            child: SizedBox(
              height: 46,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('+$cc', style: T.bodyStrong),
                  Icon(Icons.expand_more_rounded, size: 18, color: K.muted),
                ]),
              ),
            ),
          ),
        ),
        const SizedBox(width: Sp.sm),
        Expanded(
          child: TextField(
            controller: controller,
            autofocus: autofocus,
            keyboardType: TextInputType.phone,
            autofillHints: const [AutofillHints.telephoneNumberNational],
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]'))],
            style: T.bodyStrong,
            decoration: const InputDecoration(hintText: 'Mobile number'),
            onSubmitted: (_) => onSubmitted?.call(),
          ),
        ),
      ]),
    );
  }
}

/// The first screen: what Pursee is, and signing in.
class Welcome extends StatelessWidget {
  const Welcome({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(children: [
        Positioned(
          top: -220,
          left: -100,
          right: -100,
          child: Container(
            height: 520,
            decoration: const BoxDecoration(gradient: RadialGradient(colors: [Color(0x266D4AE8), Color(0x006D4AE8)], radius: 0.6)),
          ),
        ),
        SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(Sp.xl, Sp.xl, Sp.xl, Sp.xxl),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const Center(child: MoneeIcon(size: 84, shadow: true)),
                  const SizedBox(height: 16),
                  Text('Pursee', textAlign: TextAlign.center, style: T.display),
                  const SizedBox(height: 4),
                  Text('Your money, accounts, budgets and stats.\nThe same book on your phone and computer.',
                      textAlign: TextAlign.center, style: T.body.copyWith(color: K.muted)),
                  const SizedBox(height: 22),
                  const SignIn(),
                  const SizedBox(height: Sp.md),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    _link('Privacy', kPrivacyUrl),
                    _link('Terms', kTermsUrl),
                    _link('Support', kSupportUrl),
                  ]),
                ]),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _link(String text, String url) => Semantics(
        link: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            child: Text(text, style: T.small.copyWith(decoration: TextDecoration.underline, decorationColor: K.muted)),
          ),
        ),
      );
}

// ---------------------------------------------------------------- signing in

enum _Step { start, phone, phoneCode, email, emailCode, password }

class SignIn extends StatefulWidget {
  const SignIn({super.key});

  @override
  State<SignIn> createState() => _SignInState();
}

class _SignInState extends State<SignIn> {
  _Step step = _Step.start;
  String cc = '91';
  String phone = '';
  String email = '';
  String? error;
  bool busy = false;
  int wait = 0;
  Timer? _timer;
  final _num = TextEditingController();
  final _mail = TextEditingController();
  final _code = TextEditingController();
  final _pass = TextEditingController();

  @override
  void dispose() {
    _timer?.cancel();
    _num.dispose();
    _mail.dispose();
    _code.dispose();
    _pass.dispose();
    super.dispose();
  }

  void _go(_Step s) => setState(() {
        step = s;
        error = null;
        _code.clear();
      });

  void _startWait() {
    _timer?.cancel();
    setState(() => wait = 30);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => wait = wait > 0 ? wait - 1 : 0);
      if (wait == 0) t.cancel();
    });
  }

  Future<void> _run(Future<void> Function() job) async {
    if (busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await job();
    } on ApiError catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (e) {
      if (mounted) setState(() => error = 'Something went wrong. Try again.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _sendPhone() => _run(() async {
        final p = fullPhone(cc, _num.text);
        if (p.isEmpty) throw ApiError('Enter your WhatsApp number.');
        await Api.instance.sendWhatsAppCode(p);
        phone = p;
        _go(_Step.phoneCode);
        _startWait();
      });

  Future<void> _sendEmail() => _run(() async {
        final e = _mail.text.trim().toLowerCase();
        if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(e)) throw ApiError('That email does not look right.');
        await Api.instance.sendEmailCode(e);
        email = e;
        _go(_Step.emailCode);
        _startWait();
      });

  Future<void> _verify() => _run(() async {
        final c = _code.text.replaceAll(RegExp(r'[^0-9]'), '');
        if (c.length != 6) throw ApiError('Enter the 6 digit code.');
        if (step == _Step.phoneCode) {
          await Api.instance.verifyWhatsAppCode(phone, c);
        } else {
          await Api.instance.verifyEmailCode(email, c);
        }
      });

  Future<void> _password() => _run(() async {
        final e = _mail.text.trim().toLowerCase();
        if (e.isEmpty || _pass.text.isEmpty) throw ApiError('Enter your email and password.');
        await Api.instance.signInWithPassword(e, _pass.text);
      });

  @override
  Widget build(BuildContext context) {
    return KCard(
      padding: const EdgeInsets.fromLTRB(Sp.xl, 20, Sp.xl, Sp.lg),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (error != null) ...[Notice(error!), const SizedBox(height: 14)],
        ..._form(),
        if (step != _Step.start) ...[
          const SizedBox(height: Sp.xs),
          Center(child: KButton(label: 'Back', icon: Icons.arrow_back_rounded, kind: KButtonKind.ghost, small: true, onPressed: busy ? null : () => _go(_Step.start))),
        ],
      ]),
    );
  }

  Widget _ghosts(List<Widget> buttons) => Wrap(alignment: WrapAlignment.center, spacing: Sp.xs, runSpacing: Sp.xs, children: buttons);

  List<Widget> _form() {
    switch (step) {
      case _Step.start:
        return [
          KButton(label: 'Continue with WhatsApp', icon: Icons.chat_rounded, expand: true, onPressed: () => _go(_Step.phone)),
          const SizedBox(height: Sp.md - 2),
          KButton(label: 'Use email instead', icon: Icons.mail_outline_rounded, kind: KButtonKind.secondary, expand: true, onPressed: () => _go(_Step.email)),
        ];
      case _Step.phone:
        return [
          Text('Your WhatsApp number', style: T.label),
          const SizedBox(height: Sp.sm),
          PhoneField(cc: cc, onCc: (v) => setState(() => cc = v), controller: _num, onSubmitted: _sendPhone),
          const SizedBox(height: Sp.lg),
          KButton(label: 'Send me a code on WhatsApp', icon: Icons.send_rounded, expand: true, busy: busy, onPressed: _sendPhone),
          const SizedBox(height: 4),
          _ghosts([KButton(label: 'Use email instead', kind: KButtonKind.ghost, small: true, onPressed: () => _go(_Step.email))]),
        ];
      case _Step.phoneCode:
      case _Step.emailCode:
        final wa = step == _Step.phoneCode;
        return [
          Text.rich(TextSpan(style: T.body.copyWith(color: K.ink2), children: [
            TextSpan(text: wa ? 'We sent a 6 digit code on WhatsApp to ' : 'We emailed a 6 digit code to '),
            TextSpan(text: wa ? prettyPhone(phone) : email, style: const TextStyle(fontWeight: FontWeight.w800)),
            const TextSpan(text: '.'),
          ])),
          const SizedBox(height: 14),
          TextField(
            controller: _code,
            autofocus: true,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            autofillHints: const [AutofillHints.oneTimeCode],
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
            style: const TextStyle(fontFamily: 'Manrope', fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: 0).merge(T.tabular),
            decoration: const InputDecoration(hintText: '000000'),
            onChanged: (v) {
              if (v.length == 6) _verify();
            },
            onSubmitted: (_) => _verify(),
          ),
          const SizedBox(height: Sp.lg),
          KButton(label: 'Sign in', icon: Icons.check_rounded, expand: true, busy: busy, onPressed: _verify),
          const SizedBox(height: 4),
          _ghosts([
            KButton(
              label: wait > 0 ? 'Send again in ${wait}s' : 'Send again',
              kind: KButtonKind.ghost,
              small: true,
              onPressed: wait > 0 || busy ? null : (wa ? _sendPhone : _sendEmail),
            ),
            KButton(label: wa ? 'Another number' : 'Another email', kind: KButtonKind.ghost, small: true, onPressed: () => _go(wa ? _Step.phone : _Step.email)),
          ]),
        ];
      case _Step.email:
        return [
          Text('Email', style: T.label),
          const SizedBox(height: Sp.sm),
          TextField(
            controller: _mail,
            autofocus: true,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            textCapitalization: TextCapitalization.none,
            autofillHints: const [AutofillHints.email],
            style: T.bodyStrong,
            decoration: const InputDecoration(hintText: 'you@example.com'),
            onSubmitted: (_) => _sendEmail(),
          ),
          const SizedBox(height: Sp.lg),
          KButton(label: 'Email me a code', icon: Icons.mail_outline_rounded, expand: true, busy: busy, onPressed: _sendEmail),
          const SizedBox(height: 4),
          _ghosts([
            KButton(label: 'Use WhatsApp', kind: KButtonKind.ghost, small: true, onPressed: () => _go(_Step.phone)),
            KButton(label: 'Use a password', kind: KButtonKind.ghost, small: true, onPressed: () => _go(_Step.password)),
          ]),
        ];
      case _Step.password:
        return [
          KField(label: 'Email', controller: _mail, keyboard: TextInputType.emailAddress, autofill: const [AutofillHints.email], caps: TextCapitalization.none),
          const SizedBox(height: Sp.md),
          KField(label: 'Password', controller: _pass, obscure: true, autofill: const [AutofillHints.password], caps: TextCapitalization.none, onSubmitted: (_) => _password()),
          const SizedBox(height: Sp.lg),
          KButton(label: 'Sign in', icon: Icons.check_rounded, expand: true, busy: busy, onPressed: _password),
          const SizedBox(height: 4),
          _ghosts([KButton(label: 'Email me a code instead', kind: KButtonKind.ghost, small: true, onPressed: () => _go(_Step.email))]),
        ];
    }
  }
}

