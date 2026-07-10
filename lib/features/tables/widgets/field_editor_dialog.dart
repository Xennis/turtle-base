import 'package:flutter/material.dart';
import 'package:turtle_base/features/tables/data/field_type.dart';
import 'package:turtle_base/features/tables/data/fields_repository.dart';

/// Shows a dialog to create a new field, or rename/retype/delete an
/// existing one. Pass [fieldId] (plus its current name/type) to edit;
/// omit it to create a field instead.
Future<void> showFieldEditorDialog(
  BuildContext context, {
  required FieldsRepository fields,
  required String collectionId,
  String? fieldId,
  String initialName = '',
  FieldType initialType = FieldType.text,
}) {
  final controller = TextEditingController(text: initialName);
  var selectedType = initialType;

  return showDialog<void>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text(fieldId == null ? 'New field' : 'Edit field'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                const SizedBox(height: 12),
                DropdownButton<FieldType>(
                  value: selectedType,
                  isExpanded: true,
                  items: [
                    for (final type in FieldType.values)
                      DropdownMenuItem(value: type, child: Text(type.label)),
                  ],
                  onChanged: (type) => setState(() => selectedType = type!),
                ),
              ],
            ),
            actions: [
              if (fieldId != null)
                TextButton(
                  onPressed: () async {
                    await fields.softDelete(fieldId);
                    if (context.mounted) Navigator.of(context).pop();
                  },
                  child: const Text('Delete'),
                ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  final name = controller.text.trim();
                  if (name.isEmpty) return;
                  if (fieldId == null) {
                    await fields.create(
                      collectionId: collectionId,
                      name: name,
                      type: selectedType,
                    );
                  } else {
                    await fields.rename(fieldId, name);
                    if (selectedType != initialType) {
                      await fields.changeType(fieldId, selectedType);
                    }
                  }
                  if (context.mounted) Navigator.of(context).pop();
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      );
    },
  );
}
