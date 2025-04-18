/// The state of the flashlight.
enum RecordState {
  auto(2),
  off(0),
  on(1),
  unavailable(-1);

  const RecordState(this.rawValue);

  factory RecordState.fromRawValue(int value) {
    switch (value) {
      case -1:
        return RecordState.unavailable;
      case 0:
        return RecordState.off;
      case 1:
        return RecordState.on;
      case 2:
        return RecordState.auto;
      default:
        throw ArgumentError.value(value, 'value', 'Invalid raw value.');
    }
  }

  /// The raw value for the torch state.
  final int rawValue;
}
