import 'dart:io';
import 'dart:typed_data';

/// Represents a binary file managed by dartdata outside of SQLite.
///
/// Large binary assets (images, audio, video, documents) are stored as files
/// on disk. The SQLite column holds only a UUID reference. All I/O is
/// delegated to the underlying [dart:io] [File].
///
/// **Lifecycle**
///
/// | State          | How created                    | [file] accessible? |
/// |----------------|--------------------------------|--------------------|
/// | Staged (bytes) | [ExternalFile.fromBytes]       | No — not on disk yet |
/// | Staged (path)  | [ExternalFile.fromPath]        | No — not copied yet |
/// | Managed        | After [ModelContext.save]      | Yes |
/// | Pending delete | After [delete] is called       | No |
///
/// [file] throws [StateError] when called in a staged or deleted state.
/// Call [ModelContext.save] first to flush staged files to managed storage.
class ExternalFile {
  _ExternalFileState _state;

  ExternalFile._managed(File file) : _state = _ManagedState(file);
  ExternalFile._staged(_ExternalFileState state) : _state = state;

  /// Create an [ExternalFile] pre-populated with [data].
  ///
  /// The bytes are written to managed storage when [ModelContext.save] is
  /// called. Until then, [file] is not accessible.
  factory ExternalFile.fromBytes(Uint8List data) =>
      ExternalFile._staged(_StagedBytesState(data));

  /// Create an [ExternalFile] from a file that already exists on disk
  /// (e.g., returned by an image picker).
  ///
  /// The file is **copied** into managed storage on [ModelContext.save].
  /// The source file is left untouched.
  factory ExternalFile.fromPath(String path) =>
      ExternalFile._staged(_StagedPathState(path));

  /// The underlying [dart:io] [File] in managed storage.
  ///
  /// Use this for all I/O — [File.readAsBytes], [File.openRead],
  /// [File.stat], etc.
  ///
  /// Throws [StateError] if the file has not been persisted yet (i.e.,
  /// [ModelContext.save] has not been called since this object was created
  /// or last modified).
  File get file {
    return switch (_state) {
      _ManagedState(:final managedFile) => managedFile,
      _PendingDeletionState() =>
        throw StateError('ExternalFile has been marked for deletion.'),
      _ => throw StateError(
          'ExternalFile.file is not available until ModelContext.save() '
          'has been called. Use ExternalFile.fromBytes() and keep a '
          'reference to the Uint8List if you need access before saving.',
        ),
    };
  }

  /// The URI of the managed file. Convenience wrapper over [file.uri].
  ///
  /// Useful for APIs that accept a [Uri] (e.g., video players).
  Uri get uri => file.uri;

  /// Mark this file for deletion on the next [ModelContext.save].
  ///
  /// After calling [delete], setting the field to `null` and saving will
  /// remove the file from disk. Does nothing if the file was never persisted.
  void delete() {
    _state = _PendingDeletionState(
      switch (_state) {
        _ManagedState(:final managedFile) => managedFile,
        _ => null,
      },
    );
  }

  // -------------------------------------------------------------------------
  // Internal API — used by ModelContext and the generated code
  // -------------------------------------------------------------------------

  /// Whether this file needs to be written to disk on the next save.
  bool get isStaged =>
      _state is _StagedBytesState || _state is _StagedPathState;

  /// Whether this file should be removed from disk on the next save.
  bool get isPendingDeletion => _state is _PendingDeletionState;

  /// Whether this file is in managed storage and [file] is safe to access.
  bool get isManaged => _state is _ManagedState;

  /// The UUID key used to identify this file in the external data directory.
  /// Only available for managed files.
  String? get _managedUuid {
    if (_state case _ManagedState(:final managedFile)) {
      return managedFile.uri.pathSegments.last;
    }
    return null;
  }

  /// Write staged data to [destination] and transition to managed state.
  /// Called by [ModelContext] during save.
  Future<void> persistTo(File destination) async {
    switch (_state) {
      case _StagedBytesState(:final bytes):
        await destination.parent.create(recursive: true);
        await destination.writeAsBytes(bytes);
      case _StagedPathState(:final sourcePath):
        await destination.parent.create(recursive: true);
        await File(sourcePath).copy(destination.path);
      case _ManagedState():
        return; // already in place
      case _PendingDeletionState():
        throw StateError('Cannot persist a file marked for deletion.');
    }
    _state = _ManagedState(destination);
  }

  /// Delete the managed file from disk and transition to pending-deletion state.
  /// Called by [ModelContext] during save.
  Future<void> removeFromDisk() async {
    if (_state case _PendingDeletionState(:final managedFile?)) {
      if (await managedFile.exists()) {
        await managedFile.delete();
      }
    }
  }

  /// Reconstruct an [ExternalFile] pointing to a file that already exists in
  /// managed storage. Called by the generated `fromMap()` function.
  factory ExternalFile.fromManagedPath(String path) =>
      ExternalFile._managed(File(path));
}

// ---------------------------------------------------------------------------
// Internal state machine
// ---------------------------------------------------------------------------

sealed class _ExternalFileState {}

final class _ManagedState extends _ExternalFileState {
  final File managedFile;
  _ManagedState(this.managedFile);
}

final class _StagedBytesState extends _ExternalFileState {
  final Uint8List bytes;
  _StagedBytesState(this.bytes);
}

final class _StagedPathState extends _ExternalFileState {
  final String sourcePath;
  _StagedPathState(this.sourcePath);
}

final class _PendingDeletionState extends _ExternalFileState {
  final File? managedFile;
  _PendingDeletionState(this.managedFile);
}
