import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:turtle_base/core/database/app_database.dart';
import 'package:turtle_base/features/files/data/attachments_repository.dart';
import 'package:turtle_base/features/pages/data/blocks_repository.dart';
import 'package:turtle_base/features/pages/data/pages_repository.dart';
import 'package:turtle_base/features/plugins/data/plugin_instances_repository.dart';
import 'package:turtle_base/features/plugins/data/plugin_registry.dart';
import 'package:turtle_base/features/spaces/data/spaces_repository.dart';
import 'package:turtle_base/features/tables/data/collections_repository.dart';
import 'package:turtle_base/features/tables/data/field_type_registry.dart';
import 'package:turtle_base/features/tables/data/fields_repository.dart';
import 'package:turtle_base/packages/file_store/file_store.dart';

/// Makes the database and repositories available to the widget tree,
/// built with the plain InheritedWidget instead of a DI package.
class AppScope extends InheritedWidget {
  /// [files] defaults to a store in the system's temp directory - for
  /// tests, the app passes its own (see main.dart).
  AppScope({
    super.key,
    required this.database,
    FieldTypeRegistry? fieldTypes,
    PluginRegistry? plugins,
    FileStore? files,
    required super.child,
  }) : fieldTypes = fieldTypes ?? FieldTypeRegistry(),
       plugins = plugins ?? PluginRegistry(),
       pluginInstances = PluginInstancesRepository(database),
       files = files ?? FileStore(p.join(Directory.systemTemp.path, 'turtle_base_files')),
       spaces = SpacesRepository(database),
       collections = CollectionsRepository(database),
       fields = FieldsRepository(database, fieldTypes: fieldTypes),
       pages = PagesRepository(database),
       blocks = BlocksRepository(database),
       attachments = AttachmentsRepository(database);

  final AppDatabase database;
  final FieldTypeRegistry fieldTypes;
  final PluginRegistry plugins;
  final PluginInstancesRepository pluginInstances;
  final SpacesRepository spaces;
  final CollectionsRepository collections;
  final FieldsRepository fields;
  final PagesRepository pages;
  final BlocksRepository blocks;
  final FileStore files;
  final AttachmentsRepository attachments;

  static AppScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'No AppScope found in context');
    return scope!;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) => database != oldWidget.database;
}
