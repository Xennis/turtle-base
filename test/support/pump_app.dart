import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite_crdt/sqlite_crdt.dart';
import 'package:turtle_base/core/app_scope.dart';
import 'package:turtle_base/core/database/app_database.dart';
import 'package:turtle_base/core/sync/app_sync_controller.dart';
import 'package:turtle_base/core/sync/sync_scope.dart';
import 'package:turtle_base/core/theme/theme_controller.dart';
import 'package:turtle_base/core/theme/theme_scope.dart';
import 'package:turtle_base/features/ai/data/ai_settings_controller.dart';
import 'package:turtle_base/features/ai/widgets/ai_settings_scope.dart';
import 'package:turtle_base/features/shell/widgets/app_shell.dart';
import 'package:turtle_base/features/spaces/data/spaces_repository.dart';

import 'fake_drive_authenticator.dart';

/// An in-memory database for widget tests.
///
/// closeStreamsSynchronously avoids a pending-timer failure: by default
/// a drift stream query stays open for one event loop turn after the
/// last subscriber unsubscribes, which flutter_test flags as a leaked
/// timer at teardown. See drift.simonbinder.eu/testing.
AppDatabase newTestDatabase() {
  return AppDatabase.withExecutor(
    DatabaseConnection(
      NativeDatabase.memory(),
      closeStreamsSynchronously: true,
    ),
  );
}

/// Mirrors the real app's ShadApp.custom + MaterialApp setup (see
/// main.dart) - shared by any test that pumps a widget tree that may
/// reach a shadcn_ui component (ShadTheme.of requires this ancestor)
/// or AppFlowyEditor (which needs its own localizations delegate).
Widget wrapWithAppLocalizations(Widget home) {
  return ShadApp.custom(
    theme: ShadThemeData(
      brightness: Brightness.light,
      colorScheme: const ShadZincColorScheme.light(),
    ),
    appBuilder: (context) {
      return MaterialApp(
        theme: Theme.of(context),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          AppFlowyEditorLocalizations.delegate,
        ],
        supportedLocales: AppFlowyEditorLocalizations.delegate.supportedLocales,
        home: home,
        builder: (context, child) => ShadAppBuilder(child: child!),
      );
    },
  );
}

/// Sets up and pumps the full app against a fresh in-memory database.
///
/// NativeDatabase does real FFI I/O for migration/seeding, which needs
/// runAsync() - but only for the real async work, not for pumping
/// (mixing the two hangs the test).
///
/// [seedDefaultSpace] mirrors what most tests need - some existing
/// space to select/populate - even though AppDatabase itself no longer
/// seeds one (see its _seedDefaults doc comment). Tests covering the
/// "no spaces yet" empty state pass false.
Future<AppDatabase> pumpApp(WidgetTester tester, {bool seedDefaultSpace = true}) async {
  final database = newTestDatabase();
  await tester.runAsync(() => database.currentUserId());
  if (seedDefaultSpace) {
    await tester.runAsync(() => SpacesRepository(database).create(name: 'Default'));
  }
  // Mocked (no real platform channel), so unlike the database above,
  // this doesn't need runAsync().
  SharedPreferences.setMockInitialValues({});
  final themeController = await ThemeController.load();
  final aiSettingsController = await AiSettingsController.load();
  // Unrelated to `database` above - SyncScope just needs *a* SqliteCrdt to
  // construct AppSyncController; no widget test exercises sync itself
  // (FakeDriveAuthenticator never reaches Google).
  final syncCrdt = await tester.runAsync(SqliteCrdt.openInMemory);
  final syncController = AppSyncController(
    crdt: syncCrdt!,
    authenticator: FakeDriveAuthenticator(),
  );
  await tester.pumpWidget(
    ThemeScope(
      controller: themeController,
      child: AiSettingsScope(
        controller: aiSettingsController,
        child: ThemeScope(
          controller: themeController,
          child: SyncScope(
            controller: syncController,
            child: AppScope(
              database: database,
              child: wrapWithAppLocalizations(const AppShell()),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  // One more pump for the sidebar's default-space auto-select
  // (postFrameCallback -> notifyListeners -> rebuild) to settle.
  await tester.pump();
  return database;
}
