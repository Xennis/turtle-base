import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/pump_app.dart';

void main() {
  testWidgets('opens Settings from the sidebar and shows the theme dropdown', (
    WidgetTester tester,
  ) async {
    final database = await pumpApp(tester);
    addTearDown(database.close);

    await tester.tap(find.text('Settings'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Theme'), findsOneWidget);
    // Defaults to System - shown as the dropdown's current value.
    expect(find.text('System'), findsOneWidget);
    // The sidebar (still visible - wide layout) is a sibling, not
    // replaced.
    expect(find.text('Default'), findsOneWidget);
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('choosing Dark from the dropdown persists it for the next app start', (
    WidgetTester tester,
  ) async {
    final database = await pumpApp(tester);
    addTearDown(database.close);

    await tester.tap(find.text('Settings'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.byType(ShadSelect<ThemeMode>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // The dropdown now shows the newly-chosen value.
    expect(find.text('Dark'), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('theme_mode'), 'dark');
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('shows the Sync card, not connected by default', (
    WidgetTester tester,
  ) async {
    final database = await pumpApp(tester);
    addTearDown(database.close);

    await tester.tap(find.text('Settings'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Sync'), findsOneWidget);
    expect(find.text('Google Drive'), findsOneWidget);
    expect(find.text('Not connected'), findsOneWidget);
    expect(find.widgetWithText(ShadButton, 'Connect'), findsOneWidget);
    // Nothing to sync yet - the button is disabled while disconnected.
    final syncNowButton = tester.widget<ShadButton>(
      find.widgetWithText(ShadButton, 'Sync now'),
    );
    expect(syncNowButton.onPressed, isNull);
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
    expect(find.text('Appearance'), findsNothing);
  }, timeout: const Timeout(Duration(seconds: 30)));
}
