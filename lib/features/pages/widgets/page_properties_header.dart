// Flutter's own `Page` (Navigator 2.0) collides with our `Page` data class.
import 'package:flutter/material.dart' hide Page;
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:turtle_base/core/app_scope.dart';
import 'package:turtle_base/core/database/app_database.dart';
import 'package:turtle_base/features/pages/data/pages_repository.dart';
import 'package:turtle_base/features/pages/widgets/relation_picker_dialog.dart';
import 'package:turtle_base/features/tables/data/field_type.dart';
import 'package:turtle_base/features/tables/data/field_validation.dart';
import 'package:turtle_base/features/tables/data/relation_field.dart';

/// The typed-fields area of a collection entry's Page-View, shown above
/// the rich-text body (see UI_UX.md). Not used for freestanding pages.
class PagePropertiesHeader extends StatefulWidget {
  const PagePropertiesHeader({
    super.key,
    required this.pageId,
    required this.collectionId,
  });

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
  TextEditingController _controllerFor(Field field, Page page) {
    final existing = _controllers[field.id];
    if (existing != null) return existing;
    final value = decodePageProperties(page.properties)[field.id];
    final controller = TextEditingController(text: value?.toString() ?? '');
    _controllers[field.id] = controller;
    return controller;
  }

  FocusNode _focusNodeFor(Field field, AppScope scope) {
    final existing = _focusNodes[field.id];
    if (existing != null) return existing;
    final focusNode = FocusNode();
    focusNode.addListener(() {
      if (!focusNode.hasFocus) {
        _persistIfValid(scope, field, _controllers[field.id]!.text);
      }
    });
    _focusNodes[field.id] = focusNode;
    return focusNode;
  }

  // Invalid input is never saved - the field keeps showing what the
  // user typed (and the validator's error) until they fix or clear
  // it, but the last valid value stays in the database untouched.
  void _persistIfValid(AppScope scope, Field field, String value) {
    if (!isValidForType(FieldType.values.byName(field.type), value)) return;
    scope.pages.setPropertyValue(widget.pageId, field.id, value);
  }

  String? Function(String)? _validatorFor(Field field) {
    final type = FieldType.values.byName(field.type);
    final message = invalidMessageFor(type);
    if (message == null) return null; // text/relation are never invalid
    return (value) => isValidForType(type, value) ? null : message;
  }

  TextInputType? _keyboardTypeFor(Field field) {
    if (field.type == FieldType.number.name) {
      return const TextInputType.numberWithOptions(decimal: true);
    }
    if (field.type == FieldType.url.name) return TextInputType.url;
    return null;
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
            final fields = fieldsSnapshot.data ?? const <Field>[];
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
                            child: Text(
                              field.name,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                        ),
                        Expanded(
                          child: field.type == FieldType.relation.name
                              ? _RelationFieldValue(
                                  pageId: widget.pageId,
                                  field: field,
                                  selectedIds: decodeRelationValue(
                                    decodePageProperties(
                                      page.properties,
                                    )[field.id],
                                  ),
                                )
                              : ShadInputFormField(
                                  controller: _controllerFor(field, page),
                                  focusNode: _focusNodeFor(field, scope),
                                  // always, not onUserInteraction - an
                                  // already-invalid stored value (e.g. a
                                  // number field typed as "3a" before)
                                  // should show as an error right when
                                  // the page opens, not just after the
                                  // next edit.
                                  autovalidateMode: AutovalidateMode.always,
                                  keyboardType: _keyboardTypeFor(field),
                                  validator: _validatorFor(field),
                                  onSubmitted: (value) =>
                                      _persistIfValid(scope, field, value),
                                ),
                        ),
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
  const _RelationFieldValue({
    required this.pageId,
    required this.field,
    required this.selectedIds,
  });

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
        final selected = [
          for (final id in selectedIds) ..._findById(targetPages, id),
        ];
        return Wrap(
          spacing: 4,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final page in selected)
              _RelationChip(
                label: page.title.isEmpty ? 'Untitled' : page.title,
                onRemove: () => scope.pages.setPropertyValue(
                  pageId,
                  field.id,
                  selectedIds.where((id) => id != page.id).toList(),
                ),
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
      decoration: BoxDecoration(
        color: theme.colorScheme.secondary,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: theme.textTheme.small.copyWith(
              color: theme.colorScheme.secondaryForeground,
            ),
          ),
          const SizedBox(width: 2),
          InkWell(
            onTap: onRemove,
            borderRadius: BorderRadius.circular(999),
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Icon(
                Icons.close,
                size: 14,
                color: theme.colorScheme.secondaryForeground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
