// Flutter's own `Page` (Navigator 2.0) collides with our `Page` data class.
import 'package:flutter/material.dart' hide Page;
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:trina_grid/trina_grid.dart';
import 'package:turtle_base/core/app_scope.dart';
import 'package:turtle_base/core/database/app_database.dart';
import 'package:turtle_base/features/pages/data/pages_repository.dart';
import 'package:turtle_base/features/tables/data/field_type.dart';
import 'package:turtle_base/features/tables/data/field_validation.dart';
import 'package:turtle_base/features/tables/data/relation_field.dart';
import 'package:url_launcher/url_launcher.dart';

/// Storage/display format for date fields - also what TrinaGrid's date
/// picker writes back on selection (see TrinaColumnTypeDate).
const _dateFormat = 'yyyy-MM-dd';

/// Grid view of a collection's entries, with inline cell editing for
/// text/number/date/url. Edits are persisted immediately on commit
/// (TrinaGrid's onChanged fires on Enter/Tab/blur, not per keystroke).
/// Invalid values (bad date, malformed URL) are rejected by TrinaGrid's
/// column validation and never reach [_onCellChanged]. Stored values
/// that no longer match a field's type (e.g. after changing it from
/// Text to Number/Date/URL - see FieldsRepository.changeType) are never
/// silently dropped or misrepresented as valid; each typed column's
/// renderer flags them in red instead.
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
    final theme = ShadTheme.of(context);
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
                                    style: ShadTheme.of(context).textTheme.h3,
                                  ),
                                ],
                              ),
                            ),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            // Wrap rather than Row - on narrow screens
                            // (see UI_UX.md's Responsive/Adaptive Layout)
                            // both buttons side by side don't fit.
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                ShadButton.outline(
                                  leading: const Icon(Icons.add, size: 16),
                                  onPressed: () => _addRow(scope),
                                  child: const Text('Add row'),
                                ),
                                ShadButton.outline(
                                  leading: const Icon(
                                    Icons.edit_outlined,
                                    size: 16,
                                  ),
                                  onPressed: onEdit,
                                  child: const Text('Edit collection'),
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
                              columns: _columnsFor(
                                titleLabel,
                                fields,
                                theme.colorScheme,
                              ),
                              rows: _rowsFor(
                                fields,
                                entries,
                                relatedPagesByCollection,
                              ),
                              configuration: _gridConfiguration(theme),
                              onChanged: (event) =>
                                  _onCellChanged(scope, event),
                              onRowDoubleTap: (event) =>
                                  onOpenEntry(event.row.data as String),
                              onValidationFailed: (event) =>
                                  _onValidationFailed(context, event),
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

  /// TrinaGrid doesn't follow the ambient theme on its own - without a
  /// configuration it always renders its light default styling, so the
  /// grid stayed white in dark mode. Map the shadcn tokens onto its
  /// style config instead; the `.dark` constructor also sets
  /// `isDarkStyle`, which TrinaGrid's own popups (column menu, date
  /// picker) use to pick their text colors.
  TrinaGridConfiguration _gridConfiguration(ShadThemeData theme) {
    final colors = theme.colorScheme;
    final cellTextStyle = TextStyle(fontSize: 14, color: colors.foreground);
    final columnTextStyle = TextStyle(
      color: colors.foreground,
      decoration: TextDecoration.none,
      fontSize: 14,
      fontWeight: FontWeight.w600,
    );
    final gridBorderRadius = BorderRadius.circular(8);
    final style = theme.brightness == Brightness.dark
        ? TrinaGridStyleConfig.dark(
            // card, not background: on the wide layout the grid sits on
            // the floating content panel (see AppShell/_WideShell).
            gridBackgroundColor: colors.card,
            rowColor: colors.card,
            activatedColor: colors.accent,
            activatedBorderColor: colors.ring,
            inactivatedBorderColor: colors.border,
            gridBorderColor: colors.border,
            borderColor: colors.border,
            cellTextStyle: cellTextStyle,
            columnTextStyle: columnTextStyle,
            iconColor: colors.mutedForeground,
            menuBackgroundColor: colors.popover,
            cellColorInEditState: colors.card,
            cellColorInReadOnlyState: colors.muted,
            gridBorderRadius: gridBorderRadius,
          )
        : TrinaGridStyleConfig(
            // card, not background - same reason as the dark branch.
            gridBackgroundColor: colors.card,
            rowColor: colors.card,
            activatedColor: colors.accent,
            activatedBorderColor: colors.ring,
            inactivatedBorderColor: colors.border,
            gridBorderColor: colors.border,
            borderColor: colors.border,
            cellTextStyle: cellTextStyle,
            columnTextStyle: columnTextStyle,
            iconColor: colors.mutedForeground,
            menuBackgroundColor: colors.popover,
            cellColorInEditState: colors.card,
            cellColorInReadOnlyState: colors.muted,
            gridBorderRadius: gridBorderRadius,
          );
    return TrinaGridConfiguration(style: style);
  }

  List<TrinaColumn> _columnsFor(
    String titleLabel,
    List<Field> fields,
    ShadColorScheme colors,
  ) {
    return [
      // Not editable via "Manage fields" - it's the built-in title,
      // not a user-defined field. Its label is customizable per
      // collection (CollectionEditPage) though, unlike the column
      // itself.
      TrinaColumn(
        title: titleLabel,
        field: 'title',
        type: TrinaColumnType.text(),
      ),
      for (final field in fields)
        TrinaColumn(
          title: field.name,
          field: field.id,
          type: _columnTypeFor(field),
          // Relations are edited via a picker in the entry's Page-View
          // (see PagePropertiesHeader), not inline in the grid.
          readOnly: field.type == FieldType.relation.name,
          validator: field.type == FieldType.url.name ? _validateUrl : null,
          renderer: _rendererFor(field, colors),
        ),
    ];
  }

  /// [colors] is passed in because [TrinaColumnRendererContext] carries
  /// no BuildContext to resolve the theme from inside a renderer.
  TrinaColumnRenderer? _rendererFor(Field field, ShadColorScheme colors) {
    if (field.type == FieldType.url.name) {
      return (context) => _urlRenderer(context, colors);
    }
    if (field.type == FieldType.number.name) {
      return (context) => _numberRenderer(context, colors);
    }
    if (field.type == FieldType.date.name) {
      return (context) => _dateRenderer(context, colors);
    }
    return null;
  }

  String? _validateUrl(dynamic value, TrinaValidationContext context) {
    final text = value?.toString() ?? '';
    if (text.isEmpty || isValidUrl(text)) return null;
    return 'Enter a valid URL, e.g. example.com';
  }

  Widget _urlRenderer(
    TrinaColumnRendererContext context,
    ShadColorScheme colors,
  ) {
    final text = context.cell.value?.toString() ?? '';
    if (text.isEmpty) return const SizedBox.shrink();
    // Not every stored value is still a URL - e.g. a field changed
    // from Text to URL keeps its old free-text values (see
    // FieldsRepository.changeType) - flag those instead of rendering
    // them as a clickable link they aren't.
    if (!isValidUrl(text)) {
      return Text(text, style: TextStyle(color: colors.destructive));
    }
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      // GestureDetector rather than InkWell - no Material ancestor is
      // guaranteed inside a TrinaGrid cell.
      child: GestureDetector(
        onTap: () => launchUrl(
          Uri.parse(text.contains('://') ? text : 'https://$text'),
          mode: LaunchMode.externalApplication,
        ),
        child: Text(
          text,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: colors.primary,
            decoration: TextDecoration.underline,
            decorationColor: colors.primary,
          ),
        ),
      ),
    );
  }

  Widget _dateRenderer(
    TrinaColumnRendererContext context,
    ShadColorScheme colors,
  ) {
    final text = context.cell.value?.toString() ?? '';
    if (text.isEmpty) return const SizedBox.shrink();
    // TrinaColumnTypeDate.applyFormat silently returns '' for a value
    // it can't parse, which would hide a stored value that no longer
    // matches the field's type (see FieldsRepository.changeType) -
    // flag it instead.
    if (!isValidDate(text)) {
      return Text(text, style: TextStyle(color: colors.destructive));
    }
    // Custom renderers bypass the grid's cellTextStyle (see
    // TrinaDefaultCell.build), so the foreground color must be set
    // explicitly here too.
    return Text(
      context.column.type.applyFormat(text),
      style: TextStyle(color: colors.foreground),
    );
  }

  Widget _numberRenderer(
    TrinaColumnRendererContext context,
    ShadColorScheme colors,
  ) {
    final value = context.cell.value;
    if (value == null || value.toString().isEmpty) {
      return const SizedBox.shrink();
    }
    // A genuine num (parsed in _cellValue) formats normally; anything
    // else is a stored value that never was a number (e.g. typed as
    // "3a" in the entry's Page-View, which only warns, doesn't block -
    // see PagePropertiesHeader) - flag it rather than silently showing
    // it as 0 (TrinaColumnTypeNumber's own formatting would do that).
    if (value is num) {
      // Same as _dateRenderer: custom renderers bypass cellTextStyle.
      return Text(
        context.column.type.applyFormat(value),
        style: TextStyle(color: colors.foreground),
      );
    }
    return Text(value.toString(), style: TextStyle(color: colors.destructive));
  }

  void _onValidationFailed(
    BuildContext context,
    TrinaGridValidationEvent event,
  ) {
    ShadToaster.of(context).show(
      ShadToast.destructive(
        title: Text('${event.column.title}: ${event.errorMessage}'),
      ),
    );
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
    if (field.type == FieldType.number.name) {
      // applyFormatOnInit off - its default behaviour formats anything
      // it can't parse (an empty cell, or invalid stored text) as "0",
      // which _numberRenderer must be able to tell apart from a real 0.
      return TrinaColumnType.number(applyFormatOnInit: false);
    }
    if (field.type == FieldType.date.name) {
      // format is the sortable yyyy-MM-dd - both stored in properties
      // and shown in the grid; headerFormat stays the picker's default
      // (month/year), unrelated to how the cell itself is displayed.
      // applyFormatOnInit off, same reason as number above - its
      // default behaviour silently formats an unparseable stored
      // value as '', which _dateRenderer must be able to flag instead.
      return TrinaColumnType.date(
        format: _dateFormat,
        applyFormatOnInit: false,
      );
    }
    // url stays plain text - it needs its own validator/renderer
    // (added in _columnsFor) rather than a distinct TrinaColumnType.
    return TrinaColumnType.text();
  }

  String _gridVersion(
    String titleLabel,
    List<Field> fields,
    List<Page> entries,
    Map<String, List<Page>> relatedPagesByCollection,
  ) {
    final fieldPart = fields
        .map((f) => '${f.id}:${f.name}:${f.type}')
        .join(',');
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
  Widget build(BuildContext context) =>
      _build(context, collectionIds, const {});

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
