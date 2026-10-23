// Flutter's own `Page` (Navigator 2.0) collides with our `Page` data class.
import 'package:flutter/material.dart' hide Page;
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:trina_grid/trina_grid.dart';
import 'package:turtle_base/core/app_scope.dart';
import 'package:turtle_base/core/database/app_database.dart';
import 'package:turtle_base/features/files/data/attachments_repository.dart';
import 'package:turtle_base/features/files/widgets/attachment_thumbnail.dart';
import 'package:turtle_base/features/files/widgets/files_field_value.dart';
import 'package:turtle_base/features/pages/data/pages_repository.dart';
import 'package:turtle_base/features/plugins/widgets/entry_lookup_dialog.dart';
import 'package:turtle_base/features/tables/data/base_field_type.dart';
import 'package:turtle_base/features/tables/data/field_type_registry.dart';
import 'package:turtle_base/features/tables/data/relation_field.dart';
import 'package:turtle_base/features/tables/data/resolved_field.dart';
import 'package:turtle_base/features/tables/data/select_field.dart';
import 'package:turtle_base/features/tables/widgets/collection_tiles_view.dart';
import 'package:turtle_base/features/tables/widgets/field_type_picker.dart';
import 'package:turtle_base/features/tables/widgets/select_option_chip.dart';
import 'package:turtle_base/features/tables/widgets/select_option_picker_dialog.dart';
import 'package:turtle_plugin/turtle_plugin.dart';
import 'package:url_launcher/url_launcher.dart';

/// Storage/display format for date fields - also what TrinaGrid's date
/// picker writes back on selection (see TrinaColumnTypeDate).
const _dateFormat = 'yyyy-MM-dd';

/// Grid view of a collection's entries, with inline cell editing for
/// typed-in field types (text, number, date and their variants). Edits
/// are persisted immediately on commit (TrinaGrid's onChanged fires on
/// Enter/Tab/blur, not per keystroke). Invalid values (bad date,
/// malformed URL) are rejected by TrinaGrid's column validation and
/// never reach [_onCellChanged]. Stored values that no longer match a
/// field's type (e.g. after changing it from Text to Number - see
/// FieldsRepository.changeType) are never silently dropped or
/// misrepresented as valid; [_valueRenderer] flags them in red instead.
class CollectionView extends StatefulWidget {
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
  State<CollectionView> createState() => _CollectionViewState();
}

/// How [CollectionView] shows its entries; not persisted.
enum _CollectionLayout {
  table('Table', Icons.table_rows_outlined),
  tiles('Tiles', Icons.grid_view_outlined);

  const _CollectionLayout(this.label, this.icon);

  final String label;
  final IconData icon;
}

