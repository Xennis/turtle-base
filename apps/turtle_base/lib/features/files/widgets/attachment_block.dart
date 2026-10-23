import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:turtle_base/core/app_scope.dart';
import 'package:turtle_base/core/database/app_database.dart';
import 'package:turtle_base/features/files/data/attachments_repository.dart';
import 'package:turtle_base/features/files/data/file_accept.dart';
import 'package:turtle_base/features/files/widgets/attachment_thumbnail.dart';
import 'package:turtle_base/features/files/widgets/attachment_viewer.dart';
import 'package:turtle_base/features/files/widgets/pick_files.dart';
import 'package:turtle_base/features/files/widgets/stored_file_builder.dart';
import 'package:turtle_base/packages/file_store/file_store.dart';

/// A file in a page's rich text, referencing an attachment of the page
/// (see block_sync.dart for keeping the two in step). Shown as the image
/// for an image, as a file row for anything else.
class AttachmentBlockKeys {
  const AttachmentBlockKeys._();

  static const type = 'attachment';
  static const attachmentId = 'attachmentId';
}

Node attachmentNode(String attachmentId) =>
    Node(type: AttachmentBlockKeys.type, attributes: {AttachmentBlockKeys.attachmentId: attachmentId});

/// Slash menu entries replacing appflowy's own image entry - which
/// stores a local file path that no other device has.
List<SelectionMenuItem> attachmentSelectionMenuItems({required String pageId}) => [
  _pickItem(
    pageId: pageId,
    name: 'Image',
    icon: Icons.image_outlined,
    accept: FileAccept.images,
    keywords: ['image', 'photo', 'picture'],
  ),
  _pickItem(
    pageId: pageId,
    name: 'File',
    icon: Icons.attach_file,
    accept: FileAccept.any,
    keywords: ['file', 'attachment', 'upload'],
  ),
];

SelectionMenuItem _pickItem({
  required String pageId,
  required String name,
  required IconData icon,
  required FileAccept accept,
  required List<String> keywords,
}) {
  return SelectionMenuItem(
    getName: () => name,
    icon: (editorState, isSelected, style) => Icon(
      icon,
      size: 18,
      color: isSelected ? style.selectionMenuItemSelectedIconColor : style.selectionMenuItemIconColor,
    ),
    keywords: keywords,
    handler: (editorState, menuService, context) async {
      final selection = editorState.selection;
      final ids = await pickAndAttach(context, pageId: pageId, accept: accept);
      if (ids.isEmpty || selection == null) return;
      final transaction = editorState.transaction;
      final current = editorState.getNodeAtPath(selection.end.path);
      // Replaces the empty paragraph the slash was typed into, like
      // appflowy's own block entries do.
      final replace = current != null && current.type == ParagraphBlockKeys.type && (current.delta?.isEmpty ?? false);
      final path = replace ? selection.end.path : selection.end.path.next;
      transaction.insertNodes(path, [for (final id in ids) attachmentNode(id)]);
      if (replace) transaction.deleteNode(current);
      await editorState.apply(transaction);
    },
  );
}

class AttachmentBlockComponentBuilder extends BlockComponentBuilder {
  AttachmentBlockComponentBuilder({required this.editorState, super.configuration});

  final EditorState editorState;

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    return _AttachmentBlock(
      key: node.key,
      node: node,
      editorState: editorState,
      configuration: configuration,
      showActions: showActions(node),
      actionBuilder: (context, state) => actionBuilder(blockComponentContext, state),
      actionTrailingBuilder: (context, state) => actionTrailingBuilder(blockComponentContext, state),
    );
  }

  @override
  BlockComponentValidate get validate =>
      (node) => node.delta == null && node.children.isEmpty;
}

class _AttachmentBlock extends BlockComponentStatefulWidget {
  const _AttachmentBlock({
    super.key,
    required super.node,
    required this.editorState,
    super.showActions,
    super.actionBuilder,
    super.actionTrailingBuilder,
    super.configuration = const BlockComponentConfiguration(),
  });

  final EditorState editorState;

  @override
  State<_AttachmentBlock> createState() => _AttachmentBlockState();
}

/// Selectable as one unit, like appflowy's image block.
class _AttachmentBlockState extends State<_AttachmentBlock> with SelectableMixin, BlockComponentConfigurable {
  @override
  BlockComponentConfiguration get configuration => widget.configuration;

  @override
  Node get node => widget.node;

  final _contentKey = GlobalKey();

  RenderBox? get _renderBox => context.findRenderObject() as RenderBox?;

