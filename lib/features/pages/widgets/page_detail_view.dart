import 'dart:async';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/foundation.dart';
// Flutter's own `Page` (Navigator 2.0) collides with our `Page` data class.
import 'package:flutter/material.dart' hide Page;
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:turtle_base/core/app_scope.dart';
import 'package:turtle_base/features/pages/widgets/block_document.dart';
import 'package:turtle_base/features/pages/widgets/block_sync.dart';
import 'package:turtle_base/features/pages/widgets/page_properties_header.dart';
import 'package:turtle_base/features/shell/widgets/confirm_dialog.dart';

/// Shows a page's title and its blocks, editable. Works for both
/// freestanding pages and collection entries - they're the same
/// underlying thing (see ARCHITECTURE.md).
///
/// The editor state is loaded once and kept alive across rebuilds
/// (rather than reconstructed from the database like CollectionView's
/// grid) - rebuilding it on every change to the underlying data would
/// reset the user's cursor/selection on every keystroke, since editing
/// itself is what causes those changes. There's no external writer to
/// race against yet (sync is a later phase), so "load once, edit live,
/// write out" is enough for now.
class PageDetailView extends StatefulWidget {
  const PageDetailView({super.key, required this.pageId, this.onOpenCollection});

  final String pageId;

  /// Called with the entry's collection id when the user taps the back
  /// button - only shown for collection entries, not freestanding
  /// pages (see build()).
  final ValueChanged<String>? onOpenCollection;

  @override
  State<PageDetailView> createState() => _PageDetailViewState();
}

class _PageDetailViewState extends State<PageDetailView> {
  EditorState? _editorState;
  TextEditingController? _titleController;
  FocusNode? _titleFocusNode;
  StreamSubscription<EditorTransactionValue>? _transactionSubscription;
  Timer? _debounceTimer;
  bool _initializedOnce = false;
  String? _collectionId;
  String? _icon;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initializedOnce) {
      _initializedOnce = true;
      _initialize();
    }
  }

  @override
  void didUpdateWidget(covariant PageDetailView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pageId != widget.pageId) {
      _disposeEditingState();
      _initialize();
    }
  }

  @override
  void dispose() {
    _disposeEditingState();
    super.dispose();
  }

  void _disposeEditingState() {
    _debounceTimer?.cancel();
    _transactionSubscription?.cancel();
    _editorState?.dispose();
    _titleController?.dispose();
    _titleFocusNode?.dispose();
    _editorState = null;
    _titleController = null;
    _titleFocusNode = null;
    _collectionId = null;
    _icon = null;
  }

  Future<void> _initialize() async {
    final scope = AppScope.of(context);
    final (page, blocks) = await (
      scope.pages.watchById(widget.pageId).first,
      scope.blocks.watchAllInPage(widget.pageId).first,
    ).wait;
    if (!mounted) return;

    final titleController = TextEditingController(text: page.title);
    final titleFocusNode = FocusNode();
    titleFocusNode.addListener(() {
      if (!titleFocusNode.hasFocus) {
        _saveTitle(scope, titleController.text);
      }
    });

    final editorState = EditorState(document: buildDocument(blocks))
      ..editable = true;
    final transactionSubscription = editorState.transactionStream.listen((event) {
      final (time, _, _) = event;
      if (time == TransactionTime.after) {
        _scheduleSync(scope, editorState);
      }
    });

    setState(() {
      _titleController = titleController;
      _titleFocusNode = titleFocusNode;
      _editorState = editorState;
      _transactionSubscription = transactionSubscription;
      _collectionId = page.collectionId;
      _icon = page.icon;
    });
  }

  void _saveTitle(AppScope scope, String value) {
    scope.pages.rename(widget.pageId, value.trim());
  }

  /// No dedicated edit page exists for a page (unlike collections) -
  /// the icon itself, shown before the title, is the affordance for
  /// changing it.
  Future<void> _pickIcon(BuildContext context) async {
    final scope = AppScope.of(context);
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => SizedBox(
        height: 320,
        child: EmojiPicker(
          onEmojiSelected: (category, emoji) {
            scope.pages.setIcon(widget.pageId, emoji.emoji);
            setState(() => _icon = emoji.emoji);
            Navigator.of(context).pop();
          },
        ),
      ),
    );
  }

  Future<void> _deleteEntry(BuildContext context, String collectionId) async {
    final scope = AppScope.of(context);
    final confirmed = await confirmDelete(context, title: 'Delete this entry?');
    if (!confirmed) return;
    await scope.pages.softDelete(widget.pageId);
    if (!mounted) return;
    widget.onOpenCollection?.call(collectionId);
  }

  void _scheduleSync(AppScope scope, EditorState editorState) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () async {
      final currentBlocks = await scope.blocks.watchAllInPage(widget.pageId).first;
      await syncBlocksFromDocument(
        blocks: scope.blocks,
        pageId: widget.pageId,
        document: editorState.document,
        currentBlocks: currentBlocks,
      );
    });
  }

  /// AppFlowyEditor doesn't follow the ambient theme on its own - its
  /// default EditorStyle hardcodes black text, which made the page body
  /// unreadable in dark mode. Both platform variants get the shadcn
  /// tokens; the mobile one additionally styles the selection handles.
  EditorStyle _editorStyle(BuildContext context) {
    final colors = ShadTheme.of(context).colorScheme;
    final textStyleConfiguration = TextStyleConfiguration(
      text: TextStyle(fontSize: 16, height: 1.5, color: colors.foreground),
    );
    final isMobile =
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
    if (isMobile) {
      return EditorStyle.mobile(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        cursorColor: colors.primary,
        dragHandleColor: colors.primary,
        selectionColor: colors.selection,
        textStyleConfiguration: textStyleConfiguration,
      );
    }
    return EditorStyle.desktop(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      cursorColor: colors.primary,
      selectionColor: colors.selection,
      textStyleConfiguration: textStyleConfiguration,
    );
  }

  @override
  Widget build(BuildContext context) {
    final editorState = _editorState;
    if (editorState == null) {
      return Center(
        child: CircularProgressIndicator(
          color: ShadTheme.of(context).colorScheme.mutedForeground,
        ),
      );
    }
    final collectionId = _collectionId;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (collectionId != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
            child: Row(
              children: [
                Tooltip(
                  message: 'Back to collection',
                  child: ShadIconButton.ghost(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => widget.onOpenCollection?.call(collectionId),
                  ),
                ),
                Tooltip(
                  message: 'Delete entry',
                  child: ShadIconButton.ghost(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _deleteEntry(context, collectionId),
                  ),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              InkWell(
                onTap: () => _pickIcon(context),
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: _icon != null
                      ? Text(_icon!, style: const TextStyle(fontSize: 28))
                      : const Icon(Icons.add_reaction_outlined),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: ShadInput(
                  controller: _titleController,
                  focusNode: _titleFocusNode,
                  style: ShadTheme.of(context).textTheme.h3,
                  decoration: ShadDecoration.none,
                  placeholder: const Text('Untitled'),
                  onSubmitted: (value) => _saveTitle(AppScope.of(context), value),
                ),
              ),
            ],
          ),
        ),
        if (collectionId != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: PagePropertiesHeader(pageId: widget.pageId, collectionId: collectionId),
          ),
        Expanded(
          child: AppFlowyEditor(
            editorState: editorState,
            editorStyle: _editorStyle(context),
          ),
        ),
      ],
    );
  }
}
