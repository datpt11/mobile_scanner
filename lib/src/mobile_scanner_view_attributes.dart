import 'dart:ui';

import 'package:mobile_scanner/mobile_scanner.dart';

/// This class defines the attributes for the mobile scanner view.
class MobileScannerViewAttributes {
  /// Construct a new [MobileScannerViewAttributes] instance.
  const MobileScannerViewAttributes({
    required this.cameraDirection,
    required this.currentTorchMode,
    required this.size,
    this.numberOfCameras,
    this.currentRecordingState = RecordState.off,
  });

  /// The direction of the active camera.
  final CameraFacing cameraDirection;

  /// The current torch state of the active camera.
  final TorchState currentTorchMode;

  /// The number of available cameras.
  final int? numberOfCameras;

  /// The size of the camera output.
  final Size size;

  /// The current recording state.
  final RecordState currentRecordingState;
}
