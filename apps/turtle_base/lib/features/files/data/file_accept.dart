import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;

/// Which files a files field takes, in the syntax of HTML's `accept`
/// attribute: MIME types (`application/pdf`), MIME wildcards
/// (`image/*`) and extensions (`.xml`). Empty takes any file.
class FileAccept {
  const FileAccept(this.patterns);

  static const any = FileAccept([]);
  static const images = FileAccept(['image/*']);
  static const pdf = FileAccept(['application/pdf']);

  /// Parses a comma-separated list, as typed into the field settings.
  factory FileAccept.parse(String text) => FileAccept([
    for (final part in text.split(','))
      if (part.trim().toLowerCase() case final pattern when pattern.isNotEmpty) pattern,
  ]);

  final List<String> patterns;

  bool get isAny => patterns.isEmpty;

  /// Whether a file of [mimeType] named [fileName] fits.
  bool accepts({required String mimeType, required String fileName}) {
    if (isAny) return true;
    final mime = mimeType.toLowerCase();
    final extension = p.extension(fileName).toLowerCase();
    return patterns.any(
      (pattern) => switch (pattern) {
        _ when pattern.startsWith('.') => extension == pattern,
        _ when pattern.endsWith('/*') => mime.startsWith(pattern.substring(0, pattern.length - 1)),
        _ => mime == pattern,
      },
    );
  }

  /// Only image types - so the file dialog can offer the platform's
  /// image picker (e.g. the gallery on Android).
  bool get isImagesOnly => !isAny && patterns.every((pattern) => pattern.startsWith('image/'));

  /// Extensions (without dot) for the file dialog's filter, null for no
  /// filter - when [isAny], or when a wildcard other than image/* can't
  /// be listed as extensions.
  List<String>? get dialogExtensions {
    if (isAny) return null;
    final extensions = <String>{};
    for (final pattern in patterns) {
      if (pattern.startsWith('.')) {
        extensions.add(pattern.substring(1));
      } else if (pattern == 'image/*') {
        extensions.addAll(_imageExtensions);
      } else if (pattern.endsWith('/*')) {
        return null;
      } else if (extensionFromMime(pattern) case final extension?) {
        extensions.add(extension);
      }
    }
    return extensions.isEmpty ? null : extensions.toList();
  }

  String toText() => patterns.join(', ');

  @override
  bool operator ==(Object other) =>
      other is FileAccept && other.patterns.length == patterns.length && other.patterns.every(patterns.contains);

  @override
  int get hashCode => Object.hashAllUnordered(patterns);
}

const _imageExtensions = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'heic', 'heif', 'bmp', 'tif', 'tiff', 'svg'];
