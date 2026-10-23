import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:turtle_base/core/app_scope.dart';
import 'package:turtle_base/core/database/app_database.dart';
import 'package:turtle_base/features/tables/data/base_field_type.dart';
import 'package:turtle_base/features/tables/data/field_conversion.dart';
import 'package:turtle_base/features/tables/data/field_type_registry.dart';
import 'package:turtle_base/features/tables/data/fields_repository.dart';
import 'package:turtle_base/features/tables/data/relation_field.dart';
import 'package:turtle_base/features/tables/data/resolved_field.dart';
import 'package:turtle_base/features/tables/data/select_field.dart';
import 'package:turtle_base/features/tables/widgets/field_config_editor.dart';
import 'package:turtle_base/features/tables/widgets/field_type_picker.dart';
import 'package:turtle_base/features/tables/widgets/select_options_editor.dart';
import 'package:turtle_base/features/tables/widgets/type_change_dialog.dart';

/// Below this width a field's row puts its type picker on a line of
/// its own, so the name keeps room to type in.
const _narrowWidth = 480.0;

/// The "Fields" part of CollectionEditPage: one compact, draggable row
/// per field, whose type-specific settings fold out below it, plus a
/// row to add a field.
class FieldsEditor extends StatefulWidget {
  const FieldsEditor({super.key, required this.collectionId, required this.spaceId});

  final String collectionId;

  /// The relation type's target picker offers this space's collections.
  final String spaceId;

  @override
  State<FieldsEditor> createState() => _FieldsEditorState();
}

class _FieldsEditorState extends State<FieldsEditor> {
  final _nameControllers = <String, TextEditingController>{};
  final _focusNodes = <String, FocusNode>{};
  final _expanded = <String>{};

  /// The order of a drag just dropped, shown until the database's
  /// stream catches up - otherwise the row jumps back for a frame.
  List<String>? _pendingOrder;

  @override
  void dispose() {
    for (final controller in _nameControllers.values) {
      controller.dispose();
    }
    for (final focusNode in _focusNodes.values) {
      focusNode.dispose();
    }
    super.dispose();
  }

  TextEditingController _nameControllerFor(Field field) {
    return _nameControllers[field.id] ??= TextEditingController(text: field.name);
  }

  FocusNode _focusNodeFor(Field field, FieldsRepository fields) {
    final existing = _focusNodes[field.id];
    if (existing != null) return existing;
    final focusNode = FocusNode();
    focusNode.addListener(() {
      if (!focusNode.hasFocus) _rename(fields, field.id, _nameControllerFor(field).text);
    });
    return _focusNodes[field.id] = focusNode;
  }

  void _rename(FieldsRepository fields, String id, String value) {
    final trimmed = value.trim();
    if (trimmed.isNotEmpty) fields.rename(id, trimmed);
  }

  /// Drops controllers/focus nodes of fields that no longer exist.
  void _prune(List<Field> fields) {
    final ids = {for (final field in fields) field.id};
    _nameControllers.removeWhere((id, controller) {
      if (!ids.contains(id)) controller.dispose();
      return !ids.contains(id);
    });
    _focusNodes.removeWhere((id, focusNode) {
      if (!ids.contains(id)) focusNode.dispose();
      return !ids.contains(id);
    });
    _expanded.removeWhere((id) => !ids.contains(id));
  }

  List<Field> _ordered(List<Field> fields) {
    final pending = _pendingOrder;
    if (pending == null) return fields;
    if (fields.map((f) => f.id).join() == pending.join()) {
      _pendingOrder = null;
      return fields;
    }
    final byId = {for (final field in fields) field.id: field};
    return [for (final id in pending) ?byId[id], ...fields.where((f) => !pending.contains(f.id))];
  }

