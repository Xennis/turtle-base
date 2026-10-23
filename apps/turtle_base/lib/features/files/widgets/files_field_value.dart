import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:turtle_base/core/app_scope.dart';
import 'package:turtle_base/core/database/app_database.dart';
import 'package:turtle_base/features/files/data/file_accept.dart';
import 'package:turtle_base/features/files/widgets/attachment_thumbnail.dart';
import 'package:turtle_base/features/files/widgets/attachment_viewer.dart';
import 'package:turtle_base/features/files/widgets/pick_files.dart';

/// A files field's value on the entry's page: a preview per attachment
/// (tap to open, menu to move or remove) and an add button while the
/// field has room.
class FilesFieldValue extends StatelessWidget {
  const FilesFieldValue({
    super.key,
    required this.pageId,
    required this.fieldId,
    required this.accept,
    required this.maxFiles,
  });

  final String pageId;
  final String fieldId;
  final FileAccept accept;
  final int? maxFiles;

  static const _previewSize = 72.0;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return StreamBuilder<List<Attachment>>(
      stream: scope.attachments.watchInField(pageId, fieldId),
      builder: (context, snapshot) {
        final attachments = snapshot.data ?? const <Attachment>[];
        final room = maxFiles == null ? null : maxFiles! - attachments.length;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (index, attachment) in attachments.indexed)
                _AttachmentTile(
                  attachment: attachment,
                  size: _previewSize,
                  onMove: (offset) {
                    final ids = [for (final a in attachments) a.id];
                    final target = (index + offset).clamp(0, ids.length - 1);
                    ids.insert(target, ids.removeAt(index));
                    scope.attachments.reorderAll(ids);
                  },
                  canMoveBack: index > 0,
                  canMoveForward: index < attachments.length - 1,
                ),
              if (room == null || room > 0)
                Tooltip(
                  message: 'Add file',
                  child: SizedBox.square(
                    dimension: _previewSize,
                    child: ShadButton.outline(
                      padding: EdgeInsets.zero,
                      onPressed: () =>
                          pickAndAttach(context, pageId: pageId, fieldId: fieldId, accept: accept, maxCount: room),
                      child: const Icon(Icons.add),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _AttachmentTile extends StatelessWidget {
  const _AttachmentTile({
    required this.attachment,
    required this.size,
    required this.onMove,
    required this.canMoveBack,
    required this.canMoveForward,
  });

  final Attachment attachment;
  final double size;
  final ValueChanged<int> onMove;
  final bool canMoveBack;
  final bool canMoveForward;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return Tooltip(
      message: '${attachment.name} (${formatFileSize(attachment.size)})',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => openAttachment(context, attachment),
          child: Stack(
            children: [
              AttachmentThumbnail(attachment: attachment, size: size),
              Positioned(
                top: 2,
                right: 2,
                child: PopupMenuButton<_TileAction>(
                  tooltip: 'More',
                  padding: EdgeInsets.zero,
                  iconSize: 16,
                  style: IconButton.styleFrom(
                    backgroundColor: ShadTheme.of(context).colorScheme.background.withValues(alpha: 0.85),
                    minimumSize: const Size.square(24),
                    maximumSize: const Size.square(24),
                    padding: EdgeInsets.zero,
                  ),
                  icon: const Icon(Icons.more_horiz),
                  onSelected: (action) => switch (action) {
                    _TileAction.open => openExternally(context, attachment),
                    _TileAction.moveBack => onMove(-1),
                    _TileAction.moveForward => onMove(1),
                    _TileAction.remove => scope.attachments.softDelete(attachment.id),
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(value: _TileAction.open, child: Text('Open with…')),
                    if (canMoveBack) const PopupMenuItem(value: _TileAction.moveBack, child: Text('Move left')),
                    if (canMoveForward) const PopupMenuItem(value: _TileAction.moveForward, child: Text('Move right')),
                    const PopupMenuItem(value: _TileAction.remove, child: Text('Remove')),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _TileAction { open, moveBack, moveForward, remove }

/// A row of small previews of a files field's value, e.g. in a grid
/// cell - as many as fit up to [max], then "+N".
class AttachmentStrip extends StatelessWidget {
  const AttachmentStrip({super.key, required this.pageId, required this.fieldId, this.size = 28, this.max = 3});

  final String pageId;
  final String fieldId;
  final double size;
  final int max;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Attachment>>(
      stream: AppScope.of(context).attachments.watchInField(pageId, fieldId),
      builder: (context, snapshot) {
        final attachments = snapshot.data ?? const <Attachment>[];
        if (attachments.isEmpty) return const SizedBox.shrink();
        final shown = attachments.take(max).toList();
        final more = attachments.length - shown.length;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final attachment in shown)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Tooltip(
                  message: attachment.name,
                  child: AttachmentThumbnail(attachment: attachment, size: size, borderRadius: 4),
                ),
              ),
            if (more > 0) Text('+$more', style: ShadTheme.of(context).textTheme.muted),
          ],
        );
      },
    );
  }
}
