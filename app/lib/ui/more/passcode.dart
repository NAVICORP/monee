import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api.dart';
import '../theme.dart';
import '../widgets.dart';
import 'more_common.dart';

/// The passcode: four digits kept on this device only (another phone or
/// the web app has its own). It guards the device, not the account, so a
/// salted hash in shared preferences is enough.
class Passcode {
  Passcode._();

  static const _pinKey = 'monee.pin';
  static const _afterKey = 'monee.pin.after';

  static String? _hash;
  static bool _loaded = false;
  static DateTime? _holdUntil;

  /// Seconds away before it asks again: 0 right away, 60, 300.
  static int after = 0;

  static bool get isOn => _hash != null;

  static Future<void> load() async {
    if (_loaded) return;
    try {
      final p = await SharedPreferences.getInstance();
      _hash = p.getString(_pinKey);
      after = p.getInt(_afterKey) ?? 0;
    } catch (_) {
      // No storage: no passcode.
    }
    _loaded = true;
  }

  /// A small salted hash that gives the same answer on phones and on the web
  /// (every step stays well under 2^53).
  static String _digest(String pin) {
    const p1 = 67108859, p2 = 67108837;
    var a = 7, b = 11;
    final s = 'monee:$pin:device';
    for (var round = 0; round < 400; round++) {
      for (final c in s.codeUnits) {
        a = (a * 131 + c + round) % p1;
        b = (b * 257 + c * 7 + a) % p2;
      }
    }
    return '${a.toRadixString(16)}.${b.toRadixString(16)}';
  }

  static bool check(String pin) => _hash != null && _digest(pin) == _hash;

  static Future<void> save(String pin) async {
    _hash = _digest(pin);
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_pinKey, _hash!);
    } catch (_) {
      // Kept for this visit.
    }
  }

  static Future<void> clear() async {
    _hash = null;
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(_pinKey);
    } catch (_) {
      // Gone for this visit.
    }
  }

  static Future<void> setAfter(int seconds) async {
    after = seconds;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt(_afterKey, seconds);
    } catch (_) {
      // Kept for this visit.
    }
  }

  /// Pursee itself is about to leave the screen for a moment (the file
  /// picker, the share sheet): coming back from that does not ask.
  static void holdBriefly() => _holdUntil = DateTime.now().add(const Duration(seconds: 20));

  static bool _held(DateTime away) {
    final h = _holdUntil;
    return h != null && away.isBefore(h);
  }

  static String afterLabel(int s) => switch (s) {
        0 => 'Right away',
        60 => 'After 1 minute',
        _ => 'After ${s ~/ 60} minutes',
      };
}

/// Shows the app, and covers it with the lock screen when it opens and when
/// it comes back after the chosen time. Does nothing when no passcode is set
/// on this device (the web included).
class PasscodeGate extends StatefulWidget {
  const PasscodeGate({super.key, required this.child});
  final Widget child;

  @override
  State<PasscodeGate> createState() => _PasscodeGateState();
}

class _PasscodeGateState extends State<PasscodeGate> with WidgetsBindingObserver {
  /// The saved passcode has been read.
  bool _ready = false;

  /// The lock screen covers the app (when it opens).
  bool _locked = false;

  /// The lock screen is open over everything (after coming back), above any
  /// sheet or full-screen editor.
  bool _over = false;