  void _onReorder(FieldsRepository repository, List<Field> fields, int oldIndex, int newIndex) {
    final ids = [for (final field in fields) field.id];
    ids.insert(newIndex, ids.removeAt(oldIndex));
    setState(() => _pendingOrder = ids);
    repository.reorderAll(ids);
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return StreamBuilder<List<Collection>>(
      stream: scope.collections.watchAllInSpace(widget.spaceId),
      builder: (context, collectionsSnapshot) {
        final collections = collectionsSnapshot.data ?? const <Collection>[];
        return StreamBuilder<List<Field>>(
          stream: scope.fields.watchAllInCollection(widget.collectionId),
          builder: (context, fieldsSnapshot) {
            final rows = fieldsSnapshot.data ?? const <Field>[];
            _prune(rows);
            final fields = _ordered(rows);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (fields.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'No fields yet - add one below to give each entry more than a name.',
                      style: ShadTheme.of(context).textTheme.muted,
                    ),
                  ),
                ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  itemCount: fields.length,
                  onReorderItem: (oldIndex, newIndex) => _onReorder(scope.fields, fields, oldIndex, newIndex),
                  proxyDecorator: (child, index, animation) => Material(
                    elevation: 4,
                    color: ShadTheme.of(context).colorScheme.card,
                    borderRadius: BorderRadius.circular(8),
                    child: child,
                  ),
                  itemBuilder: (context, index) {
                    final field = fields[index];
                    return _FieldTile(
                      key: ValueKey(field.id),
                      index: index,
                      field: scope.fieldTypes.resolve(field),
                      choices: scope.fieldTypes.choices,
                      nameController: _nameControllerFor(field),
                      focusNode: _focusNodeFor(field, scope.fields),
                      fields: scope.fields,
                      collections: collections,
                      expanded: _expanded.contains(field.id),
                      onExpandedChanged: (expanded) => setState(() {
                        expanded ? _expanded.add(field.id) : _expanded.remove(field.id);
                      }),
                    );
                  },
                ),
                const SizedBox(height: 8),
                _AddFieldRow(
                  choices: scope.fieldTypes.choices,
                  collections: collections,
                  fields: scope.fields,
                  collectionId: widget.collectionId,
                  // Straight to the new field's settings, e.g. to add a
                  // select's options.
                  onAdded: (id, hasSettings) {
                    if (hasSettings) setState(() => _expanded.add(id));
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }
}

/// Whether [field] has settings to fold out - see fieldConfigEditorFor
/// for why variants have none.
bool _hasSettings(ResolvedField field) {
  if (field.variant != null) return false;
  return switch (field.base) {
    TextFieldType() || NumberFieldType() || SelectFieldType() || RelationFieldType() => true,
    DateFieldType() || CheckboxFieldType() || LocationFieldType() || UnsupportedFieldType() => false,
  };
}

class _FieldTile extends StatefulWidget {
  const _FieldTile({
    super.key,
    required this.index,
    required this.field,
    required this.choices,
    required this.nameController,
    required this.focusNode,
    required this.fields,
    required this.collections,
    required this.expanded,
    required this.onExpandedChanged,
  });

  /// Position in the ReorderableListView, for the drag handle.
  final int index;
  final ResolvedField field;
  final List<FieldTypeChoice> choices;
  final TextEditingController nameController;
  final FocusNode focusNode;
  final FieldsRepository fields;
  final List<Collection> collections;
  final bool expanded;
  final ValueChanged<bool> onExpandedChanged;

  @override
  State<_FieldTile> createState() => _FieldTileState();
}

class _FieldTileState extends State<_FieldTile> {
  /// Bumped to reset the type picker after a cancelled change - it
  /// already shows the picked type, and nothing in the database changed
  /// to rebuild it.
  int _typePickerGeneration = 0;

  Future<void> _changeType(FieldTypeChoice choice) async {
    final plan = await widget.fields.planTypeChange(widget.field.id, choice);
    if (!mounted) return;
    if (needsTypeChangeConfirmation(plan) && !await confirmTypeChange(context, plan: plan, typeLabel: choice.label)) {
      setState(() => _typePickerGeneration++);
      return;
    }
    await widget.fields.applyTypeChange(plan);
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final field = widget.field;
    final current = FieldTypeChoice(field.base, field.variant);
    final hasSettings = _hasSettings(field);
    final missingTarget = field.config is RelationConfig && (field.config as RelationConfig).targetCollectionId == null;
    final expanded = hasSettings && (widget.expanded || missingTarget);

    final dragHandle = ReorderableDragStartListener(
      index: widget.index,
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Icon(Icons.drag_indicator, size: 18, color: theme.colorScheme.mutedForeground),
        ),
      ),
    );
    final name = ShadInput(
      controller: widget.nameController,
      focusNode: widget.focusNode,
      leading: Icon(fieldTypeIcon(current), size: 16, color: theme.colorScheme.mutedForeground),
      onSubmitted: (value) {
        final trimmed = value.trim();
        if (trimmed.isNotEmpty) widget.fields.rename(field.id, trimmed);
      },
    );
    final typePicker = FieldTypePicker(
      key: ValueKey(_typePickerGeneration),
      value: current,
      choices: [
        for (final choice in widget.choices)
          if (choice == current || conversionMode(field.base, choice.base) != ConversionMode.none) choice,
      ],
      onChanged: _changeType,
    );
    final actions = [
      // Kept in the layout when hidden, so the type pickers of all rows
      // line up.
      Visibility(
        visible: hasSettings,
        maintainSize: true,
        maintainAnimation: true,
        maintainState: true,
        child: Tooltip(
          message: expanded ? 'Hide field settings' : 'Field settings',
          child: ShadIconButton.ghost(
            icon: Icon(Icons.tune, size: 18, color: expanded ? theme.colorScheme.foreground : null),
            onPressed: () => widget.onExpandedChanged(!widget.expanded),
          ),
        ),
      ),
      Tooltip(
        message: 'Delete field',
        child: ShadIconButton.ghost(
          icon: const Icon(Icons.delete_outline, size: 18),
          onPressed: () => widget.fields.softDelete(field.id),
        ),
      ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= _narrowWidth) {
                return Row(
                  children: [
                    dragHandle,
                    Expanded(child: name),
                    const SizedBox(width: 8),
                    typePicker,
                    ...actions,
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      dragHandle,
                      Expanded(child: name),
                      ...actions,
                    ],
                  ),
                  Padding(padding: const EdgeInsets.only(left: 26, top: 4), child: typePicker),
                ],
              );
            },
          ),
          if (expanded)
            Container(
              margin: const EdgeInsets.only(left: 26, top: 8, bottom: 4),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.muted.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: _FieldSettings(field: field, fields: widget.fields, collections: widget.collections),
            ),
        ],
      ),
    );
  }
}

