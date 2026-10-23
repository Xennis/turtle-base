import 'package:flutter/foundation.dart';
import 'package:googleapis/drive/v3.dart' as drive;

const folderMimeType = 'application/vnd.google-apps.folder';

/// Folder lookups shared by the transports of one [drive.DriveApi]:
/// resolves (and creates) folder paths once, and lists with paging.
class DriveFolders {
  DriveFolders(this.api);

  final drive.DriveApi api;

  final _ids = <String, String>{};

  /// The id of the folder at [path] from the Drive root, creating
  /// missing folders on the way.
  Future<String> resolve(List<String> path) async {
    String? parentId;
    for (var i = 0; i < path.length; i++) {
      final key = path.sublist(0, i + 1).join('/');
      parentId = _ids[key] ??= await _findOrCreate(name: path[i], parentId: parentId);
    }
    return parentId!;
  }

  /// Every file matching [query] - Drive returns at most one page per
  /// call (100 entries by default), so this follows `nextPageToken`.
  Future<List<drive.File>> listAll(String query) async {
    final files = <drive.File>[];
    String? pageToken;
    do {
      final page = await api.files.list(
        q: query,
        spaces: 'drive',
        pageSize: 1000,
        pageToken: pageToken,
        $fields: 'nextPageToken,files(id,name)',
      );
      files.addAll(page.files ?? const []);
      pageToken = page.nextPageToken;
    } while (pageToken != null);
    return files;
  }

  Future<List<drive.File>> childFolders(String parentId) {
    return listAll("'$parentId' in parents and mimeType='$folderMimeType' and trashed=false");
  }

  Future<List<drive.File>> childFiles(String parentId, {String? name}) {
    final nameClause = name == null ? '' : " and name='${escapeQuery(name)}'";
    return listAll("'$parentId' in parents and mimeType!='$folderMimeType' and trashed=false$nameClause");
  }

  Future<String> _findOrCreate({required String name, required String? parentId}) async {
    final parentClause = parentId == null ? '' : " and '$parentId' in parents";
    final existing = await listAll(
      "name='${escapeQuery(name)}' and mimeType='$folderMimeType' and trashed=false$parentClause",
    );
    final existingId = existing.firstOrNull?.id;
    if (existingId != null) {
      debugPrint('[sync] drive: found existing folder "$name" ($existingId)');
      return existingId;
    }

    final created = await api.files.create(
      drive.File(name: name, mimeType: folderMimeType, parents: parentId == null ? null : [parentId]),
    );
    debugPrint('[sync] drive: created new folder "$name" (${created.id})');
    return created.id!;
  }
}

/// Escapes [value] for a string literal in a Drive query.
String escapeQuery(String value) => value.replaceAll(r'\', r'\\').replaceAll("'", r"\'");
