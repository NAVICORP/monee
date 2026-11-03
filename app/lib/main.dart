import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/api.dart';
import 'core/book.dart';
import 'ui/book_gate.dart';
import 'ui/start/welcome.dart';
import 'ui/theme.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb) {
    // Phones stay upright; tablets turn freely.
    final view = PlatformDispatcher.instance.views.first;
    final shortest = view.physicalSize.shortestSide / view.devicePixelRatio;
    if (shortest < 600) await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  }
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: K.surface,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));
  await Api.instance.load();
  runApp(const MoneeApp());
}

class MoneeApp extends StatelessWidget {
  const MoneeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pursee',
      debugShowCheckedModeBanner: false,
      theme: moneeTheme(),
      navigatorKey: navigatorKey,
      supportedLocales: const [Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // Text never grows past a size that breaks the rows.
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        final scale = mq.textScaler.clamp(minScaleFactor: 0.85, maxScaleFactor: 1.3);
        return MediaQuery(data: mq.copyWith(textScaler: scale), child: child!);
      },
      home: const Gate(),
    );
  }
}

/// Signed in (the book) or not (the welcome screen).
class Gate extends StatefulWidget {
  const Gate({super.key});

  @override
  State<Gate> createState() => _GateState();
}

class _GateState extends State<Gate> {
  late final StreamSubscription<Session?> _sub;

  @override
  void initState() {
    super.initState();
    _sub = Api.instance.changes.listen((s) {
      if (s == null) {
        navigatorKey.currentState?.popUntil((r) => r.isFirst);
        Me.instance.signOut();
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final page = Api.instance.signedIn ? const BookGate(key: ValueKey('book')) : const Welcome(key: ValueKey('welcome'));
    return AnimatedSwitcher(duration: const Duration(milliseconds: 250), child: page);
  }
}