  DateTime? _away;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  Future<void> _start() async {
    await Passcode.load();
    if (!mounted) return;
    setState(() {
      _ready = true;
      _locked = Passcode.isOn;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      final now = DateTime.now();
      _away ??= now;
      // Right away: lock as it leaves, so nothing shows when it comes back.
      if (Passcode.isOn && Passcode.after == 0 && !Passcode._held(now)) _lock();
    } else if (state == AppLifecycleState.resumed) {
      final away = _away;
      _away = null;
      if (away == null || !Passcode.isOn || Passcode._held(away)) return;
      if (DateTime.now().difference(away).inSeconds >= Passcode.after) _lock();
    }
  }

  void _lock() {
    if (!_ready || _locked || _over || !mounted) return;
    final nav = Navigator.maybeOf(context, rootNavigator: true);
    if (nav == null) {
      setState(() => _locked = true);
      return;
    }
    _over = true;
    nav
        .push(PageRouteBuilder<void>(
          opaque: true,
          transitionDuration: Duration.zero,
          reverseTransitionDuration: const Duration(milliseconds: 180),
          pageBuilder: (ctx, a, b) => _LockScreen(onUnlock: () => Navigator.of(ctx).pop()),
          transitionsBuilder: (ctx, a, b, child) => FadeTransition(opacity: a, child: child),
        ))
        .whenComplete(() {
      _over = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final covered = !_ready || _locked;
    return Stack(fit: StackFit.expand, children: [
      ExcludeSemantics(excluding: covered, child: widget.child),
      if (!_ready) Positioned.fill(child: ColoredBox(color: K.paper)),
      if (_ready && _locked) Positioned.fill(child: _LockScreen(onUnlock: () => setState(() => _locked = false))),
    ]);
  }
}

/// The lock screen: the logo, four dots, a keypad, and a way out.
class _LockScreen extends StatefulWidget {
  const _LockScreen({required this.onUnlock});
  final VoidCallback onUnlock;

  @override
  State<_LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<_LockScreen> {
  String typed = '';
  String? error;
  int wrong = 0;
  DateTime? waitUntil;
  Timer? _tick;

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  bool get _waiting => waitUntil != null && DateTime.now().isBefore(waitUntil!);

  void _digit(String d) {
    if (_waiting || typed.length >= 4) return;
    setState(() {
      typed += d;
      error = null;
    });
    if (typed.length == 4) _check();
  }

  void _back() {
    if (typed.isEmpty) return;
    setState(() => typed = typed.substring(0, typed.length - 1));
  }

  void _check() {
    if (Passcode.check(typed)) {
      HapticFeedback.lightImpact();
      widget.onUnlock();
      return;
    }
    HapticFeedback.heavyImpact();
    wrong++;
    setState(() {
      typed = '';
      error = 'That is not the passcode. Try again.';
      if (wrong >= 5) {
        wrong = 0;
        waitUntil = DateTime.now().add(const Duration(seconds: 30));
        error = 'Too many tries. Wait 30 seconds.';
        _tick?.cancel();
        _tick = Timer(const Duration(seconds: 30), () {
          if (mounted) {
            setState(() {
              waitUntil = null;
              error = null;
            });
          }
        });
      }
    });
  }

  Future<void> _forgot() async {
    final ok = await confirm(context,
        title: 'Sign out?',
        text: 'The passcode is removed from this device. Sign in again to open Pursee; your books stay safe on the server.',
        yes: 'Sign out');
    if (!ok) return;
    await Passcode.clear();
    await Api.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: K.paper,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(Sp.xl),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 340),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const MoneeIcon(size: 56, shadow: true),
                  const SizedBox(height: Sp.lg),
                  Text('Enter your passcode', style: T.h2, textAlign: TextAlign.center),
                  const SizedBox(height: 4),
                  Text(error ?? 'Pursee is locked on this device.',
                      textAlign: TextAlign.center, style: T.small.copyWith(color: error == null ? K.muted : K.bad)),
                  const SizedBox(height: Sp.xl),
                  PinDots(count: typed.length, bad: error != null),
                  const SizedBox(height: Sp.xl),
                  PinPad(onDigit: _digit, onBack: _back, enabled: !_waiting),
                  const SizedBox(height: Sp.md),
                  KButton(label: 'Forgot? Sign out', kind: KButtonKind.ghost, small: true, onPressed: _forgot),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Four dots, filled as digits are typed.
class PinDots extends StatelessWidget {
  const PinDots({super.key, required this.count, this.bad = false});
  final int count;
  final bool bad;

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (var i = 0; i < 4; i++)
        AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          margin: const EdgeInsets.symmetric(horizontal: 9),
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: i < count ? K.blue : Colors.transparent,
            border: Border.all(color: bad ? K.bad : (i < count ? K.blue : K.border2), width: 1.6),
          ),
        ),
    ]);
  }
}

/// A round number keypad: 1 to 9, then 0 and a back key.
class PinPad extends StatelessWidget {
  const PinPad({super.key, required this.onDigit, required this.onBack, this.enabled = true});
  final ValueChanged<String> onDigit;
  final VoidCallback onBack;
  final bool enabled;

