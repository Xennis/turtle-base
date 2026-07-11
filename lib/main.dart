import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:turtle_base/core/app_scope.dart';
import 'package:turtle_base/core/database/app_database.dart';
import 'package:turtle_base/features/shell/widgets/app_shell.dart';

void main() {
  runApp(TurtleBaseApp(database: AppDatabase()));
}

class TurtleBaseApp extends StatelessWidget {
  const TurtleBaseApp({super.key, required this.database});

  final AppDatabase database;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      database: database,
      // ShadApp.custom + ShadAppBuilder lets shadcn_ui and Material
      // widgets coexist in the same tree, so features can be migrated
      // to shadcn_ui incrementally instead of all at once (see
      // shadcn-ui-flutter skill's interop guide).
      child: ShadApp.custom(
        themeMode: ThemeMode.system,
        theme: ShadThemeData(
          brightness: Brightness.light,
          colorScheme: const ShadZincColorScheme.light(),
        ),
        darkTheme: ShadThemeData(
          brightness: Brightness.dark,
          colorScheme: const ShadZincColorScheme.dark(),
        ),
        appBuilder: (context) {
          return MaterialApp(
            // ShadApp.custom already resolved light/dark via its own
            // themeMode above - Theme.of(context) here reflects
            // whichever ShadThemeData that picked.
            theme: Theme.of(context),
            // AppFlowyEditor requires its own localizations delegate
            // (plus the standard Flutter ones it depends on) to be
            // registered here - our own app strings stay hardcoded
            // English for now (see UI_UX.md), this isn't full l10n
            // setup yet.
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
      ),
    );
  }
}
