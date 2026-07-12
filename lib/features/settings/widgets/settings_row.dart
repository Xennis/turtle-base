import 'package:flutter/material.dart';

/// A label on the left, its control on the right - one row per
/// setting, so further settings just add another row in the same Card.
class SettingsRow extends StatelessWidget {
  const SettingsRow({super.key, required this.label, required this.control});

  final String label;
  final Widget control;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          control,
        ],
      ),
    );
  }
}
