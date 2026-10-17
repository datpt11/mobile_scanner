/// @docImport 'package:mobile_scanner/src/mobile_scanner.dart';
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';
import 'package:mobile_scanner/src/enums/barcode_format.dart';
import 'package:mobile_scanner/src/enums/camera_facing.dart';
import 'package:mobile_scanner/src/enums/detection_speed.dart';
import 'package:mobile_scanner/src/enums/mobile_scanner_error_code.dart';
import 'package:mobile_scanner/src/enums/record_state.dart';
import 'package:mobile_scanner/src/enums/torch_state.dart';
import 'package:mobile_scanner/src/method_channel/mobile_scanner_method_channel.dart';
import 'package:mobile_scanner/src/mobile_scanner_exception.dart';
import 'package:mobile_scanner/src/mobile_scanner_platform_interface.dart';
import 'package:mobile_scanner/src/mobile_scanner_view_attributes.dart';
import 'package:mobile_scanner/src/objects/barcode_capture.dart';
import 'package:mobile_scanner/src/objects/mobile_scanner_state.dart';
import 'package:mobile_scanner/src/objects/record_file.dart';
import 'package:mobile_scanner/src/objects/start_options.dart';

/// The controller for the [MobileScanner] widget.
class MobileScannerController extends ValueNotifier<MobileScannerState> {
  /// Construct a new [MobileScannerController] instance.
  MobileScannerController({
    this.autoStart = true,
    this.cameraResolution,
    this.detectionSpeed = DetectionSpeed.normal,
    int detectionTimeoutMs = 250,
    this.facing = CameraFacing.back,
    this.formats = const <BarcodeFormat>[],
    this.returnImage = false,
    this.torchEnabled = false,
    this.invertImage = false,
    this.autoZoom = false,
  }) : detectionTimeoutMs = detectionSpeed == DetectionSpeed.normal ? detectionTimeoutMs : 0,
       assert(detectionTimeoutMs >= 0, 'The detection timeout must be greater than or equal to 0.'),
       assert(
         facing != CameraFacing.unknown,
         'CameraFacing.unknown is not a valid camera direction.',
       ),
       super(const MobileScannerState.uninitialized());

  /// The desired resolution for the camera.
  ///
  /// When this value is provided, the camera will try to match this resolution,
  /// or fallback to the closest available resolution.
  /// When this is null, Android defaults to a resolution of 640x480.
  ///
  /// Bear in mind that changing the resolution has an effect on the aspect
  /// ratio.
  ///
  /// When the camera orientation changes,
  /// the resolution will be flipped to match the new dimensions of the display.
  ///
  /// Currently only supported on Android.
  final Size? cameraResolution;

  /// Automatically start the scanner on initialization.
  final bool autoStart;

  /// The detection speed for the scanner.
  ///
  /// Defaults to [DetectionSpeed.normal].
  final DetectionSpeed detectionSpeed;

  /// The detection timeout, in milliseconds, for the scanner.
  ///
  /// This timeout is ignored if the [detectionSpeed]
  /// is not set to [DetectionSpeed.normal].
  ///
  /// By default this is set to `250` milliseconds,
  /// which prevents memory issues on older devices.
  final int detectionTimeoutMs;

  /// The facing direction for the camera.
  ///
  /// Defaults to the back-facing camera.
  final CameraFacing facing;

  /// The formats that the scanner should detect.
  ///
  /// If this is empty, all supported formats are detected.
  final List<BarcodeFormat> formats;

  /// Whether the [BarcodeCapture.image] bytes should be provided.
  ///
  /// If this is false, [BarcodeCapture.image] will always be null.
  ///
  /// Defaults to false, and is only supported on iOS, MacOS and Android.
  final bool returnImage;

  /// Invert image colors for analyzer to support white-on-black barcodes, which
  /// are not supported by MLKit. Usage of this parameter can incur a
  /// performance cost, as frames need to be altered during processing.
  ///
  /// Defaults to false and is only supported on Android.
  final bool invertImage;

