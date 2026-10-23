import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:turtle_base/features/tables/data/field_conversion.dart';

/// Whether [plan] affects stored values enough to ask first - a rewrite
/// of existing values, or values that won't fit the new type.
bool needsTypeChangeConfirmation(TypeChangePlan plan) =>
    plan.invalidCount > 0 || (plan.mode == ConversionMode.rewrite && plan.valueCount > 0);

/// Previews a type change (see FieldsRepository.planTypeChange), true
/// if the user confirmed it.
Future<bool> confirmTypeChange(BuildContext context, {required TypeChangePlan plan, required String typeLabel}) async {
  final lines = [
    if (plan.mode == ConversionMode.rewrite)
      '${_values(plan.valueCount)} will be converted to $typeLabel.'
    else
      'Existing values are kept as they are.',
    if (plan.invalidCount > 0)
      '${plan.invalidCount} of ${_values(plan.valueCount)} won\'t fit $typeLabel '
          '(e.g. ${plan.invalidSamples.map((s) => '"$s"').join(', ')}) and will be flagged as invalid'
          '${plan.mode == ConversionMode.rewrite ? ', kept as plain text' : ''}.',
  ];
  final result = await showShadDialog<bool>(
    context: context,
    builder: (context) {
      return ShadDialog.alert(
        title: Text('Change type to $typeLabel?'),
        description: Text(lines.join('\n\n')),
        actions: [
          ShadButton.outline(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          ShadButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Change type')),
        ],
      );
    },
  );
  return result ?? false;
}

String _values(int count) => count == 1 ? '1 value' : '$count values';
