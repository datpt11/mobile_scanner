/// This class represents a scanned barcode.Add commentMore actions
class RecordFile {
  /// Create a new [RecordFile] instance.
  RecordFile({this.file, this.id, this.error});

  /// The file path of the recorded video.
  ///
  /// This is null when the recording failed without a usable video.
  String? file;

  /// The id of the recorded video.
  String? id;

  /// The error code of the recording, or null if it succeeded.
  ///
  /// On Android this is a CameraX `VideoRecordEvent.Finalize` error code,
  /// and [file] is still set when the video recorded before the error was kept.
  /// It is -1 when the recording could not be started or produced no video.
  int? error;
}