  /// Whether the flashlight should be turned on when the camera is started.
  ///
  /// Defaults to false.
  final bool torchEnabled;

  /// Whether the camera should auto zoom if the detected code is to far from
  /// the camera.
  ///
  /// Only supported on Android.
  final bool autoZoom;

  /// The internal barcode controller, that listens for detected barcodes.
  final StreamController<BarcodeCapture> _barcodesController = StreamController.broadcast();

  /// The internal record file controller, that listens for recorded files.
  final StreamController<RecordFile?> _recordFileController = StreamController.broadcast();

  /// Get the stream of scanned barcodes.
  ///
  /// If an error occurred during the detection of a barcode,
  /// a [MobileScannerBarcodeException] error is emitted to the stream.
  Stream<BarcodeCapture> get barcodes => _barcodesController.stream;

  /// Get the stream of recorded files.
  Stream<RecordFile?> get recordFile => _recordFileController.stream;

  StreamSubscription<BarcodeCapture?>? _barcodesSubscription;
  StreamSubscription<TorchState>? _torchStateSubscription;
  StreamSubscription<double>? _zoomScaleSubscription;
  StreamSubscription<DeviceOrientation>? _deviceOrientationSubscription;
  StreamSubscription<int>? _previewRotationSubscription;
  StreamSubscription<RecordState>? _recordStateSubscription;
  StreamSubscription<RecordFile?>? _recordFileSubscription;
  _RecordingSession? _recording;
  Future<void>? _cameraStopFuture;
  Future<void>? _disposeFuture;
  bool _isDisposing = false;
  bool _isDisposed = false;
  // This completer keeps track of whether the MobileScanner widget,
  // that is attached to this controller,
  // called its `initState()` lifecycle method.
  final Completer<void> _isAttachedCompleter = Completer<void>();

  void _disposeListeners() {
    _barcodesSubscription?.cancel();
    _torchStateSubscription?.cancel();
    _zoomScaleSubscription?.cancel();
    _deviceOrientationSubscription?.cancel();
    _previewRotationSubscription?.cancel();
    _recordStateSubscription?.cancel();
    _recordFileSubscription?.cancel();

    _barcodesSubscription = null;
    _torchStateSubscription = null;
    _zoomScaleSubscription = null;
    _deviceOrientationSubscription = null;
    _previewRotationSubscription = null;
    _recordStateSubscription = null;
    _recordFileSubscription = null;
  }

