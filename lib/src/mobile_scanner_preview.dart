import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// A widget showing a live camera preview.
class CameraPreview extends StatelessWidget {
  /// Creates a preview widget for the given camera controller.
  const CameraPreview(this.controller, {super.key});

  /// The controller for the camera that the preview is shown for.
  final MobileScannerController controller;

  @override
  Widget build(BuildContext context) {
    if (!controller.value.isInitialized) {
      return const SizedBox();
    }

    return ValueListenableBuilder<MobileScannerState>(
      valueListenable: controller,
      builder: (BuildContext context, MobileScannerState value, Widget? child) {
        return SizedBox.fromSize(
          size:
              value.deviceOrientation.isLandscape
                  ? value.size.flipped
                  : value.size,
          child: _wrapInRotatedBox(
            child: _applyPreviewRotation(
              previewRotation: value.previewRotation,
              child: controller.buildCameraView(),
            ),
          ),
        );
      },
    );
  }

  /// Applies the rotation correction that CameraX reports for the preview
  /// buffer (Android only).
  ///
  /// CameraX delivers the preview buffer in an orientation that depends on the
  /// device, sensor and the resolved CameraX version. This rotates the buffer
  /// by the reported amount so it is displayed upright. It is a no-op on other
  /// platforms and when no correction is needed.
  Widget _applyPreviewRotation({
    required int previewRotation,
    required Widget child,
  }) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return child;
    }
    final int quarterTurns = (previewRotation ~/ 90) % 4;
    if (quarterTurns == 0) {
      return child;
    }
    return RotatedBox(quarterTurns: quarterTurns, child: child);
  }

  Widget _wrapInRotatedBox({required Widget child}) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return child;
    }
    return RotatedBox(
      quarterTurns: controller.value.deviceOrientation.turns,
      child: child,
    );
  }
}

/// Extension on [DeviceOrientation] that adds helpful properties for
/// working with screen rotation and camera preview transformations.
extension on DeviceOrientation {
  /// Returns `true` if the device orientation is landscape (horizontal).
  bool get isLandscape =>
      this == DeviceOrientation.landscapeLeft ||
      this == DeviceOrientation.landscapeRight;

  /// Maps the different device orientations to quarter turns that the
  /// preview should take in account.
  int get turns => switch (this) {
    DeviceOrientation.portraitUp => 0,
    DeviceOrientation.landscapeRight => 1,
    DeviceOrientation.portraitDown => 2,
    DeviceOrientation.landscapeLeft => 3,
  };
}
