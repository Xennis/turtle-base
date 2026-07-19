import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:turtle_base/core/app_scope.dart';
import 'package:turtle_base/core/database/app_database.dart';
import 'package:turtle_base/features/shell/widgets/confirm_dialog.dart';
import 'package:turtle_base/features/tables/data/field_type.dart';
import 'package:turtle_base/features/tables/data/fields_repository.dart';
import 'package:turtle_base/features/tables/data/relation_field.dart';

/// Shown in the same content area as CollectionView (see
/// AppShell/_MainContent) rather than pushed via Navigator, so the
/// sidebar stays visible. [onDone] goes back to the grid.
class CollectionEditPage extends StatefulWidget {
  const CollectionEditPage({
    super.key,
    required this.collectionId,
    required this.onDone,
    required this.onDeleted,
  });

  final String collectionId;
  final VoidCallback onDone;

  /// Called after the collection itself is deleted - unlike [onDone],
  /// there's no grid left to go back to.
  final VoidCallback onDeleted;

  @override
  State<CollectionEditPage> createState() => _CollectionEditPageState();
}

class _CollectionEditPageState extends State<CollectionEditPage> {
  TextEditingController? _nameController;
  FocusNode? _nameFocusNode;
  TextEditingController? _titleFieldLabelController;
  FocusNode? _titleFieldLabelFocusNode;
  final _newFieldNameController = TextEditingController();
  FieldType _newFieldType = FieldType.text;
  String? _newFieldRelationTargetId;
  final _fieldNameControllers = <String, TextEditingController>{};
  final _fieldFocusNodes = <String, FocusNode>{};

  @override
  void dispose() {
    _nameController?.dispose();
    _nameFocusNode?.dispose();
    _titleFieldLabelController?.dispose();
    _titleFieldLabelFocusNode?.dispose();
    _newFieldNameController.dispose();
    for (final controller in _fieldNameControllers.values) {
      controller.dispose();
    }
    for (final focusNode in _fieldFocusNodes.values) {
      focusNode.dispose();
    }
    super.dispose();
  }

  void _saveName(String value, Future<void> Function(String) save) {
    final trimmed = value.trim();
    if (trimmed.isNotEmpty) save(trimmed);
  }

  /// Unlike _saveName, an empty value is valid here - it resets to the
  /// "Name" default instead of being ignored.
  void _saveTitleFieldLabel(String value) {
    final scope = AppScope.of(context);
    final trimmed = value.trim();
    scope.collections.setTitleFieldLabel(
      widget.collectionId,
      trimmed.isEmpty ? null : trimmed,
    );
  }

