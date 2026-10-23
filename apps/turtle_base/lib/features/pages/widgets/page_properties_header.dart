// Flutter's own `Page` (Navigator 2.0) collides with our `Page` data class.
import 'package:flutter/material.dart' hide Page;
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:turtle_base/core/app_scope.dart';
import 'package:turtle_base/core/database/app_database.dart';
import 'package:turtle_base/features/pages/data/pages_repository.dart';
import 'package:turtle_base/features/pages/widgets/relation_picker_dialog.dart';
import 'package:field_types/field_types.dart';
import 'package:turtle_base/features/tables/data/base_field_type.dart';
import 'package:turtle_base/features/tables/data/relation_field.dart';
import 'package:turtle_base/features/tables/data/resolved_field.dart';
import 'package:turtle_base/features/tables/data/select_field.dart';
import 'package:turtle_base/features/tables/widgets/select_option_chip.dart';
import 'package:turtle_base/features/tables/widgets/select_option_picker_dialog.dart';

/// The typed-fields area of a collection entry's Page-View, shown above
/// the rich-text body (see UI_UX.md). Not used for freestanding pages.
class PagePropertiesHeader extends StatefulWidget {
  const PagePropertiesHeader({super.key, required this.pageId, required this.collectionId});

  final String pageId;
  final String collectionId;

  @override
  State<PagePropertiesHeader> createState() => _PagePropertiesHeaderState();
}

