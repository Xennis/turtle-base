import 'dart:async';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:books/books.dart';
import 'package:crdt_file_sync_google_drive/crdt_file_sync_google_drive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:turtle_base/core/app_scope.dart';
import 'package:turtle_base/core/database/app_database.dart';
import 'package:turtle_base/core/database/local_user_id_store.dart';
import 'package:turtle_base/core/platform/window_chrome.dart';
import 'package:turtle_base/core/sync/app_sync_controller.dart';
import 'package:turtle_base/core/sync/sync_scope.dart';
import 'package:turtle_base/core/theme/app_color_scheme.dart';
import 'package:turtle_base/core/theme/theme_controller.dart';
import 'package:turtle_base/core/theme/theme_preset_controller.dart';
import 'package:turtle_base/core/theme/theme_preset_scope.dart';
import 'package:turtle_base/core/theme/theme_scope.dart';
import 'package:turtle_base/features/ai/data/ai_settings_controller.dart';
import 'package:turtle_base/features/ai/widgets/ai_settings_scope.dart';
import 'package:turtle_base/features/files/data/attachments_repository.dart';
import 'package:turtle_base/features/shell/widgets/app_shell.dart';
import 'package:turtle_base/features/tables/data/field_type_registry.dart';
import 'package:turtle_base/packages/file_store/file_store.dart';

/// Field type variants contributed by packages, next to the app's own.
final _fieldTypes = FieldTypeRegistry(variants: booksVariants);

Future<void> main() async {
  // ThemeController.load() does real (if fast) I/O via shared_preferences,
  // which needs the binding ready - and we want the correct theme mode
  // known before the first frame, rather than flashing System then
  // switching.
  WidgetsFlutterBinding.ensureInitialized();
  final themeController = await ThemeController.load();
  final themePresetController = await ThemePresetController.load();
  final aiSettingsController = await AiSettingsController.load();

  final database = AppDatabase(localUserIdStore: await SharedPreferencesLocalUserIdStore.load());
  // This device's first (and only) chance to adopt a fresh users row as
  // its own before sync can merge in any others - see
  // AppDatabase.currentUserId's doc comment. (`database.crdt` below opens
  // the connection itself if this didn't, e.g. because the id was already
  // cached in [LocalUserIdStore].)
  await database.currentUserId();
  // Next to the database, see AppDatabase._openConnection for why the
  // support directory.
  final files = FileStore(p.join((await getApplicationSupportDirectory()).path, 'files'));

  final driveAuthenticator = createDriveAuthenticator(
    desktopClientId: DriveClientConfig.desktopClientId,
    desktopClientSecret: DriveClientConfig.desktopClientSecret,
    androidServerClientId: DriveClientConfig.androidServerClientId,
  );
  if (driveAuthenticator == null) {
    debugPrint(
      '[sync] Google Drive sync disabled - no OAuth client configured for '
      'this platform, see packages/crdt_file_sync_google_drive/README.md.',
    );
  }

  final syncController = AppSyncController(
    crdt: await database.crdt,
    authenticator: driveAuthenticator,
    files: files,
    attachments: AttachmentsRepository(database),
    prefs: await SharedPreferences.getInstance(),
  );
  // Fire-and-forget: don't delay the first frame on a network-ish silent
  // sign-in check - SyncScope's listeners update once/if it resolves.
  unawaited(syncController.restoreConnection());

  runApp(
    TurtleBaseApp(
      database: database,
      files: files,
      themeController: themeController,
      themePresetController: themePresetController,
      aiSettingsController: aiSettingsController,
      syncController: syncController,
    ),
  );
}

class TurtleBaseApp extends StatelessWidget {
  const TurtleBaseApp({
    super.key,
    required this.database,
    required this.files,
    required this.themeController,
    required this.themePresetController,
    required this.aiSettingsController,
    required this.syncController,
  });

  final AppDatabase database;
  final FileStore files;
  final ThemeController themeController;
  final ThemePresetController themePresetController;
  final AiSettingsController aiSettingsController;
  final AppSyncController syncController;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      database: database,
      fieldTypes: _fieldTypes,
      files: files,
      child: SyncScope(
        controller: syncController,
        child: ThemeScope(
          controller: themeController,
          // ShadApp.custom + ShadAppBuilder lets shadcn_ui and Material
          // widgets coexist in the same tree, so features can be migrated
          // to shadcn_ui incrementally instead of all at once (see
          // shadcn-ui-flutter skill's interop guide).
          child: ThemePresetScope(
            controller: themePresetController,
            child: AiSettingsScope(
              controller: aiSettingsController,
              child: Builder(
                builder: (context) {
                  // Depends on ThemeScope and ThemePresetScope (both
                  // InheritedNotifiers), so this whole subtree rebuilds
                  // whenever the user changes the theme mode or color
                  // scheme in Settings.
                  final themeMode = ThemeScope.of(context).mode;
                  final preset = ThemePresetScope.of(context).preset;
                  // Fetched at runtime by google_fonts (cached on disk
                  // after the first fetch) rather than bundled as
                  // assets, so updating the font is a pubspec bump, not
                  // a manual re-download. ShadApp forwards
                  // textTheme.googleFontBuilder into the Material
                  // theme's fontFamily too, so Material widgets pick up
                  // Inter as well.
                  final textTheme = ShadTextTheme.fromGoogleFont(GoogleFonts.inter);
                  return ShadApp.custom(
                    themeMode: themeMode,
                    // The presets' neutral tones are softened app-wide -
                    // see app_color_scheme.dart for why.
                    theme: ShadThemeData(
                      brightness: Brightness.light,
                      colorScheme: softenedLightScheme(preset.light()),
                      textTheme: textTheme,
                    ),
                    darkTheme: ShadThemeData(
                      brightness: Brightness.dark,
                      colorScheme: softenedDarkScheme(preset.dark()),
                      textTheme: textTheme,
                    ),
                    appBuilder: (context) {
                      return MaterialApp(
                        // ShadApp.custom already resolved light/dark via
                        // its own themeMode above - Theme.of(context)
                        // here reflects whichever ShadThemeData that
                        // picked, extended with the component themes
                        // ShadApp leaves at (mismatched) M3 defaults.
                        theme: materialThemeFrom(Theme.of(context), ShadTheme.of(context)),
                        // AppFlowyEditor requires its own localizations
                        // delegate (plus the standard Flutter ones it
                        // depends on) to be registered here - our own app
                        // strings stay hardcoded English for now (see
                        // UI_UX.md), this isn't full l10n setup yet.
                        localizationsDelegates: const [
                          GlobalMaterialLocalizations.delegate,
                          GlobalCupertinoLocalizations.delegate,
                          GlobalWidgetsLocalizations.delegate,
                          AppFlowyEditorLocalizations.delegate,
                        ],
                        supportedLocales: AppFlowyEditorLocalizations.delegate.supportedLocales,
                        home: const WindowChromeSync(child: AppShell()),
                        builder: (context, child) => ShadAppBuilder(child: child!),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
