import 'dart:async';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:googleapis_auth/googleapis_auth.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:turtle_base/core/app_scope.dart';
import 'package:turtle_base/core/database/app_database.dart';
import 'package:turtle_base/core/sync/app_sync_controller.dart';
import 'package:turtle_base/core/sync/sync_scope.dart';
import 'package:turtle_base/core/theme/theme_controller.dart';
import 'package:turtle_base/core/theme/theme_scope.dart';
import 'package:turtle_base/features/ai/data/ai_settings_controller.dart';
import 'package:turtle_base/features/ai/widgets/ai_settings_scope.dart';
import 'package:turtle_base/features/shell/widgets/app_shell.dart';
import 'package:turtle_base/packages/crdt_file_sync/google_drive/client_config.dart';
import 'package:turtle_base/packages/crdt_file_sync/google_drive/drive_authenticator.dart';

Future<void> main() async {
  // ThemeController.load() does real (if fast) I/O via shared_preferences,
  // which needs the binding ready - and we want the correct theme mode
  // known before the first frame, rather than flashing System then
  // switching.
  WidgetsFlutterBinding.ensureInitialized();
  final themeController = await ThemeController.load();
  final aiSettingsController = await AiSettingsController.load();

  final database = AppDatabase();
  // Forces the (otherwise lazily-opened) connection to actually open now,
  // so CrdtDatabaseDelegate exists and `database.crdt` below can resolve -
  // see AppDatabase.crdt's doc comment.
  await database.currentUserId();

  final syncController = AppSyncController(
    crdt: await database.crdt,
    authenticator: createDriveAuthenticator(
      desktopClientId: ClientId(DriveClientConfig.desktopClientId, DriveClientConfig.desktopClientSecret),
      androidServerClientId: DriveClientConfig.androidServerClientId,
    ),
  );
  // Fire-and-forget: don't delay the first frame on a network-ish silent
  // sign-in check - SyncScope's listeners update once/if it resolves.
  unawaited(syncController.restoreConnection());

  runApp(
    TurtleBaseApp(
      database: database,
      themeController: themeController,
      aiSettingsController: aiSettingsController,
      syncController: syncController,
    ),
  );
}

class TurtleBaseApp extends StatelessWidget {
  const TurtleBaseApp({
    super.key,
    required this.database,
    required this.themeController,
    required this.aiSettingsController,
    required this.syncController,
  });

  final AppDatabase database;
  final ThemeController themeController;
  final AiSettingsController aiSettingsController;
  final AppSyncController syncController;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      database: database,
      child: SyncScope(
        controller: syncController,
        child: ThemeScope(
          controller: themeController,
          // ShadApp.custom + ShadAppBuilder lets shadcn_ui and Material
          // widgets coexist in the same tree, so features can be migrated
          // to shadcn_ui incrementally instead of all at once (see
          // shadcn-ui-flutter skill's interop guide).
          child: AiSettingsScope(
            controller: aiSettingsController,
            child: Builder(
              builder: (context) {
                // Depends on ThemeScope (an InheritedNotifier), so this
                // whole subtree rebuilds whenever the user changes the
                // theme in Settings.
                final themeMode = ThemeScope.of(context).mode;
                return ShadApp.custom(
                  themeMode: themeMode,
                  theme: ShadThemeData(
                    brightness: Brightness.light,
                    colorScheme: ShadGreenColorScheme.light(),
                  ),
                  darkTheme: ShadThemeData(
                    brightness: Brightness.dark,
                    colorScheme: ShadGreenColorScheme.dark(),
                  ),
                  appBuilder: (context) {
                    return MaterialApp(
                      // ShadApp.custom already resolved light/dark via its
                      // own themeMode above - Theme.of(context) here
                      // reflects whichever ShadThemeData that picked.
                      theme: Theme.of(context),
                      // AppFlowyEditor requires its own localizations
                      // delegate (plus the standard Flutter ones it depends
                      // on) to be registered here - our own app strings stay
                      // hardcoded English for now (see UI_UX.md), this
                      // isn't full l10n setup yet.
                      localizationsDelegates: const [
                        GlobalMaterialLocalizations.delegate,
                        GlobalCupertinoLocalizations.delegate,
                        GlobalWidgetsLocalizations.delegate,
                        AppFlowyEditorLocalizations.delegate,
                      ],
                      supportedLocales: AppFlowyEditorLocalizations.delegate.supportedLocales,
                      home: const AppShell(),
                      builder: (context, child) => ShadAppBuilder(child: child!),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