class _PagePropertiesHeaderState extends State<PagePropertiesHeader> {
  final _controllers = <String, TextEditingController>{};
  final _focusNodes = <String, FocusNode>{};

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    for (final focusNode in _focusNodes.values) {
      focusNode.dispose();
    }
    super.dispose();
  }

  // Created once per field id, like CollectionEditPage's field-name
  // controllers - pulling the value back down from the stream on every
  // rebuild would reset the cursor mid-edit.
  TextEditingController _controllerFor(ResolvedField field, Page page) {
    final existing = _controllers[field.id];
    if (existing != null) return existing;
    final controller = TextEditingController(text: field.display(decodePageProperties(page.properties)[field.id]));
    _controllers[field.id] = controller;
    return controller;
  }

  // Persists through whichever ResolvedField is current at blur time -
  // the listener outlives the build it was created in, and the field's
  // type or config may have changed since.
  FocusNode _focusNodeFor(ResolvedField field, AppScope scope) {
    final existing = _focusNodes[field.id];
    if (existing != null) return existing;
    final focusNode = FocusNode();
    focusNode.addListener(() {
      final current = _fields[field.id];
      if (!focusNode.hasFocus && current != null) {
        _persistIfValid(scope, current, _controllers[field.id]!.text);
      }
    });
    _focusNodes[field.id] = focusNode;
    return focusNode;
  }

  // Invalid input is never saved - the field keeps showing what the
  // user typed (and the validator's error) until they fix or clear
  // it, but the last valid value stays in the database untouched.
  void _persistIfValid(AppScope scope, ResolvedField field, String value) {
    if (field.parse(value) case ParsedValue(:final stored)) {
      scope.pages.setPropertyValue(widget.pageId, field.id, stored);
    }
  }

  String? _validate(ResolvedField field, String value) => switch (field.parse(value)) {
    ParseError(:final message) => message,
    ParsedValue() => null,
  };

  TextInputType? _keyboardTypeFor(ResolvedField field) => switch (field.inputHint) {
    InputHint.number => const TextInputType.numberWithOptions(decimal: true, signed: true),
    InputHint.url => TextInputType.url,
    InputHint.email => TextInputType.emailAddress,
    InputHint.phone => TextInputType.phone,
    InputHint.text || null => null,
  };

  /// The latest resolved fields by id, see _focusNodeFor.
  var _fields = <String, ResolvedField>{};

  Widget _valueEditor(AppScope scope, ResolvedField field, Page page) {
    final raw = decodePageProperties(page.properties)[field.id];
    return switch (field.base) {
      SelectFieldType() => _SelectFieldValue(pageId: widget.pageId, field: field, rawValue: raw),
      RelationFieldType() => _RelationFieldValue(
        pageId: widget.pageId,
        field: field.row,
        selectedIds: decodeRelationValue(raw),
      ),
      TextFieldType() || NumberFieldType() || DateFieldType() => ShadInputFormField(
        controller: _controllerFor(field, page),
        focusNode: _focusNodeFor(field, scope),
        // always, not onUserInteraction - an already-invalid stored
        // value (e.g. a number field typed as "3a" before) should show
        // as an error right when the page opens, not just after the
        // next edit.
        autovalidateMode: AutovalidateMode.always,
        keyboardType: _keyboardTypeFor(field),
        validator: (value) => _validate(field, value),
        onSubmitted: (value) => _persistIfValid(scope, field, value),
      ),
      UnsupportedFieldType() => Padding(padding: const EdgeInsets.only(top: 12), child: Text(field.display(raw))),
    };
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return StreamBuilder<Page>(
      stream: scope.pages.watchById(widget.pageId),
      builder: (context, pageSnapshot) {
        final page = pageSnapshot.data;
        if (page == null) return const SizedBox.shrink();
        return StreamBuilder<List<Field>>(
          stream: scope.fields.watchAllInCollection(widget.collectionId),
          builder: (context, fieldsSnapshot) {
            final fields = [
              for (final field in fieldsSnapshot.data ?? const <Field>[]) scope.fieldTypes.resolve(field),
            ];
            _fields = {for (final field in fields) field.id: field};
            _controllers.removeWhere((id, controller) {
              final stillExists = fields.any((f) => f.id == id);
              if (!stillExists) controller.dispose();
              return !stillExists;
            });
            _focusNodes.removeWhere((id, focusNode) {
              final stillExists = fields.any((f) => f.id == id);
              if (!stillExists) focusNode.dispose();
              return !stillExists;
            });
            if (fields.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final field in fields)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: SizedBox(
                            width: 120,
                            child: Text(field.name, style: Theme.of(context).textTheme.bodyMedium),
                          ),
                        ),
                        Expanded(child: _valueEditor(scope, field, page)),
                      ],
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

/// A relation field's value: chips for the currently related entries
/// (each removable), plus an "Add" chip opening the picker dialog.
class _RelationFieldValue extends StatelessWidget {
  const _RelationFieldValue({required this.pageId, required this.field, required this.selectedIds});

  final String pageId;
  final Field field;
  final List<String> selectedIds;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final targetCollectionId = decodeRelationTargetCollectionId(field.config);
    if (targetCollectionId == null) {
      // No target picked yet (shouldn't normally happen - the
      // Field-Editor requires one - but a relation field is otherwise
      // unusable, so fail visibly rather than silently doing nothing).
      return const Text('No target collection configured');
    }
    return StreamBuilder<List<Page>>(
      stream: scope.pages.watchAllInCollection(targetCollectionId),
      builder: (context, snapshot) {
        final targetPages = snapshot.data ?? const <Page>[];
        final selected = [for (final id in selectedIds) ..._findById(targetPages, id)];
        return Wrap(
          spacing: 4,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final page in selected)
              _RelationChip(
                label: page.title.isEmpty ? 'Untitled' : page.title,
                onRemove: () =>
                    scope.pages.setPropertyValue(pageId, field.id, selectedIds.where((id) => id != page.id).toList()),
              ),
            ShadButton.ghost(
              size: ShadButtonSize.sm,
              leading: const Icon(Icons.add, size: 16),
              onPressed: () async {
                final result = await showRelationPicker(
                  context,
                  scope: scope,
                  targetCollectionId: targetCollectionId,
                  selectedIds: selectedIds,
                );
                if (result != null) {
                  await scope.pages.setPropertyValue(pageId, field.id, result);
                }
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }

  Iterable<Page> _findById(List<Page> pages, String id) {
    return pages.where((p) => p.id == id);
  }
}

/// A select/multi-select field's value: one chip per selected option
/// (removable for a multi-select), plus a button opening the option
/// picker. A select's chip opens the picker too, to switch options.
class _SelectFieldValue extends StatelessWidget {
  const _SelectFieldValue({required this.pageId, required this.field, required this.rawValue});

  final String pageId;
  final ResolvedField field;
  final Object? rawValue;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final multiple = (field.base as SelectFieldType).multiple;
    final selected = resolveSelectValue((field.config as SelectConfig).options, field.valueOf(rawValue));
    final selectedIds = [for (final option in selected) option.id];

    Future<void> openPicker() async {
      final result = await showSelectOptionPicker(context, scope: scope, field: field.row, selectedIds: selectedIds);
      if (result == null) return;
      await scope.pages.setPropertyValue(pageId, field.id, field.base.encode(result, field.config));
    }

    return Padding(
      // Lines the chips up with the field label's baseline (see the
      // label's own top padding in PagePropertiesHeader.build).
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final option in selected)
            SelectOptionChip(
              option: option,
              onPressed: multiple ? null : openPicker,
              onRemove: multiple
                  ? () => scope.pages.setPropertyValue(
                      pageId,
                      field.id,
                      selectedIds.where((id) => id != option.id).toList(),
                    )
                  : null,
            ),
          // A select with a value is changed by tapping its chip - an
          // extra button would only repeat that.
          if (multiple || selected.isEmpty)
            ShadButton.ghost(
              size: ShadButtonSize.sm,
              leading: const Icon(Icons.add, size: 16),
              onPressed: openPicker,
              child: Text(multiple ? 'Add' : 'Select'),
            ),
        ],
      ),
    );
  }
}

/// A removable chip for a related entry - shadcn_ui's Badge has no
/// built-in remove affordance, so this composes one from theme tokens.
class _RelationChip extends StatelessWidget {
  const _RelationChip({required this.label, required this.onRemove});

  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
      decoration: BoxDecoration(color: theme.colorScheme.secondary, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: theme.textTheme.small.copyWith(color: theme.colorScheme.secondaryForeground)),
          const SizedBox(width: 2),
          InkWell(
            onTap: onRemove,
            borderRadius: BorderRadius.circular(999),
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Icon(Icons.close, size: 14, color: theme.colorScheme.secondaryForeground),
            ),
          ),
        ],
      ),
    );
  }
}
