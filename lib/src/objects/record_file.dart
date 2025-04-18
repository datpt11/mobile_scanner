/// This class represents a scanned barcode.
class RecordFile {
  /// Create a new [RecordFile] instance.
  RecordFile({this.file, this.id});

  /// The file path of the recorded video.
  String? file;

  /// The id of the recorded video.
  String? id;
}
