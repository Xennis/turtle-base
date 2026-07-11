// Flutter's own `Page` (Navigator 2.0) collides with our `Page` data class.
import 'package:flutter/material.dart' hide Page;
import 'package:trina_grid/trina_grid.dart';
import 'package:turtle_base/core/app_scope.dart';
import 'package:turtle_base/core/database/app_database.dart';
import 'package:turtle_base/features/pages/data/pages_repository.dart';
import 'package:turtle_base/features/tables/data/field_type.dart';
import 'package:turtle_base/features/tables/data/relation_field.dart';

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
                // Relation cells show the related entries' titles, not
                // their ids - resolve them from whichever collections
                // this collection's relation fields target.
                final relationTargetIds = fields
                    .where((f) => f.type == FieldType.relation.name)
                    .map((f) => decodeRelationTargetCollectionId(f.config))
                    .whereType<String>()
                    .toSet()
                    .toList();
                return _RelatedPagesResolver(
                  scope: scope,
                  collectionIds: relationTargetIds,
                  builder: (context, relatedPagesByCollection) {
                    return Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (collection != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Row(
                                children: [
                                  if (collection.icon != null) ...[
                                    Text(
                                      collection.icon!,
                                      style: const TextStyle(fontSize: 24),
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                  Text(
                                    collection.name,
                                    style: Theme.of(context).textTheme.titleLarge,
                                  ),
                                ],
                              ),
                            ),
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
                              key: ValueKey(
                                _gridVersion(
                                  titleLabel,
                                  fields,
                                  entries,
                                  relatedPagesByCollection,
                                ),
                              ),
                              columns: _columnsFor(titleLabel, fields),
                              rows: _rowsFor(fields, entries, relatedPagesByCollection),
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
          // Relations are edited via a picker in the entry's Page-View
          // (see PagePropertiesHeader), not inline in the grid.
          readOnly: field.type == FieldType.relation.name,
        ),
    ];
  }

  List<TrinaRow> _rowsFor(
    List<Field> fields,
    List<Page> entries,
    Map<String, List<Page>> relatedPagesByCollection,
  ) {
    return [
      for (final entry in entries)
        TrinaRow(
          data: entry.id,
          cells: {
            'title': TrinaCell(value: entry.title),
            for (final field in fields)
              field.id: TrinaCell(
                value: _cellValue(field, entry, relatedPagesByCollection),
              ),
          },
        ),
    ];
  }

  Object _cellValue(
    Field field,
    Page entry,
    Map<String, List<Page>> relatedPagesByCollection,
  ) {
    final raw = decodePageProperties(entry.properties)[field.id];
    if (field.type == FieldType.relation.name) {
      final targetId = decodeRelationTargetCollectionId(field.config);
      final targetPages = relatedPagesByCollection[targetId] ?? const <Page>[];
      final titles = [
        for (final id in decodeRelationValue(raw)) _titleOf(targetPages, id),
      ];
      return titles.join(', ');
    }
    if (raw == null) return '';
    if (field.type == FieldType.number.name) {
      return num.tryParse(raw.toString()) ?? raw;
    }
    return raw;
  }

  String _titleOf(List<Page> pages, String id) {
    for (final page in pages) {
      if (page.id == id) return page.title.isEmpty ? 'Untitled' : page.title;
    }
    return '?';
  }

  TrinaColumnType _columnTypeFor(Field field) {
    // date/url stay plain text for now - a proper date picker / link
    // rendering is a later refinement, not needed for read-only display.
    return field.type == FieldType.number.name
        ? TrinaColumnType.number()
        : TrinaColumnType.text();
  }

  String _gridVersion(
    String titleLabel,
    List<Field> fields,
    List<Page> entries,
    Map<String, List<Page>> relatedPagesByCollection,
  ) {
    final fieldPart = fields.map((f) => '${f.id}:${f.name}:${f.type}').join(',');
    final entryPart = entries
        .map((e) => '${e.id}:${e.updatedAt.millisecondsSinceEpoch}')
        .join(',');
    // Included so renaming a related entry elsewhere refreshes the
    // resolved titles shown here too (TrinaGrid only reads rows once).
    final relatedPart = relatedPagesByCollection.values
        .expand((pages) => pages)
        .map((p) => '${p.id}:${p.updatedAt.millisecondsSinceEpoch}')
        .join(',');
    return '$titleLabel|$fieldPart|$entryPart|$relatedPart';
  }
}

/// Resolves [collectionIds] to their entries, nesting one StreamBuilder
/// per id - not meant for large numbers of collections, but a
/// collection's relation fields are expected to target only a few.
class _RelatedPagesResolver extends StatelessWidget {
  const _RelatedPagesResolver({
    required this.scope,
    required this.collectionIds,
    required this.builder,
  });

  final AppScope scope;
  final List<String> collectionIds;
  final Widget Function(BuildContext, Map<String, List<Page>>) builder;

  @override
  Widget build(BuildContext context) => _build(context, collectionIds, const {});

  Widget _build(
    BuildContext context,
    List<String> remaining,
    Map<String, List<Page>> resolved,
  ) {
    if (remaining.isEmpty) return builder(context, resolved);
    final collectionId = remaining.first;
    return StreamBuilder<List<Page>>(
      stream: scope.pages.watchAllInCollection(collectionId),
      builder: (context, snapshot) {
        return _build(context, remaining.sublist(1), {
          ...resolved,
          collectionId: snapshot.data ?? const <Page>[],
        });
      },
    );
  }
}
