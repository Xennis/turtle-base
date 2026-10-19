import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:turtle_base/core/app_scope.dart';
import 'package:turtle_base/core/database/app_database.dart';
import 'package:turtle_base/features/tables/data/field_type.dart';
import 'package:turtle_base/features/tables/data/select_field.dart';
import 'package:turtle_base/features/tables/widgets/select_option_chip.dart';

/// A searchable list of a select/multi-select field's options, which
/// also creates a new option from the search text. Returns the updated
/// option ids, or null if the user cancelled.
///
/// For a select field, picking an option returns right away (picking
/// the current one again clears it); a multi-select toggles options
/// until "Done".
Future<List<String>?> showSelectOptionPicker(
  BuildContext context, {
  required AppScope scope,
  required Field field,
  required List<String> selectedIds,
}) {
  return showShadDialog<List<String>>(
    context: context,
    builder: (context) => _SelectOptionPickerDialog(scope: scope, field: field, initialSelectedIds: selectedIds),
  );
}

class _SelectOptionPickerDialog extends StatefulWidget {
  const _SelectOptionPickerDialog({required this.scope, required this.field, required this.initialSelectedIds});

  final AppScope scope;
  final Field field;
  final List<String> initialSelectedIds;

  @override
  State<_SelectOptionPickerDialog> createState() => _SelectOptionPickerDialogState();
}

class _SelectOptionPickerDialogState extends State<_SelectOptionPickerDialog> {
  late final List<String> _selectedIds = [...widget.initialSelectedIds];
  final _searchController = TextEditingController();
  String _query = '';

  bool get _multiple => widget.field.type == FieldType.multiSelect.name;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggle(String optionId) {
    if (!_multiple) {
      final isCurrent = _selectedIds.length == 1 && _selectedIds.first == optionId;
      Navigator.of(context).pop(isCurrent ? <String>[] : [optionId]);
      return;
    }
    setState(() {
      if (!_selectedIds.remove(optionId)) _selectedIds.add(optionId);
    });
  }

  Future<void> _create(String name) async {
    final option = await widget.scope.fields.addSelectOption(widget.field.id, name);
    if (!mounted) return;
    _searchController.clear();
    setState(() => _query = '');
    _toggle(option.id);
  }

  /// Enter picks the only/first match, or creates the option if
  /// nothing matches - so a value can be added keyboard-only.
  void _onSubmitted(List<SelectOption> matches, bool canCreate) {
    final name = _query.trim();
    if (canCreate) {
      _create(name);
    } else if (matches.isNotEmpty && name.isNotEmpty) {
      _toggle(matches.first.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return StreamBuilder<Field>(
      // Watched rather than taken from widget.field, so an option
      // created here shows up right away.
      stream: widget.scope.fields.watchById(widget.field.id),
      initialData: widget.field,
      builder: (context, snapshot) {
        final options = decodeSelectOptions(snapshot.data!.config);
        final name = _query.trim();
        final query = name.toLowerCase();
        final matches = options.where((o) => o.name.toLowerCase().contains(query)).toList();
        final canCreate = name.isNotEmpty && !options.any((o) => o.name.toLowerCase() == query);
        final selected = resolveSelectValue(options, _selectedIds);
        return ShadDialog(
          title: Text(widget.field.name),
          actions: [
            ShadButton.outline(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
            if (_multiple)
              ShadButton(
                onPressed: () => Navigator.of(context).pop(
                  // Only ids of options that still exist - drops any
                  // left over from deleted options while at it.
                  [for (final option in selected) option.id],
                ),
                child: const Text('Done'),
              ),
          ],
          child: SizedBox(
            width: 400,
            height: 400,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (selected.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        for (final option in selected)
                          SelectOptionChip(
                            option: option,
                            onRemove: () => _multiple ? _toggle(option.id) : Navigator.of(context).pop(<String>[]),
                          ),
                      ],
                    ),
                  ),
                ShadInput(
                  controller: _searchController,
                  autofocus: true,
                  placeholder: const Text('Search or create an option'),
                  onChanged: (value) => setState(() => _query = value),
                  onSubmitted: (_) => _onSubmitted(matches, canCreate),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView(
                    children: [
                      if (options.isEmpty && !canCreate)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Center(
                            child: Text('No options yet - type to create one', style: theme.textTheme.muted),
                          ),
                        ),
                      for (final option in matches)
                        ShadButton.ghost(
                          width: double.infinity,
                          onPressed: () => _toggle(option.id),
                          trailing: _selectedIds.contains(option.id) ? const Icon(Icons.check, size: 16) : null,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: SelectOptionChip(option: option),
                          ),
                        ),
                      if (canCreate)
                        ShadButton.ghost(
                          width: double.infinity,
                          onPressed: () => _create(name),
                          leading: const Icon(Icons.add, size: 16),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text('Create'),
                                const SizedBox(width: 8),
                                Flexible(
                                  // Previews the color it'll get.
                                  child: SelectOptionChip(
                                    option: SelectOption(id: '', name: name, color: nextOptionColor(options)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
