// Draws the main signed-in screens to pictures, so the design can be checked
// without a phone, runtime errors (a bad cast, a box that spills) show up as
// failed tests, and the stores get screenshots. The answers come from the
// real database rules: CI loads the demo book (tools/demo.sql) into Postgres
// and records what the server says (tools/record_screens.py) into
// test_screens/fixtures.json first.
//
//   flutter test test_screens --update-goldens
//
// The pictures land in test_screens/shots/. Each picture is its own test, so
// one that fails does not hide the others. The app runs as it does on a
// phone: signed in, the demo book chosen, no passcode, every screen reached
// by tapping what a person would tap.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:monee/core/api.dart';
import 'package:monee/core/book.dart' show Me;
import 'package:monee/core/format.dart' show isoDay;
import 'package:monee/main.dart' show MoneeApp;
import 'package:monee/ui/money.dart' show PillTabs;
import 'package:monee/ui/widgets.dart' show KNavBar;
import 'package:shared_preferences/shared_preferences.dart';

Future<void> loadFonts() async {
  Future<void> family(String name, List<String> files) async {
    final l = FontLoader(name);
    for (final f in files) {
      l.addFont(rootBundle.load(f));
    }
    await l.load();
  }

  await family('Manrope', [for (final w in [500, 600, 700, 800]) 'assets/fonts/Manrope-$w.ttf']);
  await family('Bricolage', [for (final w in [600, 700]) 'assets/fonts/BricolageGrotesque-$w.ttf']);
  // Category emojis, from the system's emoji font when CI has installed it.
  final emoji = File('/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf');
  if (emoji.existsSync()) {
    final bytes = emoji.readAsBytesSync();
    final l = FontLoader('Noto Color Emoji')..addFont(Future.value(bytes.buffer.asByteData(bytes.offsetInBytes, bytes.lengthInBytes)));
    await l.load();
  }
  // Material icons, from the Flutter SDK running the test.
  final roots = <String>[
    if (Platform.environment['FLUTTER_ROOT'] != null) Platform.environment['FLUTTER_ROOT']!,
    File(Platform.resolvedExecutable).parent.path,
  ];
  for (final r in roots) {
    var dir = Directory(r);
    for (var i = 0; i < 8; i++) {
      final f = File('${dir.path}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
      final g = File('${dir.path}/artifacts/material_fonts/MaterialIcons-Regular.otf');
      for (final x in [f, g]) {
        if (x.existsSync()) {
          final bytes = x.readAsBytesSync();
          final l = FontLoader('MaterialIcons')..addFont(Future.value(bytes.buffer.asByteData(bytes.offsetInBytes, bytes.lengthInBytes)));
          await l.load();
          return;
        }
      }
      dir = dir.parent;
    }
  }
}

/// Arguments as one string: keys sorted, no spaces. tools/record_screens.py
/// keys every answer the same way.
String canonical(Object? v) {
  if (v is Map) {
    final keys = [for (final k in v.keys) '$k']..sort();
    return '{${[for (final k in keys) '${jsonEncode(k)}:${canonical(v[k])}'].join(',')}}';
  }
  if (v is List) return '[${[for (final x in v) canonical(x)].join(',')}]';
  return jsonEncode(v);
}

/// A stand-in for monee.skifi.co that answers from the recorded demo book.
/// Functions answer what the real function answered for the same
/// arguments; table reads honour the filters, order and range the app sends,
/// the way the database API does. Writes answer as if saved.
class FakeServer {
  FakeServer(this.fx);
  final Map<String, dynamic> fx;

  /// Calls with no recorded answer at all.
  final Set<String> unknown = <String>{};

  /// Calls whose arguments were not recorded, answered with the function's
  /// first recorded answer instead.
  final Set<String> fallback = <String>{};

  /// Functions that only change things: an empty answer will do.
  static const _writes = {
    'save_txn',
    'pay_card',
    'delete_book',
    'create_book',
    'import_rows',
    'add_repeat',
    'add_instalments',
    'set_main_currency',
    'delete_my_data',
  };

  http.Client get client => MockClient(_handle);

  Map<String, dynamic> get _answers => fx['rpc'] as Map<String, dynamic>;
  Map<String, dynamic> get _tables => fx['tables'] as Map<String, dynamic>;

  Future<http.Response> _handle(http.Request r) async {
    final path = r.url.path;
    Object? body;
    if (path.startsWith('/rest/v1/rpc/')) {
      final fn = path.substring('/rest/v1/rpc/'.length);
      final sent = r.body.isEmpty ? null : jsonDecode(r.body);
      body = _answer(fn, sent is Map ? Map<String, dynamic>.from(sent) : <String, dynamic>{});
    } else if (path.startsWith('/rest/v1/')) {
      final table = path.substring('/rest/v1/'.length);
      if (r.method == 'GET') {
        body = _rows(table, r.url.queryParameters, r.headers['Range']);
      } else {
        final sent = r.body.isEmpty ? null : jsonDecode(r.body);
        body = [if (sent is Map) sent else <String, dynamic>{}];
      }
    } else {
      // Sign-in, storage: nothing the pictures need.
      body = <String, dynamic>{};
    }
    return http.Response.bytes(utf8.encode(jsonEncode(body)), 200, headers: {'content-type': 'application/json; charset=utf-8'});
  }

  Object? _answer(String fn, Map<String, dynamic> args) {
    if (_writes.contains(fn)) return <String, dynamic>{};
    final key = '$fn ${canonical(args)}';
    if (_answers.containsKey(key)) return _answers[key];
    if (_answers.containsKey(fn)) {
      fallback.add(key);
      return _answers[fn];
    }
    unknown.add(key);
    return null;
  }

  List<Map<String, dynamic>> _rows(String table, Map<String, String> q, String? range) {
    final all = _tables[table];
    if (all is! List) {
      unknown.add('GET /rest/v1/$table');
      return <Map<String, dynamic>>[];
    }
    var rows = [for (final x in all) Map<String, dynamic>.from(x as Map)];
    for (final e in q.entries) {
      if (e.key == 'select' || e.key == 'order' || e.key == 'limit' || e.key == 'offset') continue;
      rows = rows.where((x) => _passes(x, e.key, e.value)).toList();
    }
    final order = q['order'];
    if (order != null && order.isNotEmpty) {
      final keys = [for (final o in order.split(',')) o.trim().split('.')];
      rows.sort((a, b) {
        for (final k in keys) {
          final desc = k.contains('desc');
          final nullsFirst = k.contains('nullsfirst') || (desc && !k.contains('nullslast'));
          final c = _compare(a[k[0]], b[k[0]], desc: desc, nullsFirst: nullsFirst);
          if (c != 0) return c;
        }
        return 0;
      });
    }
    final offset = int.tryParse(q['offset'] ?? '');
    if (offset != null) rows = rows.skip(offset).toList();
    final limit = int.tryParse(q['limit'] ?? '');
    if (limit != null) rows = rows.take(limit).toList();
    if (range != null) {
      final p = range.split('-');
      final from = int.tryParse(p.first.trim()) ?? 0;
      final to = p.length > 1 ? int.tryParse(p[1].trim()) : null;
      rows = rows.skip(from).toList();
      if (to != null) rows = rows.take(to - from + 1).toList();
    }
    final columns = q['select'];
    if (columns != null && columns.trim() != '*' && !columns.contains('(') && !columns.contains(':')) {
      final keep = [for (final c in columns.split(',')) c.trim()];
      rows = [
        for (final x in rows) {for (final c in keep) if (x.containsKey(c)) c: x[c]},
      ];
    }
    return rows;
  }

  static int _compare(Object? a, Object? b, {required bool desc, required bool nullsFirst}) {
    if (a == null && b == null) return 0;
    if (a == null) return nullsFirst ? -1 : 1;
    if (b == null) return nullsFirst ? 1 : -1;
    final int c;
    if (a is num && b is num) {
      c = a.compareTo(b);
    } else if (a is bool && b is bool) {
      c = a == b ? 0 : (a ? 1 : -1);
    } else {
      c = '$a'.compareTo('$b');
    }
    return desc ? -c : c;
  }

  /// One filter on one row: column=op.value (op may start with not.), and
  /// the groups and=(a.op.x,b.op.y) and or=(...).
  static bool _passes(Map<String, dynamic> row, String key, String value) {
    if (key == 'and' || key == 'or' || key == 'not.and' || key == 'not.or') {
      final inner = value.startsWith('(') && value.endsWith(')') ? value.substring(1, value.length - 1) : value;
      final results = [
        for (final part in _split(inner))
          if (part.startsWith('and(') || part.startsWith('or('))
            _passes(row, part.substring(0, part.indexOf('(')), part.substring(part.indexOf('(')))
          else if (part.contains('.'))
            _passes(row, part.substring(0, part.indexOf('.')), part.substring(part.indexOf('.') + 1)),
      ];
      final all = key.endsWith('and') ? results.every((x) => x) : results.any((x) => x);
      return key.startsWith('not.') ? !all : all;
    }
    return _match(row[key], value);
  }

  /// Splits on the commas that are not inside brackets.
  static List<String> _split(String s) {
    final out = <String>[];
    var depth = 0;
    var start = 0;
    for (var i = 0; i < s.length; i++) {
      final ch = s[i];
      if (ch == '(') depth++;
      if (ch == ')') depth--;
      if (ch == ',' && depth == 0) {
        out.add(s.substring(start, i));
        start = i + 1;
      }
    }
    out.add(s.substring(start));
    return [for (final p in out) if (p.trim().isNotEmpty) p.trim()];
  }

  static bool _match(Object? v, String f) {
    if (f.startsWith('not.')) return !_match(v, f.substring(4));
    final dot = f.indexOf('.');
    if (dot < 0) return true;
    final op = f.substring(0, dot);
    final x = f.substring(dot + 1);
    switch (op) {
      case 'eq':
        return v != null && '$v' == x;
      case 'neq':
        return v != null && '$v' != x;
      case 'is':
        if (x == 'null') return v == null;
        if (x == 'true') return v == true;
        if (x == 'false') return v == false;
        return '$v' == x;
      case 'in':
        final list = [for (final e in x.replaceAll('(', '').replaceAll(')', '').split(',')) e.trim().replaceAll('"', '')];
        return v != null && list.contains('$v');
      case 'gt':
      case 'gte':
      case 'lt':
      case 'lte':
        if (v == null) return false;
        final n = num.tryParse(x);
        final c = v is num && n != null ? v.compareTo(n) : '$v'.compareTo(x);
        return switch (op) { 'gt' => c > 0, 'gte' => c >= 0, 'lt' => c < 0, _ => c <= 0 };
      default:
        return true;
    }
  }
}

final File _fixtures = File('test_screens/fixtures.json');
final bool _have = _fixtures.existsSync();
late FakeServer server;

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
  await tester.runAsync(() async {
    for (final e in find.byType(Image).evaluate()) {
      await precacheImage((e.widget as Image).image, e);
    }
  });
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump(const Duration(milliseconds: 600));
}