  Future<void> _pickIcon(BuildContext context) async {
    final scope = AppScope.of(context);
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => SizedBox(
        height: 320,
        child: EmojiPicker(
          onEmojiSelected: (category, emoji) {
            scope.collections.setIcon(widget.collectionId, emoji.emoji);
            Navigator.of(context).pop();
          },
        ),
      ),
    );
  }

  TextEditingController _fieldNameControllerFor(Field field) {
    return _fieldNameControllers[field.id] ??= TextEditingController(
      text: field.name,
    );
  }

  FocusNode _fieldFocusNodeFor(Field field, FieldsRepository fields) {
    final existing = _fieldFocusNodes[field.id];
    if (existing != null) return existing;
    final focusNode = FocusNode();
    focusNode.addListener(() {
      if (!focusNode.hasFocus) {
        _saveName(
          _fieldNameControllerFor(field).text,
          (name) => fields.rename(field.id, name),
        );
      }
    });
    _fieldFocusNodes[field.id] = focusNode;
    return focusNode;
  }

  Future<void> _addField(FieldsRepository fields) async {
    final name = _newFieldNameController.text.trim();
    if (name.isEmpty) return;
    // A relation field needs a target collection to be usable - the
    // "Add" button is disabled until one is picked, see build().
    if (_newFieldType == FieldType.relation && _newFieldRelationTargetId == null) {
      return;
    }
    await fields.create(
      collectionId: widget.collectionId,
      name: name,
      type: _newFieldType,
      config: _newFieldType == FieldType.relation
          ? encodeRelationConfig(_newFieldRelationTargetId!)
          : null,
    );
    _newFieldNameController.clear();
    setState(() {
      _newFieldType = FieldType.text;
      _newFieldRelationTargetId = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return Scaffold(
      // Transparent so the floating content panel's card color shows
      // through on the wide layout (see AppShell/_WideShell); on the
      // narrow layout the ancestor Scaffold provides the background.
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: ShadIconButton.ghost(
          icon: const Icon(Icons.arrow_back),
          onPressed: widget.onDone,
        ),
        title: const Text('Edit collection'),
        actions: [
          Tooltip(
            // Distinct from the sidebar row's "Delete collection" -
            // both can be visible at once (sidebar stays visible while
            // editing a collection, see AppShell/_MainContent).
            message: 'Delete this collection',
            child: ShadIconButton.ghost(
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                final confirmed = await confirmDelete(
                  context,
                  title: 'Delete this collection?',
                );
                if (!confirmed) return;
                await scope.collections.softDelete(widget.collectionId);
                widget.onDeleted();
              },
            ),
          ),
        ],
      ),
      body: StreamBuilder<Collection>(
        stream: scope.collections.watchById(widget.collectionId),
        builder: (context, collectionSnapshot) {
          final collection = collectionSnapshot.data;
          if (collection == null) {
            return const Center(child: CircularProgressIndicator());
          }
          _nameController ??= TextEditingController(text: collection.name);
          _nameFocusNode ??= FocusNode()
            ..addListener(() {
              if (!_nameFocusNode!.hasFocus) {
                _saveName(
                  _nameController!.text,
                  (name) => scope.collections.rename(widget.collectionId, name),
                );
              }
            });
          _titleFieldLabelController ??= TextEditingController(
            text: collection.titleFieldLabel ?? '',
          );
          _titleFieldLabelFocusNode ??= FocusNode()
            ..addListener(() {
              if (!_titleFieldLabelFocusNode!.hasFocus) {
                _saveTitleFieldLabel(_titleFieldLabelController!.text);
              }
            });

          final theme = ShadTheme.of(context);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ShadCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Collection', style: theme.textTheme.h4),
                    const SizedBox(height: 12),
                    Text('Icon', style: theme.textTheme.small),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        ShadButton.outline(
                          onPressed: () => _pickIcon(context),
                          child: collection.icon != null
                              ? Text(
                                  collection.icon!,
                                  style: const TextStyle(fontSize: 20),
                                )
                              : const Text('Pick emoji'),
                        ),
                        if (collection.icon != null) ...[
                          const SizedBox(width: 8),
                          Tooltip(
                            message: 'Remove icon',
                            child: ShadIconButton.ghost(
                              icon: const Icon(Icons.clear),
                              onPressed: () => scope.collections.setIcon(
                                widget.collectionId,
                                null,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text('Name', style: theme.textTheme.small),
                    const SizedBox(height: 4),
                    ShadInput(
                      controller: _nameController,
                      focusNode: _nameFocusNode,
                      onSubmitted: (value) => _saveName(
                        value,
                        (name) => scope.collections.rename(widget.collectionId, name),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text('Name column label', style: theme.textTheme.small),
                    const SizedBox(height: 4),
                    ShadInput(
                      controller: _titleFieldLabelController,
                      focusNode: _titleFieldLabelFocusNode,
                      placeholder: const Text('Name'),
                      onSubmitted: _saveTitleFieldLabel,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ShadCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Fields', style: theme.textTheme.h4),
                    const SizedBox(height: 12),
                    // Needed for the relation type's target-collection
                    // dropdown - other collections in the same space.
                    StreamBuilder<List<Collection>>(
                      stream: scope.collections.watchAllInSpace(collection.spaceId),
                      builder: (context, collectionsSnapshot) {
                        final collections =
                            collectionsSnapshot.data ?? const <Collection>[];
                        return StreamBuilder<List<Field>>(
                          stream: scope.fields.watchAllInCollection(
                            widget.collectionId,
                          ),
                          builder: (context, fieldsSnapshot) {
                            final fields = fieldsSnapshot.data ?? const <Field>[];
                            // Drop controllers/focus nodes of fields
                            // that no longer exist (deleted, or from a
                            // previous collection).
                            _fieldNameControllers.removeWhere((id, controller) {
                              final stillExists = fields.any((f) => f.id == id);
                              if (!stillExists) controller.dispose();
                              return !stillExists;
                            });
                            _fieldFocusNodes.removeWhere((id, focusNode) {
                              final stillExists = fields.any((f) => f.id == id);
                              if (!stillExists) focusNode.dispose();
                              return !stillExists;
                            });
                            return Column(
                              children: [
                                if (fields.isEmpty)
                                  const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 8),
                                    child: Text('No fields yet'),
                                  ),
                                for (final field in fields)
                                  _FieldRow(
                                    field: field,
                                    nameController: _fieldNameControllerFor(field),
                                    focusNode: _fieldFocusNodeFor(field, scope.fields),
                                    fields: scope.fields,
                                    collections: collections,
                                  ),
                                const ShadSeparator.horizontal(),
                                _AddFieldRow(
                                  nameController: _newFieldNameController,
                                  type: _newFieldType,
                                  onTypeChanged: (type) => setState(() {
                                    _newFieldType = type;
                                  }),
                                  collections: collections,
                                  relationTargetId: _newFieldRelationTargetId,
                                  onRelationTargetChanged: (id) => setState(() {
                                    _newFieldRelationTargetId = id;
                                  }),
                                  onAdd: () => _addField(scope.fields),
                                ),
                              ],
                            );
                          },
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({
    required this.field,
    required this.nameController,
    required this.focusNode,
    required this.fields,
    required this.collections,
  });

  final Field field;
  final TextEditingController nameController;
  final FocusNode focusNode;
  final FieldsRepository fields;

  /// Other collections in the same space - the relation type's target
  /// picker offers these (see build()).
  final List<Collection> collections;

  @override
  Widget build(BuildContext context) {
    final isRelation = field.type == FieldType.relation.name;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: ShadInput(
              controller: nameController,
              focusNode: focusNode,
              onSubmitted: (value) {
                final trimmed = value.trim();
                if (trimmed.isNotEmpty) fields.rename(field.id, trimmed);
              },
            ),
          ),
          const SizedBox(width: 8),
          ShadSelect<FieldType>(
            initialValue: FieldType.values.byName(field.type),
            selectedOptionBuilder: (context, value) => Text(value.label),
            options: [
              for (final type in FieldType.values)
                ShadOption(value: type, child: Text(type.label)),
            ],
            onChanged: (type) {
              if (type != null) fields.changeType(field.id, type);
            },
          ),
          if (isRelation) ...[
            const SizedBox(width: 8),
            ShadSelect<String>(
              initialValue: decodeRelationTargetCollectionId(field.config),
              placeholder: const Text('Relates to...'),
              selectedOptionBuilder: (context, value) =>
                  Text(collections.firstWhere((c) => c.id == value).name),
              options: [
                for (final collection in collections)
                  ShadOption(value: collection.id, child: Text(collection.name)),
              ],
              onChanged: (targetId) {
                if (targetId != null) {
                  fields.updateConfig(field.id, encodeRelationConfig(targetId));
                }
              },
            ),
          ],
          Tooltip(
            message: 'Delete field',
            child: ShadIconButton.ghost(
              icon: const Icon(Icons.delete_outline),
              onPressed: () => fields.softDelete(field.id),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddFieldRow extends StatelessWidget {
  const _AddFieldRow({
    required this.nameController,
    required this.type,
    required this.onTypeChanged,
    required this.collections,
    required this.relationTargetId,
    required this.onRelationTargetChanged,
    required this.onAdd,
  });

  final TextEditingController nameController;
  final FieldType type;
  final ValueChanged<FieldType> onTypeChanged;
  final List<Collection> collections;
  final String? relationTargetId;
  final ValueChanged<String?> onRelationTargetChanged;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final isRelation = type == FieldType.relation;
    // A relation field is useless without a target - block adding
    // until one's picked, rather than creating a half-configured field.
    final canAdd = !isRelation || relationTargetId != null;
    return Row(
      children: [
        Expanded(
          child: ShadInput(
            controller: nameController,
            placeholder: const Text('New field name'),
            onSubmitted: (_) => onAdd(),
          ),
        ),
        const SizedBox(width: 8),
        ShadSelect<FieldType>(
          initialValue: type,
          selectedOptionBuilder: (context, value) => Text(value.label),
          options: [
            for (final t in FieldType.values)
              ShadOption(value: t, child: Text(t.label)),
          ],
          onChanged: (t) {
            if (t != null) onTypeChanged(t);
          },
        ),
        if (isRelation) ...[
          const SizedBox(width: 8),
          ShadSelect<String>(
            initialValue: relationTargetId,
            placeholder: const Text('Relates to...'),
            selectedOptionBuilder: (context, value) =>
                Text(collections.firstWhere((c) => c.id == value).name),
            options: [
              for (final collection in collections)
                ShadOption(value: collection.id, child: Text(collection.name)),
            ],
            onChanged: onRelationTargetChanged,
          ),
        ],
        Tooltip(
          message: 'Add field',
          child: ShadIconButton.ghost(
            icon: const Icon(Icons.add),
            onPressed: canAdd ? onAdd : null,
          ),
        ),
      ],
    );
  }
}