class _CollectionViewState extends State<CollectionView> {
  _CollectionLayout _layout = _CollectionLayout.table;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final theme = ShadTheme.of(context);
    return StreamBuilder<Collection>(
      stream: scope.collections.watchById(widget.collectionId),
      builder: (context, collectionSnapshot) {
        final collection = collectionSnapshot.data;
        final titleLabel = collection?.titleFieldLabel ?? 'Name';
        return StreamBuilder<List<Field>>(
          stream: scope.fields.watchAllInCollection(widget.collectionId),
          builder: (context, fieldsSnapshot) {
            final fields = [
              for (final field in fieldsSnapshot.data ?? const <Field>[]) scope.fieldTypes.resolve(field),
            ];
            return StreamBuilder<List<Page>>(
              stream: scope.pages.watchAllInCollection(widget.collectionId),
              builder: (context, entriesSnapshot) {
                final entries = entriesSnapshot.data ?? const <Page>[];
                // Relation cells show the related entries' titles, not
                // their ids - resolve them from whichever collections
                // this collection's relation fields target.
                final relationTargetIds = fields
                    .map((f) => f.config)
                    .whereType<RelationConfig>()
                    .map((c) => c.targetCollectionId)
                    .whereType<String>()
                    .toSet()
                    .toList();
                return _RelatedPagesResolver(
                  scope: scope,
                  collectionIds: relationTargetIds,
                  builder: (context, relatedPagesByCollection) {
                    return LayoutBuilder(
                      builder: (context, constraints) {
                        final narrow = constraints.maxWidth < 600;
                        return Padding(
                          padding: EdgeInsets.fromLTRB(narrow ? 16 : 24, narrow ? 16 : 24, narrow ? 16 : 24, 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (collection != null) _Header(collection: collection, entryCount: entries.length),
                              const SizedBox(height: 16),
                              _Toolbar(
                                layout: _layout,
                                onLayoutChanged: (layout) => setState(() => _layout = layout),
                                onAdd: () => _addRow(scope),
                                onEdit: widget.onEdit,
                                lookup: scope.plugins.templateOf(widget.collectionId)?.lookup,
                                onLookup: (lookup) => showEntryLookup(
                                  context,
                                  collectionId: widget.collectionId,
                                  lookup: lookup,
                                  onOpenEntry: widget.onOpenEntry,
                                ),
                                compact: narrow,
                              ),
                              const SizedBox(height: 16),
                              Expanded(
                                child: _layout == _CollectionLayout.tiles
                                    ? entries.isEmpty
                                          ? const _EmptyState()
                                          : _CoversResolver(
                                              scope: scope,
                                              collectionId: widget.collectionId,
                                              field: fields.where((f) => f.base is FilesFieldType).firstOrNull,
                                              builder: (context, coverFor) => CollectionTilesView(
                                                entries: _sortedByTitle(entries),
                                                secondaryFor: (entry) =>
                                                    _secondaryFor(fields.firstOrNull, entry, relatedPagesByCollection),
                                                coverFor: coverFor,
                                                onOpenEntry: widget.onOpenEntry,
                                              ),
                                            )
                                    // TrinaGrid only reads columns/rows once (see
                                    // its didUpdateWidget), so a Key that changes
                                    // with the data forces a fresh grid instead
                                    // of stale rows.
                                    : TrinaGrid(
                                        key: ValueKey(
                                          _gridVersion(titleLabel, fields, entries, relatedPagesByCollection),
                                        ),
                                        columns: _columnsFor(scope, titleLabel, fields, entries, theme.colorScheme),
                                        rows: _rowsFor(fields, entries, relatedPagesByCollection),
                                        configuration: _gridConfiguration(theme),
                                        onChanged: (event) => _onCellChanged(scope, event),
                                        onRowDoubleTap: (event) => widget.onOpenEntry(event.row.data as String),
                                        onValidationFailed: (event) => _onValidationFailed(context, event),
                                        onLoaded: widget.onLoaded,
                                        noRowsWidget: const _EmptyState(),
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
      },
    );
  }

  /// Tiles are shown alphabetically by title (case-insensitive).
  List<Page> _sortedByTitle(List<Page> entries) =>
      [...entries]..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

  /// The tile's line below the title: the collection's first field
  /// ([field], null if it has none) - select values as chips, the rest
  /// as text via [_cellValue]. Null when the entry has no value for it.
  Widget? _secondaryFor(ResolvedField? field, Page entry, Map<String, List<Page>> relatedPagesByCollection) {
    if (field == null) return null;
    final config = field.config;
    if (config is SelectConfig) {
      final selected = resolveSelectValue(
        config.options,
        field.valueOf(decodePageProperties(entry.properties)[field.id]),
      );
      if (selected.isEmpty) return null;
      return Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [for (final option in selected) SelectOptionChip(option: option)],
      );
    }
    final text = _cellValue(field, entry, relatedPagesByCollection).toString();
    if (text.isEmpty) return null;
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(color: ShadTheme.of(context).colorScheme.mutedForeground),
    );
  }

  /// A blank entry, filled in directly in the grid afterwards - no
  /// separate creation page, matching the inline-editing style already
  /// used for cells and fields.
  Future<void> _addRow(AppScope scope) async {
    final collection = await scope.collections.watchById(widget.collectionId).first;
    await scope.pages.create(spaceId: collection.spaceId, collectionId: widget.collectionId);
  }

  Future<void> _onCellChanged(AppScope scope, TrinaGridOnChangedEvent event) async {
    final entryId = event.row.data as String;
    if (event.column.field == 'title') {
      await scope.pages.rename(entryId, event.value.toString());
    } else {
      final field = scope.fieldTypes.resolve(await scope.fields.watchById(event.column.field).first);
      // The column validator already rejected invalid input.
      if (field.parse(event.value.toString()) case ParsedValue(:final stored)) {
        await scope.pages.setPropertyValue(entryId, field.id, stored);
      }
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
      color: colors.mutedForeground,
      decoration: TextDecoration.none,
      fontSize: 13,
      fontWeight: FontWeight.w500,
    );
    final gridBorderRadius = BorderRadius.circular(8);
    final style = theme.brightness == Brightness.dark
        ? TrinaGridStyleConfig.dark(
            // The grid sits directly on the unified window background
            // (see AppShell/_WideShell - only the sidebar floats as a
            // card).
            gridBackgroundColor: colors.background,
            rowColor: colors.background,
            activatedColor: colors.accent,
            activatedBorderColor: colors.ring,
            inactivatedBorderColor: colors.border,
            gridBorderColor: colors.border,
            borderColor: colors.border,
            cellTextStyle: cellTextStyle,
            columnTextStyle: columnTextStyle,
            iconColor: colors.mutedForeground,
            menuBackgroundColor: colors.popover,
            cellColorInEditState: colors.background,
            cellColorInReadOnlyState: colors.muted,
            gridBorderRadius: gridBorderRadius,
            rowHeight: 44,
            columnHeight: 40,
            iconSize: 16,
            columnContextIcon: Icons.more_horiz,
            enableRowHoverColor: true,
            rowHoveredColor: colors.muted.withValues(alpha: 0.5),
            defaultColumnTitlePadding: const EdgeInsets.symmetric(horizontal: 12),
            defaultCellPadding: const EdgeInsets.symmetric(horizontal: 12),
          )
        : TrinaGridStyleConfig(
            // background, not card - same reason as the dark branch.
            gridBackgroundColor: colors.background,
            rowColor: colors.background,
            activatedColor: colors.accent,
            activatedBorderColor: colors.ring,
            inactivatedBorderColor: colors.border,
            gridBorderColor: colors.border,
            borderColor: colors.border,
            cellTextStyle: cellTextStyle,
            columnTextStyle: columnTextStyle,
            iconColor: colors.mutedForeground,
            menuBackgroundColor: colors.popover,
            cellColorInEditState: colors.background,
            cellColorInReadOnlyState: colors.muted,
            gridBorderRadius: gridBorderRadius,
            rowHeight: 44,
            columnHeight: 40,
            iconSize: 16,
            columnContextIcon: Icons.more_horiz,
            enableRowHoverColor: true,
            rowHoveredColor: colors.muted.withValues(alpha: 0.5),
            defaultColumnTitlePadding: const EdgeInsets.symmetric(horizontal: 12),
            defaultCellPadding: const EdgeInsets.symmetric(horizontal: 12),
          );
    return TrinaGridConfiguration(style: style);
  }

  List<TrinaColumn> _columnsFor(
    AppScope scope,
    String titleLabel,
    List<ResolvedField> fields,
    List<Page> entries,
    ShadColorScheme colors,
  ) {
    final entriesById = {for (final entry in entries) entry.id: entry};
    return [
      // Not editable via "Manage fields" - it's the built-in title,
      // not a user-defined field. Its label is customizable per
      // collection (CollectionEditPage) though, unlike the column
      // itself.
      TrinaColumn(
        title: titleLabel,
        titleSpan: _columnTitle(titleLabel, Icons.title, colors),
        backgroundColor: _headerColor(colors),
        field: 'title',
        type: TrinaColumnType.text(),
        width: 240,
      ),
      for (final field in fields)
        TrinaColumn(
          title: field.name,
          titleSpan: _columnTitle(field.name, fieldTypeIcon(FieldTypeChoice(field.base, field.variant)), colors),
          backgroundColor: _headerColor(colors),
          width: _columnWidthFor(field),
          field: field.id,
          type: _columnTypeFor(field),
          // Relations are edited via a picker in the entry's Page-View
          // (see PagePropertiesHeader), not inline in the grid. Select
          // values via the option picker, opened by tapping the cell
          // (see _selectRenderer) instead of the grid's text editor.
          readOnly: !_isTypedIn(field),
          validator: _isTypedIn(field) ? (value, _) => _validate(field, value) : null,
          renderer: _rendererFor(scope, field, entriesById, colors),
        ),
    ];
  }

  /// Whether the field is edited by typing into the cell, rather than
  /// via a picker (select, relation) or not at all.
  bool _isTypedIn(ResolvedField field) => switch (field.base) {
    TextFieldType() || NumberFieldType() || DateFieldType() || LocationFieldType() => true,
    CheckboxFieldType() ||
    SelectFieldType() ||
    RelationFieldType() ||
    FilesFieldType() ||
    UnsupportedFieldType() => false,
  };

  String? _validate(ResolvedField field, dynamic value) => switch (field.parse(value?.toString() ?? '')) {
    ParseError(:final message) => message,
    ParsedValue() => null,
  };

  /// Set apart from the rows, like the field editor's settings panels.
  Color _headerColor(ShadColorScheme colors) => colors.muted.withValues(alpha: 0.6);

  /// The field's type icon before its name, as in the field editor.
  InlineSpan _columnTitle(String title, IconData icon, ShadColorScheme colors) {
    return TextSpan(
      children: [
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Icon(icon, size: 15, color: colors.mutedForeground),
          ),
        ),
        TextSpan(text: title),
      ],
    );
  }

  /// Narrower columns for values that are short by nature.
  double _columnWidthFor(ResolvedField field) => switch (field.base) {
    CheckboxFieldType() => 120,
    NumberFieldType() || DateFieldType() => 150,
    _ => 200,
  };

  /// [colors] is passed in because [TrinaColumnRendererContext] carries
  /// no BuildContext to resolve the theme from inside a renderer.
  TrinaColumnRenderer? _rendererFor(
    AppScope scope,
    ResolvedField field,
    Map<String, Page> entriesById,
    ShadColorScheme colors,
  ) {
    if (field.base is SelectFieldType) {
      return (context) => _selectRenderer(context, scope, field, entriesById);
    }
    if (field.base is CheckboxFieldType) {
      return (context) => _checkboxRenderer(context, scope, field, entriesById);
    }
    if (field.base is RelationFieldType) return null;
    if (field.base is FilesFieldType) {
      return (context) => Align(
        alignment: Alignment.centerLeft,
        child: AttachmentStrip(pageId: context.row.data as String, fieldId: field.id),
      );
    }
    return (context) => _valueRenderer(context, field, entriesById, colors);
  }

  /// Renders from the entry's stored value rather than the cell's, which
  /// is only there for the grid's sorting and editing (see _cellValue).
  /// Custom renderers bypass the grid's cellTextStyle (see
  /// TrinaDefaultCell.build), so colors are set explicitly.
  Widget _valueRenderer(
    TrinaColumnRendererContext context,
    ResolvedField field,
    Map<String, Page> entriesById,
    ShadColorScheme colors,
  ) {
    final entry = entriesById[context.row.data as String];
    final raw = entry == null ? null : decodePageProperties(entry.properties)[field.id];
    final text = field.display(raw);
    if (text.isEmpty) return const SizedBox.shrink();
    // Not every stored value still matches the field's type - e.g. a
    // field changed from Text to URL keeps its old free-text values (see
    // FieldsRepository.changeType) - flag those instead of rendering
    // them as valid.
    if (field.errorFor(raw) != null) {
      return Text(
        text,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: colors.destructive),
      );
    }
    final link = field.linkFor(raw);
    if (link == null) {
      return Text(
        text,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: colors.foreground),
      );
    }
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      // GestureDetector rather than InkWell - no Material ancestor is
      // guaranteed inside a TrinaGrid cell.
      child: GestureDetector(
        onTap: () => launchUrl(link, mode: LaunchMode.externalApplication),
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

  /// Toggled right in the grid - a checkbox needs no editor.
  Widget _checkboxRenderer(
    TrinaColumnRendererContext context,
    AppScope scope,
    ResolvedField field,
    Map<String, Page> entriesById,
  ) {
    final entryId = context.row.data as String;
    final entry = entriesById[entryId];
    final raw = entry == null ? null : decodePageProperties(entry.properties)[field.id];
    final checked = field.valueOf(raw) == true;
    return Align(
      alignment: Alignment.centerLeft,
      child: ShadCheckbox(
        value: checked,
        onChanged: (value) => scope.pages.setPropertyValue(entryId, field.id, field.base.encode(value, field.config)),
      ),
    );
  }

  /// The cell's value holds the options' names (see _cellValue, for
  /// sorting/filtering), so the chips are resolved from the entry's raw
  /// option ids instead - looked up via the row's entry id.
  Widget _selectRenderer(
    TrinaColumnRendererContext context,
    AppScope scope,
    ResolvedField field,
    Map<String, Page> entriesById,
  ) {
    final entryId = context.row.data as String;
    final entry = entriesById[entryId];
    final raw = entry == null ? null : decodePageProperties(entry.properties)[field.id];
    final selected = resolveSelectValue((field.config as SelectConfig).options, field.valueOf(raw));
    final selectedIds = [for (final option in selected) option.id];
    // Builder for a BuildContext to open the dialog from -
    // TrinaColumnRendererContext carries none.
    return Builder(
      builder: (buildContext) => MouseRegion(
        cursor: SystemMouseCursors.click,
        // GestureDetector rather than InkWell, same as _valueRenderer.
        // Opaque, so an empty cell is tappable too.
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () async {
            final result = await showSelectOptionPicker(
              buildContext,
              scope: scope,
              field: field.row,
              selectedIds: selectedIds,
            );
            if (result == null) return;
            await scope.pages.setPropertyValue(entryId, field.id, field.base.encode(result, field.config));
          },
          // Clipped instead of wrapped - a grid row has a fixed height,
          // so chips that don't fit are cut off at the cell's edge.
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.centerLeft,
              maxWidth: double.infinity,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final option in selected)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: SelectOptionChip(option: option),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _onValidationFailed(BuildContext context, TrinaGridValidationEvent event) {
    ShadToaster.of(context).show(ShadToast.destructive(title: Text('${event.column.title}: ${event.errorMessage}')));
  }

  List<TrinaRow> _rowsFor(
    List<ResolvedField> fields,
    List<Page> entries,
    Map<String, List<Page>> relatedPagesByCollection,
  ) {
    return [
      for (final entry in entries)
        TrinaRow(
          data: entry.id,
          cells: {
            'title': TrinaCell(value: entry.title),
            for (final field in fields) field.id: TrinaCell(value: _cellValue(field, entry, relatedPagesByCollection)),
          },
        ),
    ];
  }

  /// What the grid sorts, filters and edits - renderers show the
  /// stored value themselves (see _valueRenderer).
  Object _cellValue(ResolvedField field, Page entry, Map<String, List<Page>> relatedPagesByCollection) {
    final raw = decodePageProperties(entry.properties)[field.id];
    final config = field.config;
    if (config is RelationConfig) {
      final targetPages = relatedPagesByCollection[config.targetCollectionId] ?? const <Page>[];
      final titles = [for (final id in decodeRelationValue(raw)) _titleOf(targetPages, id)];
      return titles.join(', ');
    }
    // A genuine num, so the number column sorts numerically.
    if (field.base is NumberFieldType && field.errorFor(raw) == null) {
      return field.valueOf(raw) ?? '';
    }
    return field.display(raw);
  }

  String _titleOf(List<Page> pages, String id) {
    for (final page in pages) {
      if (page.id == id) return page.title.isEmpty ? 'Untitled' : page.title;
    }
    return '?';
  }

  TrinaColumnType _columnTypeFor(ResolvedField field) {
    return switch (field.base) {
      // applyFormatOnInit off - its default behaviour formats anything it
      // can't parse (an empty cell, or invalid stored text) as "0".
      NumberFieldType() => TrinaColumnType.number(applyFormatOnInit: false),
      // format is the sortable yyyy-MM-dd - both stored in properties
      // and shown in the grid; headerFormat stays the picker's default
      // (month/year), unrelated to how the cell itself is displayed.
      // applyFormatOnInit off, same reason as number above.
      DateFieldType() => TrinaColumnType.date(format: _dateFormat, applyFormatOnInit: false),
      _ => TrinaColumnType.text(),
    };
  }

  String _gridVersion(
    String titleLabel,
    List<ResolvedField> fields,
    List<Page> entries,
    Map<String, List<Page>> relatedPagesByCollection,
  ) {
    final fieldPart = fields
        .map((f) => f.row)
        // config included so renaming/recoloring a select option (or
        // retargeting a relation) refreshes the grid too.
        .map((f) => '${f.id}:${f.name}:${f.type}:${f.config}')
        .join(',');
    final entryPart = entries.map((e) => '${e.id}:${e.updatedAt.millisecondsSinceEpoch}').join(',');
    // Included so renaming a related entry elsewhere refreshes the
    // resolved titles shown here too (TrinaGrid only reads rows once).
    final relatedPart = relatedPagesByCollection.values
        .expand((pages) => pages)
        .map((p) => '${p.id}:${p.updatedAt.millisecondsSinceEpoch}')
        .join(',');
    return '$titleLabel|$fieldPart|$entryPart|$relatedPart';
  }
}

/// Shown instead of rows or tiles while the collection has no entries.
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined, size: 36, color: theme.colorScheme.mutedForeground),
            const SizedBox(height: 12),
            Text('No entries yet', style: theme.textTheme.large),
            const SizedBox(height: 4),
            Text('Use "New entry" to add the first one.', style: theme.textTheme.muted, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.collection, required this.entryCount});

  final Collection collection;
  final int entryCount;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Row(
      children: [
        if (collection.icon != null) ...[
          Text(collection.icon!, style: const TextStyle(fontSize: 32)),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(collection.name, style: theme.textTheme.h2, maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(entryCount == 1 ? '1 entry' : '$entryCount entries', style: theme.textTheme.muted),
            ],
          ),
        ),
      ],
    );
  }
}

/// The layout switch on the left, actions on the right - icon-only
/// actions when [compact], so all fits one line on a phone. With a
/// plugin's [lookup], adding through it is the main action and a blank
/// entry the secondary one.
class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.layout,
    required this.onLayoutChanged,
    required this.onAdd,
    required this.onEdit,
    required this.lookup,
    required this.onLookup,
    required this.compact,
  });

  final _CollectionLayout layout;
  final ValueChanged<_CollectionLayout> onLayoutChanged;
  final VoidCallback onAdd;
  final VoidCallback onEdit;
  final EntryLookup? lookup;
  final ValueChanged<EntryLookup> onLookup;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _LayoutToggle(value: layout, onChanged: onLayoutChanged, compact: compact),
        const Spacer(),
        if (compact)
          Tooltip(
            message: 'Edit collection',
            child: ShadIconButton.ghost(icon: const Icon(Icons.tune, size: 18), onPressed: onEdit),
          )
        else
          ShadButton.ghost(
            leading: const Icon(Icons.tune, size: 16),
            onPressed: onEdit,
            child: const Text('Edit collection'),
          ),
        const SizedBox(width: 8),
        if (lookup case final lookup?) ...[
          if (compact)
            Tooltip(
              message: 'New entry',
              child: ShadIconButton.ghost(icon: const Icon(Icons.add, size: 18), onPressed: onAdd),
            )
          else
            ShadButton.ghost(
              leading: const Icon(Icons.add, size: 16),
              onPressed: onAdd,
              child: const Text('New entry'),
            ),
          const SizedBox(width: 8),
          ShadButton(
            leading: const Icon(Icons.search, size: 16),
            onPressed: () => onLookup(lookup),
            child: Text(lookup.actionLabel),
          ),
        ] else
          ShadButton(leading: const Icon(Icons.add, size: 16), onPressed: onAdd, child: const Text('New entry')),
      ],
    );
  }
}