  void _setupListeners() {
    _barcodesSubscription = MobileScannerPlatform.instance.barcodesStream.listen(
      (BarcodeCapture? barcode) {
        if (_barcodesController.isClosed || barcode == null) {
          return;
        }

        _barcodesController.add(barcode);
      },
      onError: (Object error) {
        if (_barcodesController.isClosed) {
          return;
        }

        _barcodesController.addError(error);
      },
      // Errors are handled gracefully by forwarding them.
      cancelOnError: false,
    );

    _torchStateSubscription = MobileScannerPlatform.instance.torchStateStream.listen((
      TorchState torchState,
    ) {
      if (_isDisposed) {
        return;
      }

      value = value.copyWith(torchState: torchState);
    });

    _zoomScaleSubscription = MobileScannerPlatform.instance.zoomScaleStateStream.listen((
      double zoomScale,
    ) {
      if (_isDisposed) {
        return;
      }

      value = value.copyWith(zoomScale: zoomScale);
    });

    _recordStateSubscription = MobileScannerPlatform.instance.recordStateStream.listen((
      RecordState recordState,
    ) {
      if (_isDisposed) {
        return;
      }

      if (value.recordState != recordState) {
        value = value.copyWith(recordState: recordState);
      }
      if (recordState == RecordState.on) {
        _recording?.receivedOff = false;
      }
      if (recordState == RecordState.off) {
        _recording?.receivedOff = true;
        _completeRecording();
      }
    });

    _recordFileSubscription = MobileScannerPlatform.instance.recordFileStream.listen((
      RecordFile? file,
    ) {
      if (_recordFileController.isClosed || file == null) {
        return;
      }

      final _RecordingSession? recording = _recording;
      if (recording != null && (recording.id == null || recording.id == file.id)) {
        recording.receivedFile = true;
        // A terminal file event ends this recording, including an interrupted
        // recording. Consumers must see the same state on both platforms.
        if (value.recordState != RecordState.off) {
          value = value.copyWith(recordState: RecordState.off);
        }
      }
      _recordFileController.add(file);
      _completeRecording();
    });

    if (MobileScannerPlatform.instance case final MethodChannelMobileScanner implementation
        when defaultTargetPlatform != TargetPlatform.macOS) {
      _deviceOrientationSubscription = implementation.deviceOrientationChangedStream.listen((
        DeviceOrientation orientation,
      ) {
        if (_isDisposed) {
          return;
        }

        value = value.copyWith(deviceOrientation: orientation);
      });

      // The preview rotation reported by CameraX (Android only). This adapts
      // to the active CameraX version and the buffer orientation it delivers.
      _previewRotationSubscription = implementation.previewRotationStream.listen((
        int rotationDegrees,
      ) {
        if (_isDisposed) {
          return;
        }

        value = value.copyWith(previewRotation: rotationDegrees);
      });
    }
  }

  void _throwIfNotInitialized() {
    if (!value.isInitialized) {
      throw MobileScannerException(
        errorCode: MobileScannerErrorCode.controllerUninitialized,
        errorDetails: MobileScannerErrorDetails(
          message: MobileScannerErrorCode.controllerUninitialized.message,
        ),
      );
    }

    if (_isDisposed || _isDisposing) {
      throw MobileScannerException(
        errorCode: MobileScannerErrorCode.controllerDisposed,
        errorDetails: MobileScannerErrorDetails(
          message: MobileScannerErrorCode.controllerDisposed.message,
        ),
      );
    }
  }

  void _completeRecording() {
    final _RecordingSession? recording = _recording;
    if (recording == null || !recording.receivedFile || !recording.receivedOff) {
      return;
    }
    _recording = null;
    recording.done.complete();
  }

  Future<void> _stopCamera({required bool pause}) {
    return _cameraStopFuture ??= _stopCameraAndRecording(pause: pause).whenComplete(() {
      _cameraStopFuture = null;
    });
  }

  Future<void> _stopCameraAndRecording({required bool pause}) async {
    if (!value.isInitialized || !value.isRunning || _isDisposed) {
      return;
    }

    // Keep the event channel alive until native has finalized the video and
    // Dart has delivered its result. This also covers a pending Start event.
    await _finishRecording();
    if (pause) {
      await MobileScannerPlatform.instance.pause();
    } else {
      await MobileScannerPlatform.instance.stop();
    }
    _disposeListeners();

    final TorchState oldTorchState = value.torchState;
    final RecordState oldRecordState = value.recordState;
    // After the camera stopped, set the torch state to off,
    // as the torch state callback is never called when the camera is stopped.
    // If the device does not have a torch, do not report "off".
    value = value.copyWith(
      isRunning: false,
      torchState: oldTorchState == TorchState.unavailable ? TorchState.unavailable : TorchState.off,
      recordState:
          oldRecordState == RecordState.unavailable ? RecordState.unavailable : RecordState.off,
    );
  }

