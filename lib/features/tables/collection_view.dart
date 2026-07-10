// Flutter's own `Page` (Navigator 2.0) collides with our `Page` data class.
import 'package:flutter/material.dart' hide Page;
import 'package:trina_grid/trina_grid.dart';
import 'package:turtle_base/core/app_scope.dart';
import 'package:turtle_base/core/database/app_database.dart';
import 'package:turtle_base/features/pages/pages_repository.dart';
import 'package:turtle_base/features/tables/field_type.dart';

/// Grid view of a collection's entries. Read-only for now - editing
/// cells is a later step.
class CollectionView extends StatelessWidget {
  const CollectionView({super.key, required this.collectionId});

  final String collectionId;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return StreamBuilder<List<Field>>(
      stream: scope.fields.watchAllInCollection(collectionId),
      builder: (context, fieldsSnapshot) {
        final fields = fieldsSnapshot.data ?? const <Field>[];
        return StreamBuilder<List<Page>>(
          stream: scope.pages.watchAllInCollection(collectionId),
          builder: (context, entriesSnapshot) {
            final entries = entriesSnapshot.data ?? const <Page>[];
            return Padding(
              padding: const EdgeInsets.all(16),
              // TrinaGrid only reads columns/rows once (see its
              // didUpdateWidget), so a Key that changes with the data
              // forces a fresh grid instead of showing stale rows.
              child: TrinaGrid(
                key: ValueKey(_gridVersion(fields, entries)),
                columns: _columnsFor(fields),
                rows: _rowsFor(fields, entries),
              ),
            );
          },
        );
      },
    );
  }

  List<TrinaColumn> _columnsFor(List<Field> fields) {
    return [
      TrinaColumn(
        title: 'Name',
        field: 'title',
        type: TrinaColumnType.text(),
        readOnly: true,
      ),
      for (final field in fields)
        TrinaColumn(
          title: field.name,
          field: field.id,
          type: _columnTypeFor(field),
          readOnly: true,
        ),
    ];
  }

  List<TrinaRow> _rowsFor(List<Field> fields, List<Page> entries) {
    return [
      for (final entry in entries)
        TrinaRow(
          cells: {
            'title': TrinaCell(value: entry.title),
            for (final field in fields)
              field.id: TrinaCell(value: _cellValue(field, entry)),
          },
        ),
    ];
  }

  Object _cellValue(Field field, Page entry) {
    final raw = decodePageProperties(entry.properties)[field.id];
    if (raw == null) return '';
    if (field.type == FieldType.number.name) {
      return num.tryParse(raw.toString()) ?? raw;
    }
    return raw;
  }

  TrinaColumnType _columnTypeFor(Field field) {
    // date/url stay plain text for now - a proper date picker / link
    // rendering is a later refinement, not needed for read-only display.
    return field.type == FieldType.number.name
        ? TrinaColumnType.number()
        : TrinaColumnType.text();
  }

  String _gridVersion(List<Field> fields, List<Page> entries) {
    final fieldPart = fields.map((f) => '${f.id}:${f.name}:${f.type}').join(',');
    final entryPart = entries
        .map((e) => '${e.id}:${e.updatedAt.millisecondsSinceEpoch}')
        .join(',');
    return '$fieldPart|$entryPart';
  }
}
