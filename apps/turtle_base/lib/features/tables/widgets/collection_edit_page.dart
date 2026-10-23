import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:turtle_base/core/app_scope.dart';
import 'package:turtle_base/core/database/app_database.dart';
import 'package:turtle_base/features/shell/widgets/confirm_dialog.dart';
import 'package:turtle_base/features/shell/widgets/emoji_picker_sheet.dart';
import 'package:turtle_base/features/tables/widgets/fields_editor.dart';

/// Shown in the same content area as CollectionView (see
/// AppShell/_MainContent) rather than pushed via Navigator, so the
/// sidebar stays visible. [onDone] goes back to the grid.
class CollectionEditPage extends StatefulWidget {
  const CollectionEditPage({super.key, required this.collectionId, required this.onDone, required this.onDeleted});

  final String collectionId;
  final VoidCallback onDone;

  /// Called after the collection itself is deleted - unlike [onDone],
  /// there's no grid left to go back to.
  final VoidCallback onDeleted;

  @override
  State<CollectionEditPage> createState() => _CollectionEditPageState();
}

class _CollectionEditPageState extends State<CollectionEditPage> {
  TextEditingController? _nameController;
  FocusNode? _nameFocusNode;
  TextEditingController? _titleFieldLabelController;
  FocusNode? _titleFieldLabelFocusNode;

  @override
  void dispose() {
    _nameController?.dispose();
    _nameFocusNode?.dispose();
    _titleFieldLabelController?.dispose();
    _titleFieldLabelFocusNode?.dispose();
    super.dispose();
  }

  void _saveName(String value, Future<void> Function(String) save) {
    final trimmed = value.trim();
    if (trimmed.isNotEmpty) save(trimmed);
  }

  /// Unlike _saveName, an empty value is valid here - it resets to the
  /// "Name" default instead of being ignored.
  void _saveTitleFieldLabel(String value) {
    final scope = AppScope.of(context);
    final trimmed = value.trim();
    scope.collections.setTitleFieldLabel(widget.collectionId, trimmed.isEmpty ? null : trimmed);
  }

  Future<void> _pickIcon(BuildContext context) async {
    final scope = AppScope.of(context);
    await showEmojiPickerSheet(context, onSelected: (emoji) => scope.collections.setIcon(widget.collectionId, emoji));
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return Scaffold(
      // Transparent so the unified window background shows through on
      // the wide layout (see AppShell/_WideShell); on the narrow layout
      // the ancestor Scaffold provides the background.
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: ShadIconButton.ghost(icon: const Icon(Icons.arrow_back), onPressed: widget.onDone),
        title: const Text('Edit collection'),
        actions: [
          Tooltip(
            // Distinct from the sidebar row's "Delete collection" -
            // both can be visible at once (sidebar stays visible while
            // editing a collection, see AppShell/_MainContent).
            message: 'Delete this collection',
            child: ShadIconButton.ghost(
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                final confirmed = await confirmDelete(context, title: 'Delete this collection?');
                if (!confirmed) return;
                await scope.collections.softDelete(widget.collectionId);
                widget.onDeleted();
              },
            ),
          ),
        ],
      ),
      body: StreamBuilder<Collection>(
        stream: scope.collections.watchById(widget.collectionId),
        builder: (context, collectionSnapshot) {
          final collection = collectionSnapshot.data;
          if (collection == null) {
            return const Center(child: CircularProgressIndicator());
          }
          _nameController ??= TextEditingController(text: collection.name);
          _nameFocusNode ??= FocusNode()
            ..addListener(() {
              if (!_nameFocusNode!.hasFocus) {
                _saveName(_nameController!.text, (name) => scope.collections.rename(widget.collectionId, name));
              }
            });
          _titleFieldLabelController ??= TextEditingController(text: collection.titleFieldLabel ?? '');
          _titleFieldLabelFocusNode ??= FocusNode()
            ..addListener(() {
              if (!_titleFieldLabelFocusNode!.hasFocus) {
                _saveTitleFieldLabel(_titleFieldLabelController!.text);
              }
            });

          final theme = ShadTheme.of(context);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Centered with a max width like SettingsPage, so inputs
              // don't stretch across the whole window on desktop.
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ShadCard(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Collection', style: theme.textTheme.h4),
                            const SizedBox(height: 12),
                            Text('Icon and name', style: theme.textTheme.small),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Tooltip(
                                  message: 'Pick emoji',
                                  child: ShadButton.outline(
                                    width: 40,
                                    padding: EdgeInsets.zero,
                                    onPressed: () => _pickIcon(context),
                                    child: collection.icon != null
                                        ? Text(collection.icon!, style: const TextStyle(fontSize: 20))
                                        : const Icon(Icons.add_reaction_outlined, size: 18),
                                  ),
                                ),
                                if (collection.icon != null)
                                  Tooltip(
                                    message: 'Remove icon',
                                    child: ShadIconButton.ghost(
                                      icon: const Icon(Icons.clear, size: 18),
                                      onPressed: () => scope.collections.setIcon(widget.collectionId, null),
                                    ),
                                  ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: ShadInput(
                                    controller: _nameController,
                                    focusNode: _nameFocusNode,
                                    onSubmitted: (value) =>
                                        _saveName(value, (name) => scope.collections.rename(widget.collectionId, name)),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            ShadInputFormField(
                              label: const Text('Name column label'),
                              description: const Text('The heading of the built-in column every entry has.'),
                              controller: _titleFieldLabelController,
                              focusNode: _titleFieldLabelFocusNode,
                              placeholder: const Text('Name'),
                              onSubmitted: _saveTitleFieldLabel,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      ShadCard(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text('Fields', style: theme.textTheme.h4),
                            const SizedBox(height: 4),
                            Text(
                              'Drag to reorder. The type decides how values are entered, checked and shown.',
                              style: theme.textTheme.muted,
                            ),
                            const SizedBox(height: 12),
                            FieldsEditor(collectionId: widget.collectionId, spaceId: collection.spaceId),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