  /// Analyze an image file.
  ///
  /// The [path] points to a file on the device.
  /// The [formats] specify the barcode formats that should be detected in the
  /// image.
  /// If the [formats] are omitted or empty, all formats are detected.
  ///
  /// This is only supported on Android, physical iOS devices and MacOS.
  /// This is not supported on the iOS Simulator, due to restrictions on the
  /// Simulator.
  ///
  /// Returns the [BarcodeCapture] that was found in the image.
  ///
  /// If an error occurred during the analysis of the image,
  /// a [MobileScannerBarcodeException] error is thrown.
  ///
  /// If analyzing images from a file is not supported, an [UnsupportedError]
  /// is thrown.
  Future<BarcodeCapture?> analyzeImage(
    String path, {
    List<BarcodeFormat> formats = const <BarcodeFormat>[],
  }) {
    return MobileScannerPlatform.instance.analyzeImage(path, formats: formats);
  }

  /// Build a camera preview widget.
  Widget buildCameraView() {
    _throwIfNotInitialized();

    return MobileScannerPlatform.instance.buildCameraView();
  }

  /// Reset the zoom scale of the camera.
  ///
  /// Does nothing if the camera is not running.
  Future<void> resetZoomScale() async {
    _throwIfNotInitialized();

    if (!value.isRunning) {
      return;
    }

    // When the platform has updated the zoom scale,
    // it will send an update through the zoom scale state event stream.
    await MobileScannerPlatform.instance.resetZoomScale();
  }

  /// Set the zoom scale of the camera.
  ///
  /// The [zoomScale] must be between 0.0 and 1.0 (both inclusive).
  ///
  /// If the [zoomScale] is out of range,
  /// it is adjusted to fit within the allowed range.
  ///
  /// Does nothing if the camera is not running.
  Future<void> setZoomScale(double zoomScale) async {
    _throwIfNotInitialized();

    if (!value.isRunning) {
      return;
    }

    final double clampedZoomScale = zoomScale.clamp(0.0, 1.0);

    // Update the zoom scale state to the new state.
    // When the platform has updated the zoom scale,
    // it will send an update through the zoom scale state event stream.
    await MobileScannerPlatform.instance.setZoomScale(clampedZoomScale);
  }

