import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme.dart';

/// Night mode: off, on, or the same as the phone. Kept on this device, so a
/// shared book never changes how it looks for someone else.
///
/// The colours in [K] are read on every build, so switching sets [K.dark],
/// redraws every screen that is open, and rebuilds the app's theme through
/// [changes].
class Night {
  static const _key = 'pursee.night';

  /// off, on or phone.
  static String mode = 'off';

  /// Ticks when the app turns dark or light.
  static final changes = ValueNotifier<int>(0);

  static bool _watching = false;

  static String get label => labelOf(mode);

  static String labelOf(String m) => switch (m) {
        'on' => 'On',
        'phone' => 'Same as phone',
        _ => 'Off',
      };

  /// Reads the choice before the app first draws, and follows the phone
  /// from then on when asked to.
  static Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      mode = _ok(p.getString(_key));
    } catch (_) {
      // Off until the choice can be read.
    }
    if (!_watching) {
      _watching = true;
      WidgetsBinding.instance.addObserver(_PhoneWatcher());
    }
    apply();
  }

  static Future<void> set(String m) async {
    mode = _ok(m);
    apply();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_key, mode);
    } catch (_) {
      // Kept for this visit at least.
    }
  }

  static String _ok(String? m) => m == 'on' || m == 'phone' ? m! : 'off';

  /// Works out whether the app is dark now, and redraws it when that changed.
  static void apply() {
    final phoneDark = WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark;
    final dark = mode == 'on' || (mode == 'phone' && phoneDark);
    SystemChrome.setSystemUIOverlayStyle(styleFor(dark));
    if (dark == K.dark) return;
    K.dark = dark;
    changes.value++;
    _redrawAll();
  }

  /// The status bar and the phone's own bottom bar, to match.
  static SystemUiOverlayStyle styleFor(bool dark) => SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
        statusBarBrightness: dark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: dark ? const Color(0xFF1A1627) : const Color(0xFFFFFFFF),
        systemNavigationBarIconBrightness: dark ? Brightness.light : Brightness.dark,
      );

  /// Every screen that is open builds again, with the new colours.
  static void _redrawAll() {
    void mark(Element e) {
      e.markNeedsBuild();
      e.visitChildren(mark);
    }

    WidgetsBinding.instance.rootElement?.visitChildren(mark);
  }
}

class _PhoneWatcher with WidgetsBindingObserver {
  @override
  void didChangePlatformBrightness() {
    if (Night.mode == 'phone') Night.apply();
  }
}
