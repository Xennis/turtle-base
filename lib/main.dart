import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
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
      // AppFlowyEditor requires its own localizations delegate (plus
      // the standard Flutter ones it depends on) to be registered here
      // - our own app strings stay hardcoded English for now (see
      // UI_UX.md), this isn't full l10n setup yet.
      child: MaterialApp(
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          AppFlowyEditorLocalizations.delegate,
        ],
        supportedLocales: AppFlowyEditorLocalizations.delegate.supportedLocales,
        home: const AppShell(),
      ),
    );
  }
}
