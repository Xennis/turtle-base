// Flutter's own `Page` (Navigator 2.0) collides with our `Page` data class.
import 'package:flutter/material.dart' hide Page;
import 'package:turtle_base/core/app_scope.dart';
import 'package:turtle_base/core/database/app_database.dart';
import 'package:turtle_base/features/tables/data/field_type.dart';
import 'package:turtle_base/features/tables/data/fields_repository.dart';

/// Large, non-modal-feeling panel listing every field of a collection,
/// each editable inline. Replaces a per-field dialog, which got
/// cramped quickly (and would only get worse with e.g. multi-select
/// option lists later).
class ManageFieldsPanel extends StatefulWidget {
  const ManageFieldsPanel({super.key, required this.collectionId});

  final String collectionId;

  static Future<void> show(BuildContext context, {required String collectionId}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.85,
        child: ManageFieldsPanel(collectionId: collectionId),
      ),
    );
  }

  @override
  State<ManageFieldsPanel> createState() => _ManageFieldsPanelState();
}

class _ManageFieldsPanelState extends State<ManageFieldsPanel> {
  final _newFieldNameController = TextEditingController();
  FieldType _newFieldType = FieldType.text;
  final _nameControllers = <String, TextEditingController>{};

  @override
  void dispose() {
    _newFieldNameController.dispose();
    for (final controller in _nameControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  TextEditingController _nameControllerFor(Field field) {
    final existing = _nameControllers[field.id];
    if (existing != null) return existing;
    final controller = TextEditingController(text: field.name);
    _nameControllers[field.id] = controller;
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
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Manage fields',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const Divider(),
            Expanded(
              child: StreamBuilder<List<Field>>(
                stream: scope.fields.watchAllInCollection(widget.collectionId),
                builder: (context, snapshot) {
                  final fields = snapshot.data ?? const <Field>[];
                  // Drop controllers of fields that no longer exist
                  // (deleted, or from a previous collection).
                  _nameControllers.removeWhere((id, controller) {
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
                          nameController: _nameControllerFor(field),
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
