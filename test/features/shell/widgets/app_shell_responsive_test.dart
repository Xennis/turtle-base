import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:turtle_base/features/shell/widgets/app_shell.dart';

import '../../../support/pump_app.dart';

void setNarrowSize(WidgetTester tester) {
  tester.view.physicalSize = Size(AppShell.wideBreakpoint - 200, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// pumpAndSettle() is safe here specifically because nothing with a
/// periodic timer (e.g. AppFlowyEditor's cursor blink) is mounted yet -
/// the drawer's slide-in animation just needs more than a fixed pump.
Future<void> openDrawer(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.menu));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('narrow layout hides the sidebar behind a drawer', (
    WidgetTester tester,
  ) async {
    setNarrowSize(tester);
    final database = await pumpApp(tester);
    addTearDown(database.close);

    // Sidebar content isn't directly visible on a narrow screen...
    expect(find.text('Collections'), findsNothing);

    // ...until the drawer (reachable via the AppBar's auto-hamburger,
    // since narrower than AppShell.wideBreakpoint) is opened.
    await openDrawer(tester);

    expect(find.text('Collections'), findsOneWidget);
    expect(find.text('Default'), findsOneWidget);
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('wide layout keeps the sidebar permanently visible', (
    WidgetTester tester,
  ) async {
    // Default test surface is already wide (800x600) - this just pins
    // it explicitly rather than relying on the framework default.
    tester.view.physicalSize = Size(AppShell.wideBreakpoint + 600, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final database = await pumpApp(tester);
    addTearDown(database.close);

    expect(find.text('Collections'), findsOneWidget);
    expect(find.byIcon(Icons.menu), findsNothing);
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets(
    'selecting a page on a narrow screen closes the drawer and shows a back button',
    (WidgetTester tester) async {
      setNarrowSize(tester);
      final database = await pumpApp(tester);
      addTearDown(database.close);

      await openDrawer(tester);

      await tester.tap(find.byTooltip('New page'));
      // Creating a page does real FFI I/O, and PageDetailView's own
      // initial load does too - same runAsync pattern as the wide-layout
      // equivalent test in app_shell_test.dart.
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
      // Not pumpAndSettle() - AppFlowyEditor is mounted by this point,
      // and its cursor blink is a periodic timer. The drawer's own
      // closing animation still needs more than one bounded pump though.
      await tester.pump(const Duration(milliseconds: 300));

      // The drawer closed itself once a page was selected.
      expect(find.text('Collections'), findsNothing);
      expect(find.byTooltip('Back'), findsOneWidget);

      await tester.tap(find.byTooltip('Back'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Select a collection or page'), findsOneWidget);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    'editing a collection on a narrow screen shows its own back button, not a second AppBar',
    (WidgetTester tester) async {
      setNarrowSize(tester);
      final database = await pumpApp(tester);
      addTearDown(database.close);

      await openDrawer(tester);

      await tester.tap(find.byTooltip('New collection'));
      await tester.pump();
      await tester.enterText(find.byType(ShadInput), 'Tasks');
      await tester.tap(find.text('Save'));
      await tester.pump();
      // ShadDialog's own close animation, like the drawer's, needs more
      // than a single bounded pump to fully settle.
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('Tasks'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.widgetWithText(ShadButton, 'Edit collection'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Only CollectionEditPage's own AppBar - not stacked with ours.
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.text('Fields'), findsOneWidget);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
