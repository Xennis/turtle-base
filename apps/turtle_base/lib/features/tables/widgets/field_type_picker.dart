import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:turtle_base/features/tables/data/base_field_type.dart';
import 'package:turtle_base/features/tables/data/field_type_registry.dart';

/// Picks a base type or one of its variants, grouped and sorted by
/// label so the growing list stays scannable.
class FieldTypePicker extends StatelessWidget {
  const FieldTypePicker({super.key, required this.value, required this.choices, required this.onChanged});

  final FieldTypeChoice value;
  final List<FieldTypeChoice> choices;
  final ValueChanged<FieldTypeChoice> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return ShadSelect<FieldTypeChoice>(
      minWidth: 170,
      initialValue: value,
      selectedOptionBuilder: (context, choice) => _ChoiceLabel(choice: choice),
      options: [
        for (final group in _FieldTypeGroup.values)
          if (_sortedIn(group) case final inGroup when inGroup.isNotEmpty) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                child: Text(group.label, style: theme.textTheme.muted.copyWith(fontSize: 12)),
              ),
            ),
            for (final choice in inGroup)
              ShadOption(
                value: choice,
                child: _ChoiceLabel(choice: choice),
              ),
          ],
      ],
      onChanged: (choice) {
        if (choice != null) onChanged(choice);
      },
    );
  }

  List<FieldTypeChoice> _sortedIn(_FieldTypeGroup group) =>
      choices.where((c) => _FieldTypeGroup.of(c) == group).toList()
        ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
}

enum _FieldTypeGroup {
  basic('Basic'),
  choice('Choice'),
  format('Formats'),
  advanced('Advanced');

  const _FieldTypeGroup(this.label);

  final String label;

  static _FieldTypeGroup of(FieldTypeChoice choice) {
    if (choice.variant != null) return format;
    return switch (choice.base) {
      TextFieldType() ||
      NumberFieldType() ||
      DateFieldType() ||
      CheckboxFieldType() ||
      LocationFieldType() ||
      FilesFieldType() => basic,
      SelectFieldType() => _FieldTypeGroup.choice,
      RelationFieldType() || UnsupportedFieldType() => advanced,
    };
  }
}

class _ChoiceLabel extends StatelessWidget {
  const _ChoiceLabel({required this.choice});

  final FieldTypeChoice choice;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(fieldTypeIcon(choice), size: 16, color: ShadTheme.of(context).colorScheme.mutedForeground),
        const SizedBox(width: 8),
        Flexible(child: Text(choice.label, overflow: TextOverflow.ellipsis)),
      ],
    );
  }
}

/// Icons by variant id - FieldVariant has no Flutter dependency to
/// carry one. A variant not listed here shows its base type's icon.
const _variantIcons = <String, IconData>{
  'url': Icons.link,
  'email': Icons.alternate_email,
  'phone': Icons.phone_outlined,
  'books.isbn': Icons.menu_book_outlined,
};

IconData fieldTypeIcon(FieldTypeChoice choice) {
  final variantIcon = _variantIcons[choice.variant?.id];
  if (variantIcon != null) return variantIcon;
  return switch (choice.base) {
    TextFieldType() => Icons.notes,
    NumberFieldType() => Icons.tag,
    DateFieldType() => Icons.calendar_today_outlined,
    CheckboxFieldType() => Icons.check_box_outlined,
    SelectFieldType(multiple: false) => Icons.arrow_drop_down_circle_outlined,
    SelectFieldType(multiple: true) => Icons.checklist,
    RelationFieldType() => Icons.north_east,
    LocationFieldType() => Icons.place_outlined,
    FilesFieldType() => Icons.attach_file,
    UnsupportedFieldType() => Icons.help_outline,
  };
}
