import 'package:flutter/widgets.dart';
import 'package:turtle_base/core/database/app_database.dart';
import 'package:turtle_base/features/pages/data/blocks_repository.dart';
import 'package:turtle_base/features/pages/data/pages_repository.dart';
import 'package:turtle_base/features/spaces/data/spaces_repository.dart';
import 'package:turtle_base/features/tables/data/collections_repository.dart';
import 'package:turtle_base/features/tables/data/fields_repository.dart';

/// Makes the database and repositories available to the widget tree,
/// built with the plain InheritedWidget instead of a DI package.
class AppScope extends InheritedWidget {
  AppScope({super.key, required this.database, required super.child})
    : spaces = SpacesRepository(database),
      collections = CollectionsRepository(database),
      fields = FieldsRepository(database),
      pages = PagesRepository(database),
      blocks = BlocksRepository(database);

  final AppDatabase database;
  final SpacesRepository spaces;
  final CollectionsRepository collections;
  final FieldsRepository fields;
  final PagesRepository pages;
  final BlocksRepository blocks;

  static AppScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'No AppScope found in context');
    return scope!;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) => database != oldWidget.database;
}
