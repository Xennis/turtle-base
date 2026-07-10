// Flutter's own `Page` (Navigator 2.0) collides with our `Page` data class.
import 'package:flutter/material.dart' hide Page;
import 'package:trina_grid/trina_grid.dart';
import 'package:turtle_base/core/app_scope.dart';
import 'package:turtle_base/core/database/app_database.dart';
import 'package:turtle_base/features/pages/data/pages_repository.dart';
import 'package:turtle_base/features/tables/widgets/field_editor_dialog.dart';
import 'package:turtle_base/features/tables/data/field_type.dart';
import 'package:turtle_base/features/tables/data/fields_repository.dart';

/// Grid view of a collection's entries, with inline cell editing for
/// text/number/date/url. Edits are persisted immediately on commit
/// (TrinaGrid's onChanged fires on Enter/Tab/blur, not per keystroke).
class CollectionView extends StatelessWidget {
  const CollectionView({super.key, required this.collectionId, this.onLoaded});

  final String collectionId;

  /// Exposed for tests to reach the TrinaGridStateManager.
  final void Function(TrinaGridOnLoadedEvent event)? onLoaded;

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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text('Add field'),
                      onPressed: () => showFieldEditorDialog(
                        context,
                        fields: scope.fields,
                        collectionId: collectionId,
                      ),
                    ),
                  ),
                  Expanded(
                    // TrinaGrid only reads columns/rows once (see its
                    // didUpdateWidget), so a Key that changes with the
                    // data forces a fresh grid instead of stale rows.
                    child: TrinaGrid(
                      key: ValueKey(_gridVersion(fields, entries)),
                      columns: _columnsFor(context, scope.fields, fields),
                      rows: _rowsFor(fields, entries),
                      onChanged: (event) => _onCellChanged(scope, event),
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

  List<TrinaColumn> _columnsFor(
    BuildContext context,
    FieldsRepository fieldsRepository,
    List<Field> fields,
  ) {
    return [
      // Not editable via the Field-Editor - it's the built-in title,
      // not a user-defined field.
      TrinaColumn(title: 'Name', field: 'title', type: TrinaColumnType.text()),
      for (final field in fields)
        TrinaColumn(
          title: field.name,
          field: field.id,
          type: _columnTypeFor(field),
          titleRenderer: (rendererContext) => _FieldColumnTitle(
            rendererContext: rendererContext,
            onEdit: () => showFieldEditorDialog(
              context,
              fields: fieldsRepository,
              collectionId: collectionId,
              fieldId: field.id,
              initialName: field.name,
              initialType: FieldType.values.byName(field.type),
            ),
          ),
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

  String _gridVersion(List<Field> fields, List<Page> entries) {
    final fieldPart = fields.map((f) => '${f.id}:${f.name}:${f.type}').join(',');
    final entryPart = entries
        .map((e) => '${e.id}:${e.updatedAt.millisecondsSinceEpoch}')
        .join(',');
    return '$fieldPart|$entryPart';
  }
}

/// Column header with an edit icon opening the Field-Editor dialog.
class _FieldColumnTitle extends StatelessWidget {
  const _FieldColumnTitle({required this.rendererContext, required this.onEdit});

  final TrinaColumnTitleRendererContext rendererContext;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: rendererContext.column.width,
      height: rendererContext.height,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              rendererContext.column.title,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 16),
            tooltip: 'Edit field',
            onPressed: onEdit,
            constraints: const BoxConstraints(minHeight: 28, minWidth: 28),
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }
}
