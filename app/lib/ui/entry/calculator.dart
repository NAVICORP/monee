import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format.dart';
import '../theme.dart';
import '../widgets.dart';

/// The calculator keypad in a rounded sheet: digits, a point,
/// + - x ÷, %, backspace, C, = and Use. Returns the result when Use is
/// tapped (rounded to the currency's decimals when a currency is given), or
/// null when the sheet is closed.
Future<num?> showCalculator(BuildContext context, {num? start, String? currency, String title = 'Calculator'}) {
  return showKSheet<num>(
    context,
    title: title,
    builder: (ctx) => _CalcBox(start: start, currency: currency, onUse: (v) => Navigator.of(ctx).pop(v)),
  );
}

const _ops = ['+', '-', '×', '÷'];

class _CalcBox extends StatefulWidget {
  const _CalcBox({this.start, this.currency, required this.onUse});
  final num? start;
  final String? currency;
  final ValueChanged<num> onUse;

  @override
  State<_CalcBox> createState() => _CalcBoxState();
}

class _CalcBoxState extends State<_CalcBox> {
  final focus = FocusNode(debugLabel: 'calculator');

  /// What has been typed: numbers and operators, like 1250+30×2.
  String expr = '';

  /// The value on show came from outside or from =: a digit starts afresh.
  bool fresh = false;

  /// The last Use or = could not be worked out (a division by 0).
  bool bad = false;

  Currency? get cur => widget.currency == null ? null : currencyOf(widget.currency);

  /// How many decimals a number may have.
  int get maxDecimals => cur?.decimals ?? 6;

  @override
  void initState() {
    super.initState();
    final s = widget.start;
    if (s != null && s != 0) {
      expr = _plain(s.toDouble());
      fresh = true;
    }
  }

