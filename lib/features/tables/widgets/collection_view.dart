// Flutter's own `Page` (Navigator 2.0) collides with our `Page` data class.
import 'package:flutter/material.dart' hide Page;
import 'package:trina_grid/trina_grid.dart';
import 'package:turtle_base/core/app_scope.dart';
import 'package:turtle_base/core/database/app_database.dart';
import 'package:turtle_base/features/pages/data/pages_repository.dart';
import 'package:turtle_base/features/tables/data/field_type.dart';

/// Grid view of a collection's entries, with inline cell editing for
/// text/number/date/url. Edits are persisted immediately on commit
/// (TrinaGrid's onChanged fires on Enter/Tab/blur, not per keystroke).
class CollectionView extends StatelessWidget {
  const CollectionView({
    super.key,
    required this.collectionId,
    required this.onEdit,
    required this.onOpenEntry,
    this.onLoaded,
  });

  final String collectionId;

  /// Switches the content area to CollectionEditPage - a callback
  /// rather than a Navigator.push, so the sidebar stays visible (see
  /// AppShell/_MainContent).
  final VoidCallback onEdit;

  /// Switches the content area to the entry's Page-View, called with
  /// the entry's page id. Same callback-not-push pattern as [onEdit].
  final ValueChanged<String> onOpenEntry;

  /// Exposed for tests to reach the TrinaGridStateManager.
  final void Function(TrinaGridOnLoadedEvent event)? onLoaded;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return StreamBuilder<Collection>(
      stream: scope.collections.watchById(collectionId),
      builder: (context, collectionSnapshot) {
        final collection = collectionSnapshot.data;
        final titleLabel = collection?.titleFieldLabel ?? 'Name';
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            OutlinedButton.icon(
                              icon: const Icon(Icons.add),
                              label: const Text('Add row'),
                              onPressed: () => _addRow(scope),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              icon: const Icon(Icons.edit_outlined),
                              label: const Text('Edit collection'),
                              onPressed: onEdit,
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        // TrinaGrid only reads columns/rows once (see
                        // its didUpdateWidget), so a Key that changes
                        // with the data forces a fresh grid instead of
                        // stale rows.
                        child: TrinaGrid(
                          key: ValueKey(_gridVersion(titleLabel, fields, entries)),
                          columns: _columnsFor(titleLabel, fields),
                          rows: _rowsFor(fields, entries),
                          onChanged: (event) => _onCellChanged(scope, event),
                          onRowDoubleTap: (event) =>
                              onOpenEntry(event.row.data as String),
                          onLoaded: onLoaded,
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  /// A blank entry, filled in directly in the grid afterwards - no
  /// separate creation page, matching the inline-editing style already
  /// used for cells and fields.
  Future<void> _addRow(AppScope scope) async {
    final collection = await scope.collections.watchById(collectionId).first;
    await scope.pages.create(
      spaceId: collection.spaceId,
      collectionId: collectionId,
    );
  }

  Future<void> _onCellChanged(
    AppScope scope,
    TrinaGridOnChangedEvent event,
  ) async {
    final entryId = event.row.data as String;
    if (event.column.field == 'title') {
      await scope.pages.rename(entryId, event.value.toString());
    } else {
      await scope.pages.setPropertyValue(
        entryId,
        event.column.field,
        event.value.toString(),
      );
    }
  }

  List<TrinaColumn> _columnsFor(String titleLabel, List<Field> fields) {
    return [
      // Not editable via "Manage fields" - it's the built-in title,
      // not a user-defined field. Its label is customizable per
      // collection (CollectionEditPage) though, unlike the column
      // itself.
      TrinaColumn(title: titleLabel, field: 'title', type: TrinaColumnType.text()),
      for (final field in fields)
        TrinaColumn(
          title: field.name,
          field: field.id,
          type: _columnTypeFor(field),
        ),
    ];
  }

  List<TrinaRow> _rowsFor(List<Field> fields, List<Page> entries) {
    return [
      for (final entry in entries)
        TrinaRow(
          data: entry.id,
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

  String _gridVersion(String titleLabel, List<Field> fields, List<Page> entries) {
    final fieldPart = fields.map((f) => '${f.id}:${f.name}:${f.type}').join(',');
    final entryPart = entries
        .map((e) => '${e.id}:${e.updatedAt.millisecondsSinceEpoch}')
        .join(',');
    return '$titleLabel|$fieldPart|$entryPart';
  }
}
