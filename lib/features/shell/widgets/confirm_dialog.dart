import 'package:flutter/material.dart';

/// Shows a Yes/No confirmation dialog, true if the user confirmed.
///
/// The default message is honest about there being no Trash UI yet
/// (see PLAN.md "Später/v2") - soft-delete alone would otherwise imply
/// a safety net the app doesn't actually expose yet.
Future<bool> confirmDelete(
  BuildContext context, {
  required String title,
  String message = "This can't be undone from the app yet - there's no Trash UI to restore it from.",
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      );
    },
  );
  return result ?? false;
}