  /// Start scanning for barcodes.
  ///
  /// The [cameraDirection] can be used to specify the camera direction.
  /// If this is null, this defaults to the [facing] value.
  ///
  /// Does nothing if the camera is already running.
  /// Upon calling this method, the necessary camera permission will be
  /// requested.
  ///
  /// If the permission is denied on iOS, MacOS or Web, there is no way to
  /// request it again.
  Future<void> start({CameraFacing? cameraDirection}) async {
    if (_cameraStopFuture != null) {
      await _cameraStopFuture;
    }
    if (_isDisposed || _isDisposing) {
      throw MobileScannerException(
        errorCode: MobileScannerErrorCode.controllerDisposed,
        errorDetails: MobileScannerErrorDetails(
          message: MobileScannerErrorCode.controllerDisposed.message,
        ),
      );
    }

    // If start was called before the MobileScanner widget
    // had a chance to call its initState method,
    // wait for it to be called, using a timeout.
    if (!_isAttachedCompleter.isCompleted) {
      // The timeout is currently an arbitrary value,
      // which should be long enough for the next frame
      // to propagate any pending changes to the widget tree.
      await _isAttachedCompleter.future.timeout(const Duration(milliseconds: 500)).catchError((
        Object error,
        StackTrace stackTrace,
      ) {
        throw MobileScannerException(
          errorCode: MobileScannerErrorCode.controllerNotAttached,
          errorDetails: MobileScannerErrorDetails(
            message: MobileScannerErrorCode.controllerNotAttached.message,
            details: stackTrace.toString(),
          ),
        );
      });

      // Abort if the controller was disposed
      // while waiting for the widget to be attached.
      if (_isDisposed) {
        throw MobileScannerException(
          errorCode: MobileScannerErrorCode.controllerDisposed,
          errorDetails: MobileScannerErrorDetails(
            message: MobileScannerErrorCode.controllerDisposed.message,
          ),
        );
      }
    }

    if (cameraDirection == CameraFacing.unknown) {
      throw const MobileScannerException(
        errorCode: MobileScannerErrorCode.genericError,
        errorDetails: MobileScannerErrorDetails(
          message: 'CameraFacing.unknown is not a valid camera direction.',
        ),
      );
    }

    // Do nothing if the camera is already running.
    if (value.isRunning) {
      return;
    }

    if (value.isStarting) {
      throw MobileScannerException(
        errorCode: MobileScannerErrorCode.controllerInitializing,
        errorDetails: MobileScannerErrorDetails(
          message: MobileScannerErrorCode.controllerInitializing.message,
        ),
      );
    }

    if (!_isDisposed) {
      value = value.copyWith(isStarting: true);
    }

    final StartOptions options = StartOptions(
      cameraDirection: cameraDirection ?? facing,
      cameraResolution: cameraResolution,
      detectionSpeed: detectionSpeed,
      detectionTimeoutMs: detectionTimeoutMs,
      formats: formats,
      returnImage: returnImage,
      torchEnabled: torchEnabled,
      invertImage: invertImage,
      autoZoom: autoZoom,
    );

    try {
      _setupListeners();

      final MobileScannerViewAttributes viewAttributes = await MobileScannerPlatform.instance.start(
        options,
      );

      if (!_isDisposed) {
        value = value.copyWith(
          availableCameras: viewAttributes.numberOfCameras,
          cameraDirection: viewAttributes.cameraDirection,
          isInitialized: true,
          isStarting: false,
          isRunning: true,
          size: viewAttributes.size,
          deviceOrientation: viewAttributes.initialDeviceOrientation,
          // Provide the current torch state.
          // Updates are provided by the `torchStateStream`.
          torchState: viewAttributes.currentTorchMode,
        );
      }
    } on MobileScannerException catch (error) {
      // The initialization finished with an error.
      // To avoid stale values, reset the camera direction,
      // output size, torch state and zoom scale to the defaults.
      if (!_isDisposed) {
        value = value.copyWith(
          cameraDirection: CameraFacing.unknown,
          isInitialized: true,
          isStarting: false,
          isRunning: false,
          error: error,
          size: Size.zero,
          torchState: TorchState.unavailable,
          zoomScale: 1,
          recordState: RecordState.unavailable,
        );
      }
    }
  }

  /// Stop the camera.
  ///
  /// After calling this method, the camera can be restarted using [start].
  ///
  /// Does nothing if the camera is already stopped.
  Future<void> stop() async {
    await _stopCamera(pause: false);
  }

  /// Pause the camera.
  ///
  /// This method stops to update camera frame and scan barcodes.
  /// After calling this method, the camera can be restarted using [start].
  ///
  /// Does nothing if the camera is already paused or stopped.
  Future<void> pause() async {
    await _stopCamera(pause: true);
  }

  /// Switch between the front and back camera.
  ///
  /// Does nothing if the device has less than 2 cameras,
  /// or if the current camera is an external camera.
  Future<void> switchCamera() async {
    _throwIfNotInitialized();

    final int? availableCameras = value.availableCameras;
    final CameraFacing cameraDirection = value.cameraDirection;

    // Do nothing if the amount of cameras is less than 2 cameras.
    // If the the current platform does not provide the amount of cameras,
    // continue anyway.
    if (availableCameras != null && availableCameras < 2) {
      return;
    }

    // If the camera direction is not known,
    // or if the camera is an external camera, do not allow switching cameras.
    if (cameraDirection == CameraFacing.unknown || cameraDirection == CameraFacing.external) {
      return;
    }

    await stop();

    switch (value.cameraDirection) {
      case CameraFacing.front:
        return start(cameraDirection: CameraFacing.back);
      case CameraFacing.back:
        return start(cameraDirection: CameraFacing.front);
      case CameraFacing.external:
      case CameraFacing.unknown:
        return;
    }
  }

