import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:turtle_base/features/tables/data/base_field_type.dart';
import 'package:turtle_base/features/tables/data/fields_repository.dart';
import 'package:turtle_base/features/tables/data/resolved_field.dart';

/// The type-specific settings of a text or number field in
/// CollectionEditPage - select options have their own
/// SelectOptionsEditor, a relation's target sits in the field's row.
/// Null for types without settings.
Widget? fieldConfigEditorFor(ResolvedField field, FieldsRepository fields) {
  final key = ValueKey('config-${field.id}-${field.base.id}');
  return switch (field.config) {
    TextConfig() => _TextConfigEditor(key: key, field: field, fields: fields),
    NumberConfig() => _NumberConfigEditor(key: key, field: field, fields: fields),
    _ => null,
  };
}

class _TextConfigEditor extends StatelessWidget {
  const _TextConfigEditor({super.key, required this.field, required this.fields});

  final ResolvedField field;
  final FieldsRepository fields;

  @override
  Widget build(BuildContext context) {
    final json = decodeFieldConfig(field.row.config);
    return _ConfigInput(
      label: 'Pattern',
      placeholder: 'Regular expression, e.g. [A-Z]{3}',
      initialValue: json[TextConfig.patternKey] as String? ?? '',
      validator: (value) => value.isEmpty || tryParsePattern(value) != null ? null : 'Not a valid regular expression',
      onSave: (value) => fields.updateConfigValues(field.id, {TextConfig.patternKey: value.isEmpty ? null : value}),
    );
  }
}

class _NumberConfigEditor extends StatelessWidget {
  const _NumberConfigEditor({super.key, required this.field, required this.fields});

  final ResolvedField field;
  final FieldsRepository fields;

  @override
  Widget build(BuildContext context) {
    final config = field.config as NumberConfig;
    String? numberValidator(String value) => value.isEmpty || num.tryParse(value) != null ? null : 'Not a number';
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        SizedBox(
          width: 120,
          child: _ConfigInput(
            label: 'Min',
            initialValue: config.min == null ? '' : formatPlainNumber(config.min!),
            validator: numberValidator,
            onSave: (value) => fields.updateConfigValues(field.id, {NumberConfig.minKey: num.tryParse(value)}),
          ),
        ),
        SizedBox(
          width: 120,
          child: _ConfigInput(
            label: 'Max',
            initialValue: config.max == null ? '' : formatPlainNumber(config.max!),
            validator: numberValidator,
            onSave: (value) => fields.updateConfigValues(field.id, {NumberConfig.maxKey: num.tryParse(value)}),
          ),
        ),
        SizedBox(
          width: 120,
          child: _ConfigInput(
            label: 'Decimals',
            initialValue: config.decimals?.toString() ?? '',
            validator: (value) => switch (int.tryParse(value)) {
              _ when value.isEmpty => null,
              final decimals? when decimals >= 0 && decimals <= 20 => null,
              _ => 'Enter 0 to 20',
            },
            onSave: (value) => fields.updateConfigValues(field.id, {NumberConfig.decimalsKey: int.tryParse(value)}),
          ),
        ),
      ],
    );
  }
}

/// A labeled input that saves on submit and on losing focus, but only
/// once [validator] accepts the value.
class _ConfigInput extends StatefulWidget {
  const _ConfigInput({
    required this.label,
    required this.initialValue,
    required this.validator,
    required this.onSave,
    this.placeholder,
  });

  final String label;
  final String? placeholder;
  final String initialValue;
  final String? Function(String value) validator;
  final ValueChanged<String> onSave;

  @override
  State<_ConfigInput> createState() => _ConfigInputState();
}

class _ConfigInputState extends State<_ConfigInput> {
  late final _controller = TextEditingController(text: widget.initialValue);
  late final _focusNode = FocusNode()..addListener(_onFocusChanged);

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (!_focusNode.hasFocus) _save(_controller.text);
  }

  void _save(String value) {
    final trimmed = value.trim();
    if (widget.validator(trimmed) == null) widget.onSave(trimmed);
  }

  @override
  Widget build(BuildContext context) {
    return ShadInputFormField(
      label: Text(widget.label),
      controller: _controller,
      focusNode: _focusNode,
      placeholder: widget.placeholder == null ? null : Text(widget.placeholder!),
      autovalidateMode: AutovalidateMode.always,
      validator: (value) => widget.validator(value.trim()),
      onSubmitted: _save,
    );
  }
}
