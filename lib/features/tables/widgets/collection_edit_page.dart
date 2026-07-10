import 'package:flutter/material.dart';
import 'package:turtle_base/core/app_scope.dart';
import 'package:turtle_base/core/database/app_database.dart';
import 'package:turtle_base/features/tables/data/field_type.dart';
import 'package:turtle_base/features/tables/data/fields_repository.dart';

/// Shown in the same content area as CollectionView (see
/// AppShell/_MainContent) rather than pushed via Navigator, so the
/// sidebar stays visible. [onDone] goes back to the grid.
class CollectionEditPage extends StatefulWidget {
  const CollectionEditPage({
    super.key,
    required this.collectionId,
    required this.onDone,
  });

  final String collectionId;
  final VoidCallback onDone;

  @override
  State<CollectionEditPage> createState() => _CollectionEditPageState();
}

class _CollectionEditPageState extends State<CollectionEditPage> {
  TextEditingController? _nameController;
  FocusNode? _nameFocusNode;
  final _newFieldNameController = TextEditingController();
  FieldType _newFieldType = FieldType.text;
  final _fieldNameControllers = <String, TextEditingController>{};
  final _fieldFocusNodes = <String, FocusNode>{};

  @override
  void dispose() {
    _nameController?.dispose();
    _nameFocusNode?.dispose();
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
    await fields.create(
      collectionId: widget.collectionId,
      name: name,
      type: _newFieldType,
    );
    _newFieldNameController.clear();
    setState(() => _newFieldType = FieldType.text);
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: widget.onDone,
        ),
        title: const Text('Edit collection'),
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

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Collection',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      Text('Name', style: Theme.of(context).textTheme.labelLarge),
                      const SizedBox(height: 4),
                      TextField(
                        controller: _nameController,
                        focusNode: _nameFocusNode,
                        onSubmitted: (value) => _saveName(
                          value,
                          (name) => scope.collections.rename(widget.collectionId, name),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Fields',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      StreamBuilder<List<Field>>(
                        stream: scope.fields.watchAllInCollection(
                          widget.collectionId,
                        ),
                        builder: (context, fieldsSnapshot) {
                          final fields = fieldsSnapshot.data ?? const <Field>[];
                          // Drop controllers/focus nodes of fields that
                          // no longer exist (deleted, or from a
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
                                ),
                              const Divider(),
                              _AddFieldRow(
                                nameController: _newFieldNameController,
                                type: _newFieldType,
                                onTypeChanged: (type) =>
                                    setState(() => _newFieldType = type),
                                onAdd: () => _addField(scope.fields),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
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
  });

  final Field field;
  final TextEditingController nameController;
  final FocusNode focusNode;
  final FieldsRepository fields;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: nameController,
              focusNode: focusNode,
              onSubmitted: (value) {
                final trimmed = value.trim();
                if (trimmed.isNotEmpty) fields.rename(field.id, trimmed);
              },
            ),
          ),
          const SizedBox(width: 8),
          DropdownButton<FieldType>(
            value: FieldType.values.byName(field.type),
            items: [
              for (final type in FieldType.values)
                DropdownMenuItem(value: type, child: Text(type.label)),
            ],
            onChanged: (type) {
              if (type != null) fields.changeType(field.id, type);
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete field',
            onPressed: () => fields.softDelete(field.id),
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
    required this.onAdd,
  });

  final TextEditingController nameController;
  final FieldType type;
  final ValueChanged<FieldType> onTypeChanged;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: nameController,
            decoration: const InputDecoration(hintText: 'New field name'),
            onSubmitted: (_) => onAdd(),
          ),
        ),
        const SizedBox(width: 8),
        DropdownButton<FieldType>(
          value: type,
          items: [
            for (final t in FieldType.values)
              DropdownMenuItem(value: t, child: Text(t.label)),
          ],
          onChanged: (t) {
            if (t != null) onTypeChanged(t);
          },
        ),
        IconButton(
          icon: const Icon(Icons.add),
          tooltip: 'Add field',
          onPressed: onAdd,
        ),
      ],
    );
  }
}
