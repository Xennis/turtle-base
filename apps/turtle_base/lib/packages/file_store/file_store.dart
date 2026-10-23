import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:turtle_base/packages/file_store/thumbnails.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();
const _hashPrefix = 'sha256-';
const _thumbnailSuffix = '.thumb.jpg';

/// What [FileStore.import] found out about a file.
class StoredFile {
  const StoredFile({required this.hash, required this.mimeType, required this.size, this.width, this.height});

  /// The file's name in the store, `sha256-<hex>` of its content.
  final String hash;
  final String mimeType;
  final int size;
  final int? width;
  final int? height;
}

/// Content-addressed files on disk, flat in one directory: each file
/// named by the hash of its content, plus an optional JPEG thumbnail
/// next to it. Knows nothing of attachments or sync - see
/// `.local/FILES.md`.
///
/// Writes go to `tmp/` first and are renamed into place, so a file
/// under its final name is always complete.
class FileStore {
  FileStore(String path) : directory = Directory(path);

  final Directory directory;

  final _stored = StreamController<String>.broadcast();

  /// The names of files as they land, e.g. after a download - for views
  /// waiting on one.
  Stream<String> get onStored => _stored.stream;

  static String thumbnailNameOf(String hash) => '$hash$_thumbnailSuffix';

  static bool isThumbnailName(String name) => name.endsWith(_thumbnailSuffix);

  /// Whether [name] can be a file of this store - guards against names
  /// from elsewhere (e.g. a sync folder) escaping the directory.
  static bool isValidName(String name) {
    final hash = isThumbnailName(name) ? name.substring(0, name.length - _thumbnailSuffix.length) : name;
    return RegExp(r'^sha256-[0-9a-f]{64}$').hasMatch(hash);
  }

  File fileOf(String name) => File(p.join(directory.path, name));

  File? originalIfPresent(String hash) => _ifPresent(hash);

  File? thumbnailIfPresent(String hash) => _ifPresent(thumbnailNameOf(hash));

  File? _ifPresent(String name) {
    final file = fileOf(name);
    return file.existsSync() ? file : null;
  }

  /// The names of all files (originals and thumbnails) present.
  Future<Set<String>> names() async {
    if (!await directory.exists()) return {};
    return {
      await for (final entity in directory.list())
        if (entity is File && isValidName(p.basename(entity.path))) p.basename(entity.path),
    };
  }

  /// Copies [source] into the store, hashing it on the way, and writes
  /// a thumbnail if it's an image. Importing the same content twice is
  /// harmless, it's stored once.
  Future<StoredFile> import(File source) async {
    final tmp = await _tmpFile();
    final hash = await Isolate.run(() => _copyHashing(source.path, tmp.path));
    final target = fileOf(hash);
    if (await target.exists()) {
      await tmp.delete();
    } else {
      await tmp.rename(target.path);
    }

    final size = await target.length();
    final mimeType = await _mimeTypeOf(target, nameHint: source.path);
    ImageSize? image;
    if (mimeType.startsWith('image/')) {
      final thumbnailTmp = await _tmpFile();
      final targetPath = target.path;
      try {
        image = await Isolate.run(() => writeThumbnail(targetPath, thumbnailTmp.path));
      } catch (e) {
        // A corrupt image is still a file worth keeping, just without
        // a thumbnail.
        debugPrint('[files] no thumbnail for $hash: $e');
      }
      if (image != null) await thumbnailTmp.rename(fileOf(thumbnailNameOf(hash)).path);
    }
    _stored.add(hash);
    return StoredFile(hash: hash, mimeType: mimeType, size: size, width: image?.width, height: image?.height);
  }

  /// Stores downloaded bytes under [name]. An original is checked
  /// against its hash and rejected with a [FormatException] when it
  /// doesn't match; a thumbnail is derived, so it can't be checked.
  Future<void> put(String name, Stream<List<int>> bytes) async {
    if (!isValidName(name)) throw ArgumentError.value(name, 'name', 'not a file store name');
    final tmp = await _tmpFile();
    final sink = tmp.openWrite();
    final digest = _DigestSink();
    final hasher = sha256.startChunkedConversion(digest);
    try {
      await for (final chunk in bytes) {
        sink.add(chunk);
        hasher.add(chunk);
      }
    } finally {
      await sink.close();
      hasher.close();
    }
    if (!isThumbnailName(name) && '$_hashPrefix${digest.value}' != name) {
      await tmp.delete();
      throw FormatException('Downloaded content does not match its hash', name);
    }
    await tmp.rename(fileOf(name).path);
    _stored.add(name);
  }

  Future<File> _tmpFile() async {
    final tmpDir = Directory(p.join(directory.path, 'tmp'));
    await tmpDir.create(recursive: true);
    return File(p.join(tmpDir.path, _uuid.v4()));
  }

  /// From the content's magic number first, the name's extension only
  /// as a fallback - a renamed file can't pass for another type.
  static Future<String> _mimeTypeOf(File file, {required String nameHint}) async {
    final header = await file.openRead(0, defaultMagicNumbersMaxLength).expand((chunk) => chunk).toList();
    return lookupMimeType(nameHint, headerBytes: header) ?? 'application/octet-stream';
  }
}

/// Runs in an isolate: copies [sourcePath] to [targetPath] and returns
/// the content's hash, reading the file once and in chunks.
Future<String> _copyHashing(String sourcePath, String targetPath) async {
  final digest = _DigestSink();
  final hasher = sha256.startChunkedConversion(digest);
  final sink = File(targetPath).openWrite();
  try {
    await for (final chunk in File(sourcePath).openRead()) {
      sink.add(chunk);
      hasher.add(chunk);
    }
  } finally {
    await sink.close();
    hasher.close();
  }
  return '$_hashPrefix${digest.value}';
}

class _DigestSink implements Sink<Digest> {
  Digest? _digest;

  String get value => _digest.toString();

  @override
  void add(Digest data) => _digest = data;

  @override
  void close() {}
}

/// Hex of the SHA-256 of [bytes], with the store's prefix - for tests
/// and callers that already hold the content.
String fileHashOf(List<int> bytes) => '$_hashPrefix${sha256.convert(bytes)}';
