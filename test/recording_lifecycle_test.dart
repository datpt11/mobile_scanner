import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:mobile_scanner/src/method_channel/mobile_scanner_method_channel.dart';

/// Controls native event delivery independently from method replies.
class _RecorderPlatform extends MethodChannelMobileScanner {
  final events = StreamController<Map<Object?, Object?>>.broadcast();
  final calls = <String>[];
  String? activeId;
  bool active = false;
  bool emitStart = true;
  bool failStart = false;
  bool throwStart = false;
  bool autoFinalize = false;
  Completer<void>? stopReply;

  @override
  Stream<Map<Object?, Object?>> get eventsStream => events.stream;
  @override
  Stream<DeviceOrientation> get deviceOrientationChangedStream =>
      const Stream.empty();

  @override
  Future<MobileScannerViewAttributes> start(StartOptions options) async {
    calls.add('startCamera');
    return const MobileScannerViewAttributes(
      cameraDirection: CameraFacing.back,
      currentTorchMode: TorchState.off,
      size: Size(640, 480),
    );
  }

  @override
  Future<void> startRecording({String? id}) async {
    calls.add('start:$id');
    if (throwStart) throw PlatformException(code: 'start-failed');
    activeId = id;
    active = true;
    if (failStart) {
      finalize(error: RecordFile.notStarted, path: null);
    } else if (emitStart) {
      events.add({'name': 'recordState', 'data': 1});
    }
  }

  void finalize({int? error, String? path = '/local/video.mp4', String? id}) {
    if (!active) return;
    events
      ..add({
        'name': 'file',
        'id': id ?? activeId ?? '',
        'data': path,
        'error': error,
      })
      ..add({'name': 'recordState', 'data': 0});
    active = false;
    activeId = null;
    if (stopReply != null && !stopReply!.isCompleted) stopReply!.complete();
    stopReply = null;
  }

  @override
  Future<void> stopRecording({String? id}) async {
    calls.add('stopRecording');
    if (!active) return;
    final Completer<void> reply = stopReply ??= Completer<void>();
    if (autoFinalize) finalize(id: id);
    await reply.future;
  }

  @override
  Future<void> stop({bool force = false}) async {
    calls.add('stopCamera');
  }

  @override
  Future<void> pause({bool force = false}) async {
    calls.add('pauseCamera');
  }

