import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:turtle_base/core/database/app_database.dart';
import 'package:turtle_base/features/shell/widgets/confirm_dialog.dart';
import 'package:turtle_base/features/tables/data/fields_repository.dart';
import 'package:turtle_base/features/tables/data/select_field.dart';
import 'package:turtle_base/features/tables/widgets/select_option_chip.dart';

/// The options of a select/multi-select field in CollectionEditPage:
/// one row per option (color, name, delete) plus an "Add option" input.
/// Options can also be created on the fly from the option picker (see
/// showSelectOptionPicker) - this is where they're curated.
class SelectOptionsEditor extends StatefulWidget {
  const SelectOptionsEditor({super.key, required this.field, required this.fields});

  final Field field;
  final FieldsRepository fields;

  @override
  State<SelectOptionsEditor> createState() => _SelectOptionsEditorState();
}

class _SelectOptionsEditorState extends State<SelectOptionsEditor> {
  final _newOptionController = TextEditingController();

  @override
  void dispose() {
    _newOptionController.dispose();
    super.dispose();
  }

  Future<void> _addOption() async {
    final name = _newOptionController.text.trim();
    if (name.isEmpty) return;
    await widget.fields.addSelectOption(widget.field.id, name);
    _newOptionController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final options = decodeSelectOptions(widget.field.config);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final option in options)
          // Keyed by option id, so each row's controller/focus node
          // stays with its option when others are added or removed.
          _OptionRow(key: ValueKey(option.id), fieldId: widget.field.id, option: option, fields: widget.fields),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: ShadInput(
                  controller: _newOptionController,
                  placeholder: const Text('Add option'),
                  onSubmitted: (_) => _addOption(),
                ),
              ),
              Tooltip(
                message: 'Add option',
                child: ShadIconButton.ghost(icon: const Icon(Icons.add), onPressed: _addOption),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _OptionRow extends StatefulWidget {
  const _OptionRow({super.key, required this.fieldId, required this.option, required this.fields});

  final String fieldId;
  final SelectOption option;
  final FieldsRepository fields;

  @override
  State<_OptionRow> createState() => _OptionRowState();
}

class _OptionRowState extends State<_OptionRow> {
  late final _nameController = TextEditingController(text: widget.option.name);
  final _focusNode = FocusNode();
  final _colorPopoverController = ShadPopoverController();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus) _saveName(_nameController.text);
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _focusNode.dispose();
    _colorPopoverController.dispose();
    super.dispose();
  }

  void _saveName(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed == widget.option.name) return;
    widget.fields.updateSelectOption(widget.fieldId, widget.option.copyWith(name: trimmed));
  }

  void _setColor(OptionColor color) {
    _colorPopoverController.hide();
    widget.fields.updateSelectOption(widget.fieldId, widget.option.copyWith(color: color));
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          ShadPopover(
            controller: _colorPopoverController,
            popover: (context) => _ColorPalette(selected: widget.option.color, onSelected: _setColor),
            child: Tooltip(
              message: 'Change color',
              child: ShadIconButton.ghost(
                icon: OptionColorDot(color: widget.option.color),
                onPressed: _colorPopoverController.toggle,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: ShadInput(controller: _nameController, focusNode: _focusNode, onSubmitted: _saveName),
          ),
          Tooltip(
            message: 'Delete option',
            child: ShadIconButton.ghost(
              icon: Icon(Icons.close, color: theme.colorScheme.mutedForeground),
              onPressed: () async {
                final confirmed = await confirmDelete(
                  context,
                  title: 'Delete option "${widget.option.name}"?',
                  message: 'Entries using it will no longer show this value.',
                );
                if (confirmed) {
                  await widget.fields.removeSelectOption(widget.fieldId, widget.option.id);
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// The fixed option palette, as a grid of swatches - each showing how
/// an option would look in that color, the current one ringed.
class _ColorPalette extends StatelessWidget {
  const _ColorPalette({required this.selected, required this.onSelected});

  final OptionColor selected;
  final ValueChanged<OptionColor> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return SizedBox(
      width: 3 * 40 + 2 * 4,
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          for (final color in OptionColor.values)
            Tooltip(
              message: color.label,
              child: ShadIconButton.ghost(
                width: 40,
                height: 40,
                decoration: color == selected
                    ? ShadDecoration(border: ShadBorder.all(color: theme.colorScheme.ring, width: 2))
                    : null,
                icon: OptionColorDot(color: color, size: 18),
                onPressed: () => onSelected(color),
              ),
            ),
        ],
      ),
    );
  }
}