  /// Start recording.
  ///
  /// If the camera is not running, nothing is recorded and a [RecordFile]
  /// with an error is emitted on [recordFile]. A second start while a recording
  /// is starting, recording or finishing also emits an error for the new id.
  ///
  /// Throws [MobileScannerException] if uninitialized or disposed.
  Future<void> startRecording({String? id}) async {
    _throwIfNotInitialized();

    if (!value.isRunning ||
        _cameraStopFuture != null ||
        _recording != null ||
        value.recordState == RecordState.on) {
      if (!_recordFileController.isClosed) {
        _recordFileController.add(RecordFile(id: id ?? '', error: RecordFile.notStarted));
      }
      return;
    }
    final recording = _RecordingSession(id);
    _recording = recording;
    try {
      await MobileScannerPlatform.instance.startRecording(id: id);
    } catch (_) {
      if (identical(_recording, recording)) {
        _recording = null;
        value = value.copyWith(recordState: RecordState.off);
        _recordFileController.add(RecordFile(id: id ?? '', error: RecordFile.notStarted));
        recording.done.complete();
      }
      rethrow;
    }
  }

  /// Stop recording.
  ///
  /// Completes after the recording has finalized and its [RecordFile] has been
  /// emitted. Does nothing if the camera is not recording.
  Future<void> stopRecording({String? id}) async {
    _throwIfNotInitialized();

    await _finishRecording(id: id);
  }

  Future<void> _finishRecording({String? id}) async {
    final _RecordingSession? recording = _recording;
    if (recording == null) return;
    recording.stopFuture ??= MobileScannerPlatform.instance.stopRecording(id: id);
    await recording.stopFuture;
    await recording.done.future;
  }

  /// Switches the flashlight on or off.
  ///
  /// Does nothing if the device has no torch,
  /// or if the camera is not running.
  ///
  /// If the current torch state is [TorchState.auto],
  /// the torch is turned on or off depending on its actual current state.
  Future<void> toggleTorch() async {
    _throwIfNotInitialized();

    if (!value.isRunning) {
      return;
    }

    final TorchState torchState = value.torchState;

    if (torchState == TorchState.unavailable) {
      return;
    }

    // Request the torch state to be switched to the opposite state.
    // When the platform has updated the torch state,
    // it will send an update through the torch state event stream.
    await MobileScannerPlatform.instance.toggleTorch();
  }

  /// Update the scan window with the given [window] rectangle.
  ///
  /// If [window] is null, the scan window will be reset to the full camera
  /// preview.
  Future<void> updateScanWindow(Rect? window) async {
    if (_isDisposed || !value.isInitialized) {
      return;
    }

    await MobileScannerPlatform.instance.updateScanWindow(window);
  }

  /// Dispose the controller.
  ///
  /// Once the controller is disposed, it cannot be used anymore.
  @override
  Future<void> dispose() async {
    if (_disposeFuture != null) {
      await _disposeFuture;
      return;
    }
    _disposeFuture = _disposeController();
    try {
      await _disposeFuture;
    } finally {
      super.dispose();
    }
  }

  Future<void> _disposeController() async {
    _isDisposing = true;
    await stop();
    _disposeListeners();
    _isDisposed = true;
    unawaited(_barcodesController.close());
    unawaited(_recordFileController.close());
    await MobileScannerPlatform.instance.dispose();
  }

  /// Signal to this [MobileScannerController] that it is attached
  /// to a [MobileScanner] widget.
  ///
  /// This method is called by `_MobileScannerState.initState()`
  /// and is not intended to be used directly.
  @internal
  void attach() {
    if (_isAttachedCompleter.isCompleted) {
      return;
    }

    _isAttachedCompleter.complete();
  }
}

// Reserve a recording synchronously, before native posts its Start event.
// Keep the reservation until both terminal events have arrived.
class _RecordingSession {
  _RecordingSession(this.id);

  final String? id;
  final Completer<void> done = Completer<void>();
  Future<void>? stopFuture;
  bool receivedFile = false;
  bool receivedOff = false;
}
