import 'package:flutter/material.dart';
import 'package:turtle_base/core/app_scope.dart';
import 'package:turtle_base/core/database/app_database.dart';
import 'package:turtle_base/features/tables/data/field_type.dart';
import 'package:turtle_base/features/tables/data/fields_repository.dart';

/// Its own page (pushed via Navigator) rather than a sheet/dialog - a
/// sheet turned out cramped in practice, and this also has room for
/// the collection's own name, not just its fields.
class CollectionEditPage extends StatefulWidget {
  const CollectionEditPage({super.key, required this.collectionId});

  final String collectionId;

  @override
  State<CollectionEditPage> createState() => _CollectionEditPageState();
}

class _CollectionEditPageState extends State<CollectionEditPage> {
  TextEditingController? _nameController;
  final _newFieldNameController = TextEditingController();
  FieldType _newFieldType = FieldType.text;
  final _fieldNameControllers = <String, TextEditingController>{};

  @override
  void dispose() {
    _nameController?.dispose();
    _newFieldNameController.dispose();
    for (final controller in _fieldNameControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  TextEditingController _fieldNameControllerFor(Field field) {
    final existing = _fieldNameControllers[field.id];
    if (existing != null) return existing;
    final controller = TextEditingController(text: field.name);
    _fieldNameControllers[field.id] = controller;
    return controller;
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
      appBar: AppBar(title: const Text('Edit collection')),
      body: StreamBuilder<Collection>(
        stream: scope.collections.watchById(widget.collectionId),
        builder: (context, collectionSnapshot) {
          final collection = collectionSnapshot.data;
          if (collection == null) {
            return const Center(child: CircularProgressIndicator());
          }
          _nameController ??= TextEditingController(text: collection.name);

          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Name', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 4),
                TextField(
                  controller: _nameController,
                  onSubmitted: (value) {
                    final trimmed = value.trim();
                    if (trimmed.isNotEmpty) {
                      scope.collections.rename(widget.collectionId, trimmed);
                    }
                  },
                ),
                const SizedBox(height: 24),
                Text('Fields', style: Theme.of(context).textTheme.labelLarge),
                const Divider(),
                Expanded(
                  child: StreamBuilder<List<Field>>(
                    stream: scope.fields.watchAllInCollection(widget.collectionId),
                    builder: (context, fieldsSnapshot) {
                      final fields = fieldsSnapshot.data ?? const <Field>[];
                      // Drop controllers of fields that no longer exist
                      // (deleted, or from a previous collection).
                      _fieldNameControllers.removeWhere((id, controller) {
                        final stillExists = fields.any((f) => f.id == id);
                        if (!stillExists) controller.dispose();
                        return !stillExists;
                      });
                      if (fields.isEmpty) {
                        return const Center(child: Text('No fields yet'));
                      }
                      return ListView(
                        children: [
                          for (final field in fields)
                            _FieldRow(
                              field: field,
                              nameController: _fieldNameControllerFor(field),
                              fields: scope.fields,
                            ),
                        ],
                      );
                    },
                  ),
                ),
                const Divider(),
                _AddFieldRow(
                  nameController: _newFieldNameController,
                  type: _newFieldType,
                  onTypeChanged: (type) => setState(() => _newFieldType = type),
                  onAdd: () => _addField(scope.fields),
                ),
              ],
            ),
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
    required this.fields,
  });

  final Field field;
  final TextEditingController nameController;
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