  @override
  Future<void> dispose() async {
    calls.add('dispose');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _RecorderPlatform native;
  late MobileScannerController controller;
  late List<RecordFile?> files;
  late List<RecordState> statesAtFile;
  late StreamSubscription<RecordFile?> subscription;

  setUp(() async {
    native = _RecorderPlatform();
    MobileScannerPlatform.instance = native;
    controller = MobileScannerController(autoStart: false)..attach();
    files = [];
    statesAtFile = [];
    subscription = controller.recordFile.listen((file) {
      files.add(file);
      statesAtFile.add(controller.value.recordState);
      native.calls.add('file:${file?.id}');
    });
    await controller.start();
  });

  tearDown(() async {
    native
      ..autoFinalize = true
      ..finalize();
    await pumpEventQueue();
    await controller.dispose();
    await subscription.cancel();
    await native.events.close();
  });

  test(
    'interruption delivers retained file and ends the recording before notifying consumers',
    () async {
      await controller.startRecording(id: 'A');
      await pumpEventQueue();
      var endedNotifications = 0;
      controller.addListener(() {
        if (controller.value.recordState == RecordState.off) {
          endedNotifications++;
        }
      });
      native.finalize(error: RecordFile.sourceInactive);
      await pumpEventQueue();
      expect(files.single?.id, 'A');
      expect(files.single?.file, '/local/video.mp4');
      expect(files.single?.error, RecordFile.sourceInactive);
      expect(statesAtFile, [RecordState.off]);
      expect(endedNotifications, 1);
    },
  );

  for (final operation in ['stop', 'pause', 'dispose']) {
    test(
      '$operation waits for pending recording before releasing listeners or camera',
      () async {
        native.emitStart = false;
        await controller.startRecording(id: 'A');
        final Future<void> stopping = switch (operation) {
          'pause' => controller.pause(),
          'dispose' => controller.dispose(),
          _ => controller.stop(),
        };
        await pumpEventQueue();
        expect(native.calls, contains('stopRecording'));
        expect(native.calls, isNot(contains('stopCamera')));
        expect(native.calls, isNot(contains('pauseCamera')));
        expect(native.events.hasListener, isTrue);
        native.finalize();
        await stopping;
        expect(files.map((file) => file?.id), ['A']);
        final release = operation == 'pause' ? 'pauseCamera' : 'stopCamera';
        expect(
          native.calls.indexOf('file:A'),
          lessThan(native.calls.indexOf(release)),
        );
        expect(native.events.hasListener, isFalse);
      },
    );
  }

  test('platform start exception reports failure and permits retry', () async {
    native.throwStart = true;
    await expectLater(
      controller.startRecording(id: 'A'),
      throwsA(isA<PlatformException>()),
    );
    await pumpEventQueue();
    expect(files.single?.id, 'A');
    expect(files.single?.error, RecordFile.notStarted);
    native.throwStart = false;
    await controller.startRecording(id: 'B');
    expect(native.activeId, 'B');
  });

  test('concurrent dispose calls finalize and release only once', () async {
    await controller.startRecording(id: 'A');
    final Future<void> first = controller.dispose();
    final Future<void> second = controller.dispose();
    await pumpEventQueue();
    native.finalize();
    await Future.wait([first, second]);
    expect(files.map((file) => file?.id), ['A']);
    expect(native.calls.where((call) => call == 'dispose'), hasLength(1));
  });

  for (final pending in [true, false]) {
    test(
      'second start gets an error while A is ${pending ? 'pending' : 'recording'}',
      () async {
        native.emitStart = !pending;
        await controller.startRecording(id: 'A');
        await pumpEventQueue();
        await controller.startRecording(id: 'B');
        await pumpEventQueue();
        expect(native.calls, isNot(contains('start:B')));
        expect(native.activeId, 'A');
        expect(files.single?.id, 'B');
        expect(files.single?.error, RecordFile.notStarted);
        if (!pending) expect(controller.value.recordState, RecordState.on);
        native.finalize();
        await pumpEventQueue();
        expect(files.map((file) => file?.id), ['B', 'A']);
      },
    );
  }

  test(
    'start during finalization is rejected, then await stop permits the next recording',
    () async {
      await controller.startRecording(id: 'A');
      await pumpEventQueue();
      final Future<void> stopped = controller.stopRecording();
      await controller.startRecording(id: 'B');
      await pumpEventQueue();
      expect(controller.value.recordState, RecordState.on);
      expect(files.single?.id, 'B');
      native.finalize();
      await stopped;
      await controller.startRecording(id: 'C');
      expect(native.activeId, 'C');
    },
  );

  test(
    'duplicate stops share finalization and idle stop produces no failure event',
    () async {
      await controller.startRecording(id: 'A');
      final Future<void> first = controller.stopRecording();
      final Future<void> second = controller.stopRecording();
      await pumpEventQueue();
      expect(
        native.calls.where((call) => call == 'stopRecording'),
        hasLength(1),
      );
      native.finalize();
      await Future.wait([first, second]);
      await controller.stopRecording();
      await pumpEventQueue();
      expect(files, hasLength(1));
      expect(files.single?.error, isNull);
    },
  );

  test(
    'a method reply alone cannot release listeners before the terminal events',
    () async {
      await controller.startRecording(id: 'A');
      var completed = false;
      final Future<void> stopped = controller.stop().then((_) {
        completed = true;
      });
      await pumpEventQueue();
      native.stopReply!.complete();
      await pumpEventQueue();
      expect(completed, isFalse);
      expect(native.events.hasListener, isTrue);
      native.finalize();
      await stopped;
      expect(files.single?.id, 'A');
    },
  );

  test(
    'failed native start delivers null file and releases the reservation',
    () async {
      native.failStart = true;
      await controller.startRecording(id: 'A');
      await pumpEventQueue();
      expect(files.single?.error, RecordFile.notStarted);
      expect(files.single?.file, isNull);
      native.failStart = false;
      await controller.startRecording(id: 'B');
      expect(native.activeId, 'B');
    },
  );

  test(
    'stopped camera rejects start and can restart without duplicate subscriptions',
    () async {
      await controller.stop();
      await controller.startRecording(id: 'A');
      await pumpEventQueue();
      expect(files.single?.error, RecordFile.notStarted);
      await controller.start();
      await controller.startRecording(id: 'B');
      native.finalize();
      await pumpEventQueue();
      expect(files.map((file) => file?.id), ['A', 'B']);
    },
  );

  test('camera shutdown rejects starts while awaiting finalization', () async {
    await controller.startRecording(id: 'A');
    final Future<void> stopped = controller.stop();
    await controller.startRecording(id: 'B');
    await pumpEventQueue();
    expect(files.single?.id, 'B');
    expect(files.single?.error, RecordFile.notStarted);
    native.finalize();
    await stopped;
    expect(native.calls, isNot(contains('start:B')));
  });

  test('idless recording accepts a legacy id supplied at stop', () async {
    await controller.startRecording();
    final Future<void> stopped = controller.stopRecording(id: 'A');
    native.finalize(id: 'A');
    await stopped;
    expect(files.single?.id, 'A');
  });

  test(
    'uninitialized and disposed controllers retain the documented exception contract',
    () async {
      final uninitialized = MobileScannerController();
      await expectLater(
        uninitialized.startRecording(id: 'A'),
        throwsA(isA<MobileScannerException>()),
      );
      await uninitialized.dispose();
      await controller.dispose();
      await expectLater(
        controller.startRecording(id: 'B'),
        throwsA(isA<MobileScannerException>()),
      );
    },
  );
}
