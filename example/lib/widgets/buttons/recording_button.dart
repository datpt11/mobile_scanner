import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Button widget for recording function
class RecordingButton extends StatelessWidget {
  /// Construct a new [RecordingButton] instance.
  const RecordingButton({required this.controller, super.key});

  /// Controller which is used to call start and stop recording
  final MobileScannerController controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: controller,
      builder: (context, state, child) {
        if (!state.isInitialized || !state.isRunning) {
          return const SizedBox.shrink();
        }
        print(state.recordState);
        if (state.recordState == RecordState.on) {
          return IconButton(
            color: Colors.white,
            iconSize: 32,
            icon: const Icon(Icons.video_call),
            onPressed: () async {
              await controller.stopRecording(id: '999');
            },
          );
        }
        return IconButton(
          color: Colors.white,
          iconSize: 32,
          icon: const Icon(Icons.missed_video_call_outlined),
          onPressed: () async {
            await controller.startRecording(id: '999');
          },
        );
      },
    );
  }
}
