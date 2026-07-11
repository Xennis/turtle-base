// Flutter's own `Page` (Navigator 2.0) collides with our `Page` data class.
import 'package:flutter/material.dart' hide Page;
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:turtle_base/core/app_scope.dart';
import 'package:turtle_base/core/database/app_database.dart';

/// A searchable checklist of a target collection's entries. Returns the
/// updated set of selected page ids, or null if the user cancelled.
Future<List<String>?> showRelationPicker(
  BuildContext context, {
  required AppScope scope,
  required String targetCollectionId,
  required List<String> selectedIds,
}) {
  return showShadDialog<List<String>>(
    context: context,
    builder: (context) => _RelationPickerDialog(
      scope: scope,
      targetCollectionId: targetCollectionId,
      initialSelectedIds: selectedIds,
    ),
  );
}

class _RelationPickerDialog extends StatefulWidget {
  const _RelationPickerDialog({
    required this.scope,
    required this.targetCollectionId,
    required this.initialSelectedIds,
  });

  final AppScope scope;
  final String targetCollectionId;
  final List<String> initialSelectedIds;

  @override
  State<_RelationPickerDialog> createState() => _RelationPickerDialogState();
}

class _RelationPickerDialogState extends State<_RelationPickerDialog> {
  late final Set<String> _selectedIds = {...widget.initialSelectedIds};
  String _query = '';

  @override
  Widget build(BuildContext context) {
    return ShadDialog(
      title: const Text('Select related entries'),
      actions: [
        ShadButton.outline(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ShadButton(
          onPressed: () => Navigator.of(context).pop(_selectedIds.toList()),
          child: const Text('Done'),
        ),
      ],
      child: SizedBox(
        width: 400,
        height: 400,
        child: Column(
          children: [
            ShadInput(
              autofocus: true,
              placeholder: const Text('Search'),
              onChanged: (value) => setState(() => _query = value),
            ),
            Expanded(
              child: StreamBuilder<List<Page>>(
                stream: widget.scope.pages.watchAllInCollection(widget.targetCollectionId),
                builder: (context, snapshot) {
                  final query = _query.toLowerCase();
                  final entries = (snapshot.data ?? const <Page>[])
                      .where((p) => p.title.toLowerCase().contains(query))
                      .toList();
                  if (entries.isEmpty) {
                    return const Center(child: Text('No entries found'));
                  }
                  return ListView(
                    children: [
                      for (final entry in entries)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: ShadCheckbox(
                            value: _selectedIds.contains(entry.id),
                            onChanged: (checked) => setState(() {
                              if (checked) {
                                _selectedIds.add(entry.id);
                              } else {
                                _selectedIds.remove(entry.id);
                              }
                            }),
                            label: Text(entry.title.isEmpty ? 'Untitled' : entry.title),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