/// A segmented control - both layouts in view, the current one raised.
class _LayoutToggle extends StatelessWidget {
  const _LayoutToggle({required this.value, required this.onChanged, required this.compact});

  final _CollectionLayout value;
  final ValueChanged<_CollectionLayout> onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = ShadTheme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: colors.muted, borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final layout in _CollectionLayout.values)
            Tooltip(
              message: layout.label,
              child: Semantics(
                selected: layout == value,
                button: true,
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () => onChanged(layout),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: layout == value ? colors.background : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                        boxShadow: layout == value
                            ? [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.08),
                                  blurRadius: 2,
                                  offset: const Offset(0, 1),
                                ),
                              ]
                            : null,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            layout.icon,
                            size: 16,
                            color: layout == value ? colors.foreground : colors.mutedForeground,
                          ),
                          if (!compact) ...[
                            const SizedBox(width: 6),
                            Text(
                              layout.label,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: layout == value ? colors.foreground : colors.mutedForeground,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Resolves [collectionIds] to their entries, nesting one StreamBuilder
/// per id - not meant for large numbers of collections, but a
/// collection's relation fields are expected to target only a few.
class _RelatedPagesResolver extends StatelessWidget {
  const _RelatedPagesResolver({required this.scope, required this.collectionIds, required this.builder});

  final AppScope scope;
  final List<String> collectionIds;
  final Widget Function(BuildContext, Map<String, List<Page>>) builder;

  @override
  Widget build(BuildContext context) => _build(context, collectionIds, const {});

  Widget _build(BuildContext context, List<String> remaining, Map<String, List<Page>> resolved) {
    if (remaining.isEmpty) return builder(context, resolved);
    final collectionId = remaining.first;
    return StreamBuilder<List<Page>>(
      stream: scope.pages.watchAllInCollection(collectionId),
      builder: (context, snapshot) {
        return _build(context, remaining.sublist(1), {...resolved, collectionId: snapshot.data ?? const <Page>[]});
      },
    );
  }
}

/// Tile covers from the collection's first files field ([field], null
/// if it has none): each entry's first image there.
class _CoversResolver extends StatelessWidget {
  const _CoversResolver({required this.scope, required this.collectionId, required this.field, required this.builder});

  final AppScope scope;
  final String collectionId;
  final ResolvedField? field;
  final Widget Function(BuildContext context, Widget? Function(Page entry)? coverFor) builder;

  @override
  Widget build(BuildContext context) {
    final field = this.field;
    if (field == null) return builder(context, null);
    final placeholder = ColoredBox(color: ShadTheme.of(context).colorScheme.muted);
    return StreamBuilder<Map<String, List<Attachment>>>(
      stream: scope.attachments.watchInFieldOfCollection(collectionId, field.id),
      builder: (context, snapshot) {
        final byPage = snapshot.data ?? const <String, List<Attachment>>{};
        return builder(context, (entry) {
          final image = byPage[entry.id]?.where((a) => a.isImage).firstOrNull;
          return image == null ? placeholder : AttachmentCover(attachment: image);
        });
      },
    );
  }
}