Future<void> shot(WidgetTester tester, String name) async {
  await settle(tester);
  await expectLater(find.byType(MaterialApp).first, matchesGoldenFile('shots/$name.png'));
}

/// Scrolls the first match into view and taps it. Nothing to tap fails the
/// test, so a picture never quietly shows the wrong screen.
Future<void> tapOn(WidgetTester tester, Finder f) async {
  expect(f, findsWidgets, reason: 'Nothing to tap: $f');
  await tester.ensureVisible(f.first);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(f.first, warnIfMissed: false);
  await settle(tester);
}

/// A main tab, from the footer (phones) or the side bar (computers).
Future<void> openTab(WidgetTester tester, String label) async {
  final bar = find.byType(KNavBar);
  await tapOn(tester, bar.evaluate().isEmpty ? find.text(label) : find.descendant(of: bar, matching: find.text(label)));
}

/// A pill of the sub-tabs (Daily, Calendar, Monthly... or Stats, Budget, Note).
Future<void> pill(WidgetTester tester, String label) =>
    tapOn(tester, find.descendant(of: find.byType(PillTabs), matching: find.text(label)));

/// A key of the calculator sheet.
Future<void> press(WidgetTester tester, String label) =>
    tapOn(tester, find.descendant(of: find.byType(BottomSheet), matching: find.text(label)));

void phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

void computer(WidgetTester tester) {
  tester.view.physicalSize = const Size(2880, 1800);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
}

/// What the app keeps on the device between visits: signed in as the demo
/// person, the demo book chosen, no passcode.
Future<void> signedIn(WidgetTester tester) async {
  await tester.runAsync(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues(<String, Object>{
      'monee.session': jsonEncode(<String, dynamic>{
        'access_token': 'demo',
        'refresh_token': 'demo',
        'expires_at': 4102444800,
        'user': <String, dynamic>{'id': server.fx['user_id'], 'email': server.fx['email']},
      }),
      'monee.book': server.fx['book_id'] as String,
    });
    await Api.instance.load();
  });
}

/// The app opened the way a person opens it, on its first tab.
Future<void> openApp(WidgetTester tester) async {
  await signedIn(tester);
  await tester.pumpWidget(const MoneeApp());
  await settle(tester);
}

/// What tools/record_screens.py picked for the pictures to open: the entry,
/// the category and the card.
Map<String, dynamic> pick(String name) {
  final p = (server.fx['picks'] as Map)[name];
  if (p is! Map) fail('tools/record_screens.py found no $name for this picture to open.');
  return Map<String, dynamic>.from(p);
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadFonts();
    if (!_have) return;
    server = FakeServer(jsonDecode(_fixtures.readAsStringSync()) as Map<String, dynamic>);
    Api.instance.client = server.client;
    final now = isoDay(DateTime.now());
    if (server.fx['today'] != now) {
      // ignore: avoid_print
      print('The answers were recorded for ${server.fx['today']}, and this clock says $now: dates may not match.');
    }
  });
  setUp(() {
    // Every picture starts from a cold start of the app.
    Me.instance.signOut();
  });
  tearDownAll(() {
    if (!_have) return;
    if (server.fallback.isNotEmpty) {
      // ignore: avoid_print
      print('Answered with another day or screen\'s answer (these arguments were not recorded):\n  ${server.fallback.join('\n  ')}');
    }
    if (server.unknown.isNotEmpty) {
      // ignore: avoid_print
      print('No recorded answer at all:\n  ${server.unknown.join('\n  ')}');
    }
  });

  final skip = !_have;

  testWidgets('welcome', (tester) async {
    phone(tester);
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues(<String, Object>{});
    if (Api.instance.signedIn) await tester.runAsync(() => Api.instance.signOut());
    await tester.pumpWidget(const MoneeApp());
    await shot(tester, '01-welcome');
  }, skip: skip);

  testWidgets('trans, daily', (tester) async {
    phone(tester);
    await openApp(tester);
    await shot(tester, '02-trans-daily');
  }, skip: skip);

  testWidgets('trans, calendar', (tester) async {
    phone(tester);
    await openApp(tester);
    await pill(tester, 'Calendar');
    await shot(tester, '03-trans-calendar');
  }, skip: skip);

  testWidgets('trans, monthly', (tester) async {
    phone(tester);
    await openApp(tester);
    await pill(tester, 'Monthly');
    await shot(tester, '04-trans-monthly');
  }, skip: skip);

  testWidgets('trans, total', (tester) async {
    phone(tester);
    await openApp(tester);
    await pill(tester, 'Total');
    await shot(tester, '05-trans-total');
  }, skip: skip);

  testWidgets('trans, note', (tester) async {
    phone(tester);
    await openApp(tester);
    await pill(tester, 'Note');
    await shot(tester, '06-trans-note');
  }, skip: skip);

  testWidgets('filter', (tester) async {
    phone(tester);
    await openApp(tester);
    await tapOn(tester, find.byTooltip('Filter'));
    await shot(tester, '07-filter');
  }, skip: skip);

  testWidgets('search', (tester) async {
    phone(tester);
    await openApp(tester);
    await tapOn(tester, find.byTooltip('Search'));
    await tester.enterText(find.byType(TextField).first, server.fx['search'] as String);
    // The search runs a moment after the typing stops.
    await tester.pump(const Duration(milliseconds: 500));
    FocusManager.instance.primaryFocus?.unfocus();
    await shot(tester, '08-search');
  }, skip: skip);

  testWidgets('new expense', (tester) async {
    phone(tester);
    await openApp(tester);
    await tapOn(tester, find.byTooltip('Add'));
    await shot(tester, '09-new-expense');
  }, skip: skip);

  testWidgets('edit an expense', (tester) async {
    phone(tester);
    await openApp(tester);
    await tapOn(tester, find.text(pick('expense')['note'] as String));
    await shot(tester, '10-edit-expense');
  }, skip: skip);

  testWidgets('calculator', (tester) async {
    phone(tester);
    await openApp(tester);
    await tapOn(tester, find.byTooltip('Add'));
    await tapOn(tester, find.text('Amount'));
    for (final k in ['1', '2', '5', '0', '+', '3', '0']) {
      await press(tester, k);
    }
    await shot(tester, '11-calculator');
  }, skip: skip);

  testWidgets('stats, pie', (tester) async {
    phone(tester);
    await openApp(tester);
    await openTab(tester, 'Stats');
    await shot(tester, '12-stats-pie');
  }, skip: skip);

  testWidgets('stats, a category', (tester) async {
    phone(tester);
    await openApp(tester);
    await openTab(tester, 'Stats');
    await tapOn(tester, find.text(pick('category')['label'] as String));
    await shot(tester, '13-category-stats');
  }, skip: skip);

  testWidgets('stats, budget', (tester) async {
    phone(tester);
    await openApp(tester);
    await openTab(tester, 'Stats');
    await pill(tester, 'Budget');
    await shot(tester, '14-stats-budget');
  }, skip: skip);

  testWidgets('accounts', (tester) async {
    phone(tester);
    await openApp(tester);
    await openTab(tester, 'Accounts');
    await shot(tester, '15-accounts');
  }, skip: skip);

  testWidgets('a credit card', (tester) async {
    phone(tester);
    await openApp(tester);
    await openTab(tester, 'Accounts');
    await tapOn(tester, find.text(pick('card')['name'] as String));
    await shot(tester, '16-card');
  }, skip: skip);

  testWidgets('asset trend', (tester) async {
    phone(tester);
    await openApp(tester);
    await openTab(tester, 'Accounts');
    await tapOn(tester, find.byTooltip('Asset trend'));
    await shot(tester, '17-asset-trend');
  }, skip: skip);

  testWidgets('more', (tester) async {
    phone(tester);
    await openApp(tester);
    await openTab(tester, 'More');
    await shot(tester, '18-more');
  }, skip: skip);

  // The More tab's pages, each opened from its row.
  const morePages = <(String, String)>[
    ('Configuration', '19-configuration'),
    ('Expense categories', '20-categories'),
    ('Budgets', '21-budgets'),
    ('Currencies', '22-currencies'),
    ('Accounts settings', '23-account-settings'),
    ('Repeats', '24-repeats'),
    ('Passcode', '25-passcode'),
  ];
  for (final (row, name) in morePages) {
    testWidgets('more, $row', (tester) async {
      phone(tester);
      await openApp(tester);
      await openTab(tester, 'More');
      await tapOn(tester, find.text(row));
      await shot(tester, name);
    }, skip: skip);
  }

  // The web app on a computer: the side bar instead of the footer.
  testWidgets('computer, trans', (tester) async {
    computer(tester);
    await openApp(tester);
    await shot(tester, '26-computer-trans');
  }, skip: skip);

  testWidgets('computer, accounts', (tester) async {
    computer(tester);
    await openApp(tester);
    await openTab(tester, 'Accounts');
    await shot(tester, '27-computer-accounts');
  }, skip: skip);
}
