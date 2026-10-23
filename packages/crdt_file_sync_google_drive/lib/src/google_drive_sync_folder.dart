import 'dart:convert';

import 'package:crdt_file_sync_transport/crdt_file_sync_transport.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

import 'drive_folders.dart';
import 'google_drive_file_transport.dart';
import 'google_drive_transport.dart';

/// The app's sync data in Google Drive, using only `drive.file`-scoped
/// calls (files the app itself created/opened) - see
/// `.local/GOOGLE_DRIVE_SETUP.md` for why that scope was chosen.
///
/// Layout: one folder [name] at the Drive root, holding
///
/// ```
/// format.json     {"version": <n>}, see readFormatVersion
/// changesets/     <nodeId>/<file>, see changesets
/// files/          flat, see files
/// ```
class GoogleDriveSyncFolder {
  GoogleDriveSyncFolder({required http.Client authClient, this.name = 'turtle-base-sync'})
    : _folders = DriveFolders(drive.DriveApi(authClient));

  static const formatFileName = 'format.json';
  static const _versionKey = 'version';

  final DriveFolders _folders;
  final String name;

  late final SyncTransport changesets = GoogleDriveTransport(_folders, [name, 'changesets']);
  late final FileTransport files = GoogleDriveFileTransport(_folders, [name, 'files']);

  /// The layout version stored in [formatFileName], null if there is
  /// none yet. The app compares it against its own to refuse syncing
  /// data a newer app version wrote.
  Future<int?> readFormatVersion() async {
    final file = await _formatFile();
    if (file == null) return null;
    final media =
        await _folders.api.files.get(file.id!, downloadOptions: drive.DownloadOptions.fullMedia) as drive.Media;
    final bytes = await media.stream.expand((chunk) => chunk).toList();
    final json = jsonDecode(utf8.decode(bytes));
    return json is Map ? json[_versionKey] as int? : null;
  }

  Future<void> writeFormatVersion(int version) async {
    final bytes = utf8.encode(jsonEncode({_versionKey: version}));
    final media = drive.Media(Stream.value(bytes), bytes.length, contentType: 'application/json');
    final existing = await _formatFile();
    if (existing != null) {
      await _folders.api.files.update(drive.File(), existing.id!, uploadMedia: media);
      return;
    }
    final rootId = await _folders.resolve([name]);
    await _folders.api.files.create(
      drive.File(name: formatFileName, parents: [rootId]),
      uploadMedia: media,
    );
  }

  Future<drive.File?> _formatFile() async {
    final rootId = await _folders.resolve([name]);
    return (await _folders.childFiles(rootId, name: formatFileName)).firstOrNull;
  }
}
