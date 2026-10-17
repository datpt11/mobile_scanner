/// The result of a video recording, including failures without a video.
class RecordFile {
  /// Create a new [RecordFile] instance.
  RecordFile({this.file, this.id, this.error});

  /// Recording could not start or ended without a usable video.
  static const int notStarted = -1;

  /// CameraX stopped receiving frames, for example when the app went inactive.
  static const int sourceInactive = 4;

  /// The file path of the recorded video.
  ///
  /// This is null when no video was retained.
  String? file;

  /// The id of the recorded video.
  String? id;

  /// The error code of the recording, or null if it succeeded.
  ///
  /// On Android this is a CameraX `VideoRecordEvent.Finalize` error code,
  /// and [file] is still set when the video recorded before the error was kept.
  /// A retained file with an unknown error is not guaranteed to be playable.
  /// [notStarted] means recording could not start or produced no usable video.
  int? error;
}
