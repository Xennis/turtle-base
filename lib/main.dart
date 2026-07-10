import 'package:flutter/material.dart';
import 'package:turtle_base/core/app_scope.dart';
import 'package:turtle_base/core/database/app_database.dart';
import 'package:turtle_base/features/shell/app_shell.dart';

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
      child: const MaterialApp(home: AppShell()),
    );
  }
}