  Widget _key(Widget child, VoidCallback? onTap, {String? label}) {
    final VoidCallback? tap = onTap;
    return Padding(
      padding: const EdgeInsets.all(7),
      child: Semantics(
        button: true,
        label: label,
        child: Material(
          color: tap == null ? Colors.transparent : K.surface,
          shape: CircleBorder(side: tap == null ? BorderSide.none : BorderSide(color: K.border)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: tap == null || !enabled
                ? null
                : () {
                    HapticFeedback.selectionClick();
                    tap();
                  },
            child: SizedBox(width: 64, height: 64, child: Center(child: child)),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget digit(String d) => _key(Text(d, style: T.h2.copyWith(color: enabled ? K.ink : K.border2)), () => onDigit(d), label: d);
    return Opacity(
      opacity: enabled ? 1 : 0.6,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Row(mainAxisSize: MainAxisSize.min, children: [for (final d in row) digit(d)]),
        Row(mainAxisSize: MainAxisSize.min, children: [
          _key(const SizedBox.shrink(), null),
          digit('0'),
          _key(Icon(Icons.backspace_outlined, size: 20, color: K.ink2), onBack, label: 'Delete'),
        ]),
      ]),
    );
  }
}

/// Four digits in a sheet. With [verify], a wrong passcode is said so and
/// cleared. Returns the digits, or null when closed.
Future<String?> askPin(BuildContext context, {required String title, String? text, bool Function(String)? verify}) {
  return showKSheet<String>(context, title: title, builder: (ctx) => _PinAsk(text: text, verify: verify));
}

class _PinAsk extends StatefulWidget {
  const _PinAsk({this.text, this.verify});
  final String? text;
  final bool Function(String)? verify;

  @override
  State<_PinAsk> createState() => _PinAskState();
}

class _PinAskState extends State<_PinAsk> {
  String typed = '';
  String? error;

  void _digit(String d) {
    if (typed.length >= 4) return;
    setState(() {
      typed += d;
      error = null;
    });
    if (typed.length < 4) return;
    final v = widget.verify;
    if (v != null && !v(typed)) {
      HapticFeedback.heavyImpact();
      setState(() {
        typed = '';
        error = 'That is not the passcode. Try again.';
      });
      return;
    }
    Navigator.of(context).pop(typed);
  }

  void _back() {
    if (typed.isEmpty) return;
    setState(() => typed = typed.substring(0, typed.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Text(error ?? widget.text ?? 'Four digits.', textAlign: TextAlign.center, style: T.small.copyWith(color: error == null ? K.muted : K.bad)),
      const SizedBox(height: Sp.lg),
      PinDots(count: typed.length, bad: error != null),
      const SizedBox(height: Sp.lg),
      PinPad(onDigit: _digit, onBack: _back),
    ]);
  }
}

/// More > Passcode: turn it on or off, change it, and how soon it asks again.
class PasscodeSettingsPage extends StatefulWidget {
  const PasscodeSettingsPage({super.key});

  @override
  State<PasscodeSettingsPage> createState() => _PasscodeSettingsPageState();
}

class _PasscodeSettingsPageState extends State<PasscodeSettingsPage> {
  bool loaded = false;

  @override
  void initState() {
    super.initState();
    Passcode.load().then((_) {
      if (mounted) setState(() => loaded = true);
    });
  }

  /// A new passcode, typed twice. True when it was saved.
  Future<bool> _chooseNew() async {
    final first = await askPin(context, title: 'Choose a passcode', text: 'Four digits you will remember.');
    if (first == null || !mounted) return false;
    final again = await askPin(context, title: 'Once more', text: 'Type the same four digits again.');
    if (again == null || !mounted) return false;
    if (again != first) {
      toast(context, 'The two did not match. Try again.', bad: true);
      return false;
    }
    await Passcode.save(first);
    return true;
  }

  Future<void> _turn(bool on) async {
    if (on) {
      if (await _chooseNew() && mounted) {
        setState(() {});
        toast(context, 'Passcode on');
      }
      return;
    }
    final pin = await askPin(context, title: 'Turn the passcode off', text: 'Type the passcode.', verify: Passcode.check);
    if (pin == null || !mounted) return;
    await Passcode.clear();
    if (!mounted) return;
    setState(() {});
    toast(context, 'Passcode off');
  }

  Future<void> _change() async {
    final pin = await askPin(context, title: 'Change the passcode', text: 'First, the passcode you have now.', verify: Passcode.check);
    if (pin == null || !mounted) return;
    if (await _chooseNew() && mounted) {
      setState(() {});
      toast(context, 'Passcode changed');
    }
  }

  Future<void> _after() async {
    final p = await showPicker<int>(context, title: 'Ask again', selected: Passcode.after, options: [
      for (final s in const [0, 60, 300])
        PickOption(s, Passcode.afterLabel(s), sub: s == 0 ? 'Every time Pursee comes back on screen' : 'When Pursee was away that long'),
    ]);
    if (p == null) return;
    await Passcode.setAfter(p.value);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final on = Passcode.isOn;
    return Scaffold(
      appBar: AppBar(title: const Text('Passcode')),
      body: !loaded
          ? const Loading()
          : PageBody(children: [
              const Notice('The passcode guards Pursee on this device. Your other phones and the web app keep their own.', bad: false),
              const SizedBox(height: Sp.md),
              LinkGroup([
                SwitchTile(title: 'Passcode', sub: on ? 'Asked when Pursee opens' : 'Off', value: on, onChanged: _turn),
                if (on) LinkRow(Icons.pin_outlined, 'Change the passcode', _change),
                if (on) LinkRow(Icons.timer_outlined, 'Ask again', _after, value: Passcode.afterLabel(Passcode.after)),
              ]),
              const SizedBox(height: Sp.md),
              Text('Forgot it? The lock screen can sign you out; sign in again and your books are all there.', style: T.small),
            ]),
    );
  }
}
