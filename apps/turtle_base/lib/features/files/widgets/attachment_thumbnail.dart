import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:turtle_base/core/app_scope.dart';
import 'package:turtle_base/core/database/app_database.dart';
import 'package:turtle_base/features/files/data/attachments_repository.dart';
import 'package:turtle_base/features/files/widgets/stored_file_builder.dart';
import 'package:turtle_base/packages/file_store/file_store.dart';

/// A small preview of an attachment: an image's thumbnail - or, without
/// one (not synced yet, or a format without thumbnails), its original
/// downscaled - and an icon for every other file.
class AttachmentThumbnail extends StatelessWidget {
  const AttachmentThumbnail({super.key, required this.attachment, required this.size, this.borderRadius = 6});

  final Attachment attachment;
  final double size;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final files = AppScope.of(context).files;
    final hash = attachment.fileHash;
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox.square(
        dimension: size,
        child: !attachment.isImage
            ? FileTypeIcon(attachment: attachment, size: size)
            : StoredFileBuilder(
                names: [FileStore.thumbnailNameOf(hash), hash],
                builder: (context) {
                  final file = files.thumbnailIfPresent(hash) ?? files.originalIfPresent(hash);
                  if (file == null) return FileTypeIcon(attachment: attachment, size: size);
                  return Image.file(
                    file,
                    fit: BoxFit.cover,
                    // Decoded at the size shown - the original can be
                    // many megapixels.
                    cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
                    errorBuilder: (context, _, _) => FileTypeIcon(attachment: attachment, size: size),
                  );
                },
              ),
      ),
    );
  }
}

/// An image attachment filling its parent, cropped - e.g. a tile's
/// cover. Shows a muted area until the image is there.
class AttachmentCover extends StatelessWidget {
  const AttachmentCover({super.key, required this.attachment});

  final Attachment attachment;

  @override
  Widget build(BuildContext context) {
    final files = AppScope.of(context).files;
    final hash = attachment.fileHash;
    final placeholder = ColoredBox(color: ShadTheme.of(context).colorScheme.muted);
    return LayoutBuilder(
      builder: (context, constraints) => StoredFileBuilder(
        names: [FileStore.thumbnailNameOf(hash), hash],
        builder: (context) {
          final file = files.thumbnailIfPresent(hash) ?? files.originalIfPresent(hash);
          if (file == null) return placeholder;
          return Image.file(
            file,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            cacheWidth: constraints.hasBoundedWidth
                ? (constraints.maxWidth * MediaQuery.devicePixelRatioOf(context)).round()
                : null,
            errorBuilder: (context, _, _) => placeholder,
          );
        },
      ),
    );
  }
}

/// A file's type as an icon on a muted square, with its extension
/// below where there's room.
class FileTypeIcon extends StatelessWidget {
  const FileTypeIcon({super.key, required this.attachment, required this.size});

  final Attachment attachment;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final extension = p.extension(attachment.name).replaceFirst('.', '').toUpperCase();
    return ColoredBox(
      color: theme.colorScheme.muted,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(fileIconFor(attachment.mimeType), size: size * 0.45, color: theme.colorScheme.mutedForeground),
          if (size >= 56 && extension.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                extension,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.muted.copyWith(fontSize: 10),
              ),
            ),
        ],
      ),
    );
  }
}

IconData fileIconFor(String mimeType) {
  if (mimeType.startsWith('image/')) return Icons.image_outlined;
  if (mimeType.startsWith('video/')) return Icons.movie_outlined;
  if (mimeType.startsWith('audio/')) return Icons.audiotrack_outlined;
  if (mimeType == 'application/pdf') return Icons.picture_as_pdf_outlined;
  if (mimeType.contains('zip') || mimeType.contains('compressed')) return Icons.folder_zip_outlined;
  if (mimeType.startsWith('text/') || mimeType.contains('xml') || mimeType.contains('json')) {
    return Icons.description_outlined;
  }
  return Icons.insert_drive_file_outlined;
}

/// E.g. "1.2 MB".
String formatFileSize(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return unit == 0 ? '$bytes B' : '${value.toStringAsFixed(value < 10 ? 1 : 0)} ${units[unit]}';
}