  @override
  Widget build(BuildContext context) {
    final editorState = widget.editorState;
    final attachmentId = node.attributes[AttachmentBlockKeys.attachmentId] as String?;
    Widget child = Padding(
      key: _contentKey,
      padding: padding,
      child: attachmentId == null
          ? const _Missing()
          : StreamBuilder<Attachment?>(
              stream: AppScope.of(context).attachments.watchById(attachmentId),
              builder: (context, snapshot) {
                final attachment = snapshot.data;
                if (attachment == null) {
                  return snapshot.connectionState == ConnectionState.waiting
                      ? const SizedBox(height: 48)
                      : const _Missing();
                }
                return attachment.isImage ? _ImageContent(attachment: attachment) : _FileRow(attachment: attachment);
              },
            ),
    );

    child = BlockSelectionContainer(
      node: node,
      delegate: this,
      listenable: editorState.selectionNotifier,
      remoteSelection: editorState.remoteSelections,
      blockColor: editorState.editorStyle.selectionColor,
      supportTypes: const [BlockSelectionType.block],
      child: child,
    );

    if (widget.showActions && widget.actionBuilder != null) {
      child = BlockComponentActionWrapper(
        node: node,
        actionBuilder: widget.actionBuilder!,
        actionTrailingBuilder: widget.actionTrailingBuilder,
        child: child,
      );
    }
    return child;
  }

  @override
  Position start() => Position(path: widget.node.path, offset: 0);

  @override
  Position end() => Position(path: widget.node.path, offset: 1);

  @override
  Position getPositionInOffset(Offset start) => end();

  @override
  bool get shouldCursorBlink => false;

  @override
  CursorStyle get cursorStyle => CursorStyle.cover;

  @override
  Rect getBlockRect({bool shiftWithBaseOffset = false}) {
    final box = _contentKey.currentContext?.findRenderObject();
    return box is RenderBox ? Offset.zero & box.size : Rect.zero;
  }

  @override
  Rect? getCursorRectInPosition(Position position, {bool shiftWithBaseOffset = false}) {
    final size = _renderBox?.size;
    return size == null ? null : Rect.fromLTWH(-size.width / 2.0, 0, size.width, size.height);
  }

  @override
  List<Rect> getRectsInSelection(Selection selection, {bool shiftWithBaseOffset = false}) {
    final parentBox = context.findRenderObject();
    final box = _contentKey.currentContext?.findRenderObject();
    if (parentBox is RenderBox && box is RenderBox) {
      return [box.localToGlobal(Offset.zero, ancestor: parentBox) & box.size];
    }
    final size = _renderBox?.size;
    return size == null ? [] : [Offset.zero & size];
  }

  @override
  Selection getSelectionInRange(Offset start, Offset end) =>
      Selection.single(path: widget.node.path, startOffset: 0, endOffset: 1);

  @override
  Offset localToGlobal(Offset offset, {bool shiftWithBaseOffset = false}) => _renderBox!.localToGlobal(offset);
}

/// The image at its own aspect ratio, at most [_maxHeight] tall - the
/// thumbnail until the original is there.
class _ImageContent extends StatelessWidget {
  const _ImageContent({required this.attachment});

  final Attachment attachment;

  static const _maxHeight = 420.0;

  @override
  Widget build(BuildContext context) {
    final files = AppScope.of(context).files;
    final hash = attachment.fileHash;
    final width = attachment.width;
    final height = attachment.height;
    final aspectRatio = width != null && height != null && height > 0 ? width / height : 4 / 3;
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: _maxHeight, maxWidth: _maxHeight * aspectRatio),
        child: AspectRatio(
          aspectRatio: aspectRatio,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => openAttachment(context, attachment),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: StoredFileBuilder(
                  names: [hash, FileStore.thumbnailNameOf(hash)],
                  builder: (context) {
                    final file = files.originalIfPresent(hash) ?? files.thumbnailIfPresent(hash);
                    if (file == null) return ColoredBox(color: ShadTheme.of(context).colorScheme.muted);
                    return LayoutBuilder(
                      builder: (context, constraints) => Image.file(
                        file,
                        key: ValueKey(file.path),
                        fit: BoxFit.cover,
                        cacheWidth: (constraints.maxWidth * MediaQuery.devicePixelRatioOf(context)).round(),
                        errorBuilder: (context, _, _) => FileTypeIcon(attachment: attachment, size: 64),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({required this.attachment});

  final Attachment attachment;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => openAttachment(context, attachment),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              border: Border.all(color: theme.colorScheme.border),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AttachmentThumbnail(attachment: attachment, size: 36),
                const SizedBox(width: 12),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(attachment.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.small),
                      Text(formatFileSize(attachment.size), style: theme.textTheme.muted.copyWith(fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// E.g. a block synced in before its attachment row.
class _Missing extends StatelessWidget {
  const _Missing();

  @override
  Widget build(BuildContext context) {
    return Text('File not available', style: ShadTheme.of(context).textTheme.muted);
  }
}