  @override
  void dispose() {
    focus.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- the arithmetic

  /// A number as plain digits: no grouping, no exponent, no trailing zeros.
  String _plain(double v) {
    var s = v.abs().toStringAsFixed(math.min(8, math.max(maxDecimals, 2)));
    if (s.contains('.')) {
      s = s.replaceFirst(RegExp(r'0+$'), '');
      if (s.endsWith('.')) s = s.substring(0, s.length - 1);
    }
    if (s == '0') return '0';
    return v < 0 ? '-$s' : s;
  }

  static double? _parse(String t) {
    var s = t;
    if (s.isEmpty) return null;
    if (s.endsWith('.')) s = s.substring(0, s.length - 1);
    if (s.startsWith('.')) s = '0$s';
    return double.tryParse(s);
  }

  /// The expression as numbers and operators: [12.0, '+', 3.5, '×', 2.0].
  /// A trailing operator is left out. Null when a number cannot be read.
  static List<Object>? _tokens(String s) {
    final out = <Object>[];
    var i = 0;
    var neg = false;
    if (s.startsWith('-')) {
      neg = true;
      i = 1;
    }
    var buf = StringBuffer();
    for (; i < s.length; i++) {
      final ch = s[i];
      if (_ops.contains(ch)) {
        final n = _parse(buf.toString());
        if (n == null) return null;
        out
          ..add(neg ? -n : n)
          ..add(ch);
        buf = StringBuffer();
        neg = false;
      } else {
        buf.write(ch);
      }
    }
    if (buf.isNotEmpty) {
      final n = _parse(buf.toString());
      if (n == null) return null;
      out.add(neg ? -n : n);
    } else if (out.isNotEmpty) {
      out.removeLast();
    }
    return out;
  }

  /// x and ÷ first, then + and -. Null for a division by 0.
  static double? _eval(List<Object> t) {
    if (t.isEmpty) return 0.0;
    final terms = <double>[];
    final signs = <String>[];
    var acc = t[0] as double;
    for (var i = 1; i + 1 < t.length; i += 2) {
      final op = t[i] as String;
      final v = t[i + 1] as double;
      if (op == '×') {
        acc *= v;
      } else if (op == '÷') {
        if (v == 0) return null;
        acc /= v;
      } else {
        terms.add(acc);
        signs.add(op);
        acc = v;
      }
    }
    terms.add(acc);
    var r = terms[0];
    for (var i = 0; i < signs.length; i++) {
      r = signs[i] == '+' ? r + terms[i + 1] : r - terms[i + 1];
    }
    return r.isFinite ? r : null;
  }

  double? _valueOf(String s) {
    final t = _tokens(s);
    return t == null ? null : _eval(t);
  }

  double? get _value => _valueOf(expr);

  /// The result, rounded the way it will be used.
  num _rounded(double v) {
    final d = cur?.decimals ?? 6;
    final f = math.pow(10, d);
    final r = (v * f).round() / f;
    return r == r.truncateToDouble() ? r.toInt() : r;
  }

  /// The number being typed (after the last operator).
  String get _current {
    for (var i = expr.length - 1; i >= 0; i--) {
      if (_ops.contains(expr[i]) && !(i == 0 && expr[i] == '-')) return expr.substring(i + 1);
    }
    return expr.startsWith('-') ? expr.substring(1) : expr;
  }

  bool get _endsWithOp => expr.length > 1 && _ops.contains(expr[expr.length - 1]);

  bool get _hasOp {
    for (var i = 1; i < expr.length; i++) {
      if (_ops.contains(expr[i])) return true;
    }
    return false;
  }

  // ---------------------------------------------------------------- keys

  void _digit(String d) {
    if (fresh) {
      expr = '';
      fresh = false;
    }
    final c = _current;
    if (c == '0') {
      expr = expr.substring(0, expr.length - 1) + d;
      return;
    }
    if (c.replaceAll('.', '').length >= 12) return;
    final dot = c.indexOf('.');
    if (dot >= 0 && c.length - dot - 1 >= maxDecimals) return;
    expr += d;
  }

  void _dot() {
    if (maxDecimals == 0) return;
    if (fresh) {
      expr = '';
      fresh = false;
    }
    final c = _current;
    if (c.contains('.')) return;
    expr += c.isEmpty ? '0.' : '.';
  }

  void _op(String o) {
    fresh = false;
    if (expr.isEmpty || expr == '-') return;
    if (_endsWithOp) {
      expr = expr.substring(0, expr.length - 1) + o;
      return;
    }
    if (expr.endsWith('.')) expr = expr.substring(0, expr.length - 1);
    if (expr.length >= 80) return;
    expr += o;
  }

  /// 50+10% is 55 (10% of 50); 200×10% is 20; 10% alone is 0.1.
  void _percent() {
    fresh = false;
    final c = _current;
    final v = _parse(c);
    if (c.isEmpty || v == null) return;
    var head = expr.substring(0, expr.length - c.length);
    double nv;
    if (head.length > 1 && (head.endsWith('+') || head.endsWith('-'))) {
      final base = _valueOf(head.substring(0, head.length - 1));
      if (base == null) return;
      nv = base * v / 100;
      if (nv < 0) {
        head = head.substring(0, head.length - 1) + (head.endsWith('+') ? '-' : '+');
        nv = -nv;
      }
    } else {
      nv = v / 100;
    }
    expr = head + _plain(nv);
  }

  void _back() {
    fresh = false;
    if (expr.isNotEmpty) expr = expr.substring(0, expr.length - 1);
    if (expr == '-') expr = '';
  }

  void _clear() {
    fresh = false;
    expr = '';
  }

  void _equals() {
    final v = _value;
    if (v == null) {
      bad = true;
      return;
    }
    expr = _plain(_rounded(v).toDouble());
    fresh = true;
  }

  void _press(VoidCallback f) {
    HapticFeedback.selectionClick();
    setState(() {
      bad = false;
      f();
    });
  }

  void _use() {
    final v = _value;
    if (v == null) {
      HapticFeedback.heavyImpact();
      setState(() => bad = true);
      return;
    }
    HapticFeedback.selectionClick();
    widget.onUse(_rounded(v));
  }

  /// Typing on a keyboard (the web app, tablets with keyboards).
  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.backspace) {
      _press(_back);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter) {
      _use();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.delete) {
      _press(_clear);
      return KeyEventResult.handled;
    }
    final ch = e.character;
    if (ch == null || ch.length != 1) return KeyEventResult.ignored;
    if ('0123456789'.contains(ch)) {
      _press(() => _digit(ch));
    } else if (ch == '.' || ch == ',') {
      _press(_dot);
    } else if (ch == '+' || ch == '-') {
      _press(() => _op(ch));
    } else if (ch == '*' || ch == 'x' || ch == 'X') {
      _press(() => _op('×'));
    } else if (ch == '/') {
      _press(() => _op('÷'));
    } else if (ch == '%') {
      _press(_percent);
    } else if (ch == '=') {
      _press(_equals);
    } else if (ch == 'c' || ch == 'C') {
      _press(_clear);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  // ---------------------------------------------------------------- showing it

  String _group(String digits) {
    final n = int.tryParse(digits);
    if (n == null) return digits;
    return (cur?.indian ?? false) ? groupDigits(n) : groupThousands(n);
  }

  /// The expression with grouped numbers and spaced operators: 1,250 + 30 × 2.
  String _pretty(String s) {
    final out = StringBuffer();
    var buf = StringBuffer();
    void flush() {
      final t = buf.toString();
      if (t.isEmpty) return;
      final dot = t.indexOf('.');
      out.write(dot < 0 ? _group(t) : '${dot == 0 ? '0' : _group(t.substring(0, dot))}${t.substring(dot)}');
      buf = StringBuffer();
    }

    for (var i = 0; i < s.length; i++) {
      final ch = s[i];
      if (_ops.contains(ch) && !(i == 0 && ch == '-')) {
        flush();
        out.write(' $ch ');
      } else {
        buf.write(ch);
      }
    }
    flush();
    return out.toString().trimRight();
  }

  String _resultText(double v) {
    final r = _rounded(v);
    final c = cur;
    if (c != null) return c.format(r);
    final s = _plain(r.toDouble());
    final neg = s.startsWith('-');
    final body = neg ? s.substring(1) : s;
    final dot = body.indexOf('.');
    final grouped = dot < 0 ? _group(body) : '${_group(body.substring(0, dot))}${body.substring(dot)}';
    return neg ? '-$grouped' : grouped;
  }

  Widget _display() {
    final empty = expr.isEmpty;
    final v = _value;
    String? under;
    var underBad = false;
    if (bad || (v == null && !empty)) {
      under = 'Cannot divide by 0';
      underBad = true;
    } else if (_hasOp && v != null) {
      under = '= ${_resultText(v)}';
    }
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(14, 10, 14, 12),
      decoration: BoxDecoration(color: K.surface, borderRadius: BorderRadius.circular(K.r), border: Border.all(color: K.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          if (cur != null) Pill.grey(cur!.code),
          const Spacer(),
          if (under != null)
            Flexible(
              flex: 4,
              child: Text(under,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: T.small.copyWith(color: underBad ? K.bad : K.muted, fontWeight: FontWeight.w600).merge(T.tabular)),
            ),
        ]),
        const SizedBox(height: 8),
        SizedBox(
          height: 40,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerEnd,
            child: Text(
              empty ? '0' : _pretty(expr),
              maxLines: 1,
              textDirection: TextDirection.ltr,
              style: T.display.copyWith(fontSize: 32, color: empty ? K.border2 : K.ink).merge(T.tabular),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _key(String label, VoidCallback onTap, {Color bg = K.surface, Color fg = K.ink, IconData? icon, bool line = true, String? hint}) {
    final child = icon != null
        ? Icon(icon, size: 20, color: fg)
        : Text(label, style: T.h2.copyWith(fontSize: 19, color: fg));
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Semantics(
          button: true,
          label: hint ?? label,
          child: Material(
            color: bg,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(K.rMd),
              side: line ? BorderSide(color: K.border) : BorderSide.none,
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: SizedBox(height: 50, child: Center(child: ExcludeSemantics(child: child))),
            ),
          ),
        ),
      ),
    );
  }

  Widget _digitKey(String d) => _key(d, () => _press(() => _digit(d)));
  Widget _opKey(String o) => _key(o, () => _press(() => _op(o)), bg: K.brand100, fg: K.brand600, line: false);

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _display(),
          const SizedBox(height: Sp.md),
          Row(children: [
            _key('C', () => _press(_clear), bg: K.surface2, fg: K.ink2, line: false, hint: 'Clear'),
            _key('', () => _press(_back), bg: K.surface2, fg: K.ink2, line: false, icon: Icons.backspace_outlined, hint: 'Delete'),
            _key('%', () => _press(_percent), bg: K.surface2, fg: K.ink2, line: false, hint: 'Percent'),
            _opKey('÷'),
          ]),
          Row(children: [_digitKey('7'), _digitKey('8'), _digitKey('9'), _opKey('×')]),
          Row(children: [_digitKey('4'), _digitKey('5'), _digitKey('6'), _opKey('-')]),
          Row(children: [_digitKey('1'), _digitKey('2'), _digitKey('3'), _opKey('+')]),
          Row(children: [
            _key('.', () => _press(_dot), hint: 'Point'),
            _digitKey('0'),
            _key('=', () => _press(_equals), bg: K.deep, fg: Colors.white, line: false, hint: 'Equals'),
            _key('Use', _use, bg: K.blue, fg: Colors.white, line: false, hint: 'Use this amount'),
          ]),
        ]),
      ),
    );
  }
}
