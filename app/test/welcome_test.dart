import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monee/ui/book_gate.dart';
import 'package:monee/ui/start/welcome.dart';
import 'package:monee/ui/theme.dart';

void main() {
  testWidgets('the welcome screen offers WhatsApp and email', (tester) async {
    await tester.pumpWidget(MaterialApp(theme: moneeTheme(), home: const Welcome()));
    expect(find.text('Pursee'), findsOneWidget);
    expect(find.text('Continue with WhatsApp'), findsOneWidget);
    await tester.tap(find.text('Use email instead'));
    await tester.pumpAndSettle();
    expect(find.text('Email me a code'), findsOneWidget);
  });

  testWidgets('a new person starts a book', (tester) async {
    await tester.pumpWidget(MaterialApp(theme: moneeTheme(), home: StartBook(onMade: () async {})));
    expect(find.text('Start your book'), findsOneWidget);
    expect(find.text('Main currency'), findsOneWidget);
  });
}
