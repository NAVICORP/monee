import 'package:flutter/foundation.dart' show kIsWeb;

/// Where the Pursee server lives. In the browser it is the address the app
/// was opened from; on the phones it is monee.skifi.co, or whatever a build
/// names with --dart-define=MONEE_API=https://example.com
const String _built = String.fromEnvironment('MONEE_API', defaultValue: 'https://monee.skifi.co');

String get kApiBase {
  if (kIsWeb) {
    final o = Uri.base;
    if (o.scheme == 'http' || o.scheme == 'https') return o.origin;
  }
  return _built;
}

/// The public site, for links (never the local test address).
const String kSite = _built;
String get kPrivacyUrl => '$kSite/privacy';
String get kTermsUrl => '$kSite/terms';
String get kSupportUrl => '$kSite/support';
const String kSupportEmail = 'contact@skifi.co';

/// The web app, for opening the same book on a computer.
String get kWebAppUrl => '$kSite/app/';
