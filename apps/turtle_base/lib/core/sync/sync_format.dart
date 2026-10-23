/// The sync data layout this app version reads and writes. Bump it
/// whenever older app versions can no longer handle what this one syncs
/// (folder layout, a new table in the changesets, ...) - they then stop
/// syncing with a hint to update instead of failing on unknown data.
///
/// 1 was the flat layout without a format file, 2 added the changesets/
/// and files/ folders and the attachments table.
const syncFormatVersion = 2;

class SyncFormatTooNewException implements Exception {
  const SyncFormatTooNewException(this.found);

  final int found;

  @override
  String toString() =>
      'Sync data was written by a newer app version (format $found, this app supports $syncFormatVersion) '
      '- update the app.';
}

/// Writes [syncFormatVersion] where there is none yet (or an older
/// one), throws [SyncFormatTooNewException] for a newer one.
Future<void> ensureSyncFormat({
  required Future<int?> Function() read,
  required Future<void> Function(int version) write,
}) async {
  final found = await read();
  if (found != null && found > syncFormatVersion) throw SyncFormatTooNewException(found);
  if (found != syncFormatVersion) await write(syncFormatVersion);
}
