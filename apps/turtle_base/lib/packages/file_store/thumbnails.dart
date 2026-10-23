import 'dart:io';

import 'package:image/image.dart' as img;

/// Longest edge of a thumbnail - enough for grid cells, tiles and
/// high-density lists, the full view uses the original.
const thumbnailMaxEdge = 512;

/// Larger images aren't decoded for a thumbnail: the decoded pixels
/// would take several times the file size in memory.
const thumbnailMaxSourceBytes = 50 * 1024 * 1024;

class ImageSize {
  const ImageSize({required this.width, required this.height});

  final int width;
  final int height;
}

/// Writes a JPEG thumbnail of the image at [sourcePath] to [targetPath]
/// and returns the image's size - with its EXIF orientation applied,
/// so a portrait phone photo is portrait in both. Null (and nothing
/// written) when the file isn't an image the image package can decode,
/// e.g. HEIC, or is too large.
///
/// Synchronous and CPU-heavy, meant to run via Isolate.run.
ImageSize? writeThumbnail(String sourcePath, String targetPath) {
  final source = File(sourcePath);
  if (source.lengthSync() > thumbnailMaxSourceBytes) return null;
  final bytes = source.readAsBytesSync();
  final decoder = img.findDecoderForData(bytes);
  // frame 0 - an animated GIF would otherwise decode every frame.
  final decoded = decoder?.decode(bytes, frame: 0);
  if (decoded == null) return null;

  final image = img.bakeOrientation(decoded);
  final landscape = image.width >= image.height;
  final needsResize = (landscape ? image.width : image.height) > thumbnailMaxEdge;
  final thumbnail = needsResize
      ? img.copyResize(
          image,
          width: landscape ? thumbnailMaxEdge : null,
          height: landscape ? null : thumbnailMaxEdge,
          interpolation: img.Interpolation.average,
        )
      : image;
  File(targetPath).writeAsBytesSync(img.encodeJpg(thumbnail, quality: 80));
  return ImageSize(width: image.width, height: image.height);
}