class _FieldSettings extends StatelessWidget {
  const _FieldSettings({required this.field, required this.fields, required this.collections});

  final ResolvedField field;
  final FieldsRepository fields;
  final List<Collection> collections;

  @override
  Widget build(BuildContext context) {
    final config = field.config;
    if (config is SelectConfig) {
      return SelectOptionsEditor(key: ValueKey('options-${field.id}'), field: field.row, fields: fields);
    }
    if (config is RelationConfig) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Related collection', style: ShadTheme.of(context).textTheme.small),
          const SizedBox(height: 6),
          _RelationTargetSelect(
            value: config.targetCollectionId,
            collections: collections,
            onChanged: (id) => fields.updateConfig(field.id, encodeRelationConfig(id)),
          ),
        ],
      );
    }
    return fieldConfigEditorFor(field, fields) ?? const SizedBox.shrink();
  }
}

class _RelationTargetSelect extends StatelessWidget {
  const _RelationTargetSelect({required this.value, required this.collections, required this.onChanged});

  final String? value;
  final List<Collection> collections;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return ShadSelect<String>(
      minWidth: 170,
      initialValue: value,
      placeholder: const Text('Relates to...'),
      selectedOptionBuilder: (context, id) =>
          Text(collections.where((c) => c.id == id).firstOrNull?.name ?? 'Deleted collection'),
      options: [for (final collection in collections) ShadOption(value: collection.id, child: Text(collection.name))],
      onChanged: (id) {
        if (id != null) onChanged(id);
      },
    );
  }
}

class _AddFieldRow extends StatefulWidget {
  const _AddFieldRow({
    required this.choices,
    required this.collections,
    required this.fields,
    required this.collectionId,
    required this.onAdded,
  });

  final List<FieldTypeChoice> choices;
  final List<Collection> collections;
  final FieldsRepository fields;
  final String collectionId;

  /// Called with the new field's id and whether it has settings.
  final void Function(String id, bool hasSettings) onAdded;

  @override
  State<_AddFieldRow> createState() => _AddFieldRowState();
}

class _AddFieldRowState extends State<_AddFieldRow> {
  final _nameController = TextEditingController();
  FieldTypeChoice _type = const FieldTypeChoice(BaseFieldType.text);
  String? _relationTargetId;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  /// A relation field is useless without a target - adding is blocked
  /// until one's picked, rather than creating a half-configured field.
  bool get _canAdd => _type.base is! RelationFieldType || _relationTargetId != null;

  Future<void> _add() async {
    final name = _nameController.text.trim();
    if (name.isEmpty || !_canAdd) return;
    final type = _type;
    final id = await widget.fields.create(
      collectionId: widget.collectionId,
      name: name,
      type: type.base,
      variant: type.variant,
      config: switch (type.base) {
        RelationFieldType() => encodeRelationConfig(_relationTargetId!),
        // Usable right away - options are added afterwards, in the
        // field's settings or from the option picker.
        SelectFieldType() => encodeSelectConfig(const []),
        _ => null,
      },
    );
    _nameController.clear();
    setState(() {
      _type = const FieldTypeChoice(BaseFieldType.text);
      _relationTargetId = null;
    });
    widget.onAdded(id, type.variant == null && type.base is SelectFieldType);
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final name = ShadInput(
      controller: _nameController,
      placeholder: const Text('New field name'),
      leading: Icon(Icons.add, size: 16, color: theme.colorScheme.mutedForeground),
      onSubmitted: (_) => _add(),
    );
    final typePicker = FieldTypePicker(
      value: _type,
      choices: [
        for (final choice in widget.choices)
          if (choice.base is! UnsupportedFieldType) choice,
      ],
      onChanged: (type) => setState(() => _type = type),
    );
    final target = _type.base is RelationFieldType
        ? _RelationTargetSelect(
            value: _relationTargetId,
            collections: widget.collections,
            onChanged: (id) => setState(() => _relationTargetId = id),
          )
        : null;
    final addButton = ShadButton.secondary(onPressed: _canAdd ? _add : null, child: const Text('Add field'));

    return Container(
      padding: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: theme.colorScheme.border)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= _narrowWidth) {
            return Row(
              children: [
                const SizedBox(width: 26),
                Expanded(child: name),
                const SizedBox(width: 8),
                typePicker,
                if (target != null) ...[const SizedBox(width: 8), target],
                const SizedBox(width: 8),
                addButton,
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              name,
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [typePicker, ?target, addButton]),
            ],
          );
        },
      ),
    );
  }
}
