import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/pump_app.dart';

void main() {
  testWidgets('opens Settings from the sidebar and shows the theme options', (
    WidgetTester tester,
  ) async {
    final database = await pumpApp(tester);
    addTearDown(database.close);

    await tester.tap(find.text('Settings'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Theme'), findsOneWidget);
    expect(find.text('System'), findsOneWidget);
    expect(find.text('Light'), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget);
    // The sidebar (still visible - wide layout) is a sibling, not
    // replaced.
    expect(find.text('Default'), findsOneWidget);
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('choosing Dark persists it for the next app start', (
    WidgetTester tester,
  ) async {
    final database = await pumpApp(tester);
    addTearDown(database.close);

    await tester.tap(find.text('Settings'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('Dark'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('theme_mode'), 'dark');
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('back returns to whatever was showing before Settings', (
    WidgetTester tester,
  ) async {
    final database = await pumpApp(tester);
    addTearDown(database.close);

    await tester.tap(find.text('Settings'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Select a collection or page'), findsOneWidget);
    expect(find.text('Theme'), findsNothing);
  }, timeout: const Timeout(Duration(seconds: 30)));
}
