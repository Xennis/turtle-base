import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:turtle_base/core/app_scope.dart';
import 'package:turtle_base/core/database/app_database.dart';
import 'package:turtle_base/core/theme/theme_controller.dart';
import 'package:turtle_base/core/theme/theme_scope.dart';
import 'package:turtle_base/features/shell/widgets/app_shell.dart';

Future<void> main() async {
  // ThemeController.load() does real (if fast) I/O via shared_preferences,
  // which needs the binding ready - and we want the correct theme mode
  // known before the first frame, rather than flashing System then
  // switching.
  WidgetsFlutterBinding.ensureInitialized();
  final themeController = await ThemeController.load();
  runApp(TurtleBaseApp(database: AppDatabase(), themeController: themeController));
}

class TurtleBaseApp extends StatelessWidget {
  const TurtleBaseApp({super.key, required this.database, required this.themeController});

  final AppDatabase database;
  final ThemeController themeController;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      database: database,
      child: ThemeScope(
        controller: themeController,
        // ShadApp.custom + ShadAppBuilder lets shadcn_ui and Material
        // widgets coexist in the same tree, so features can be migrated
        // to shadcn_ui incrementally instead of all at once (see
        // shadcn-ui-flutter skill's interop guide).
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
    );
  }
}
