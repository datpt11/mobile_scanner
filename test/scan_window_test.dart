import 'dart:math' as math;
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:mobile_scanner/src/scan_window_calculation.dart';

void main() {
  group(
    'Scan window relative to texture',
    () {
      group('Widget (landscape) smaller than texture (portrait)', () {
        const textureSize = Size(480.0, 640.0);
        const widgetSize = Size(432.0, 256.0);
        final ctx = ScanWindowTestContext(
          textureSize: textureSize,
          widgetSize: widgetSize,
          scanWindow: Rect.fromLTWH(
            widgetSize.width / 4,
            widgetSize.height / 4,
            widgetSize.width / 2,
            widgetSize.height / 2,
          ),
        );

        test('wl tp: BoxFit.none', () {
          ctx.testScanWindow(
            BoxFit.none,
            const Rect.fromLTRB(0.275, 0.4, 0.725, 0.6),
          );
        });

        test('wl tp: BoxFit.fill', () {
          ctx.testScanWindow(
            BoxFit.fill,
            const Rect.fromLTRB(0.25, 0.25, 0.75, 0.75),
          );
        });

        test('wl tp: BoxFit.fitHeight', () {
          ctx.testScanWindow(
            BoxFit.fitHeight,
            const Rect.fromLTRB(0.0, 0.25, 1.0, 0.75),
          );
        });

        test('wl tp: BoxFit.fitWidth', () {
          ctx.testScanWindow(
            BoxFit.fitWidth,
            const Rect.fromLTRB(
              0.25,
              0.38888888888888895,
              0.75,
              0.6111111111111112,
            ),
          );
        });

        test('wl tp: BoxFit.cover', () {
          // equal to fitWidth
          ctx.testScanWindow(
            BoxFit.cover,
            const Rect.fromLTRB(
              0.25,
              0.38888888888888895,
              0.75,
              0.6111111111111112,
            ),
          );
        });

        test('wl tp: BoxFit.contain', () {
          // equal to fitHeigth
          ctx.testScanWindow(
            BoxFit.contain,
            const Rect.fromLTRB(0.0, 0.25, 1.0, 0.75),
          );
        });

        test('wl tp: BoxFit.scaleDown', () {
          // equal to fitHeigth, contain
          ctx.testScanWindow(
            BoxFit.scaleDown,
            const Rect.fromLTRB(0.0, 0.25, 1.0, 0.75),
          );
        });
      });

      group('Widget (landscape) smaller than texture and texture (landscape)',
          () {
        const textureSize = Size(640.0, 480.0);
        const widgetSize = Size(320.0, 120.0);
        final ctx = ScanWindowTestContext(
          textureSize: textureSize,
          widgetSize: widgetSize,
          scanWindow: Rect.fromLTWH(
            widgetSize.width / 4,
            widgetSize.height / 4,
            widgetSize.width / 2,
            widgetSize.height / 2,
          ),
        );

        test('wl tl: BoxFit.none', () {
          ctx.testScanWindow(
            BoxFit.none,
            const Rect.fromLTRB(0.375, 0.4375, 0.625, 0.5625),
          );
        });

        test('wl tl: BoxFit.fill', () {
          ctx.testScanWindow(
            BoxFit.fill,
            const Rect.fromLTRB(0.25, 0.25, 0.75, 0.75),
          );
        });

        test('wl tl: BoxFit.fitHeight', () {
          ctx.testScanWindow(
            BoxFit.fitHeight,
            const Rect.fromLTRB(0.0, 0.25, 1.0, 0.75),
          );
        });

        test('wl tl: BoxFit.fitWidth', () {
          ctx.testScanWindow(
            BoxFit.fitWidth,
            const Rect.fromLTRB(0.25, 0.375, 0.75, 0.625),
          );
        });

        test('wl tl: BoxFit.cover', () {
          // equal to fitWidth
          ctx.testScanWindow(
            BoxFit.cover,
            const Rect.fromLTRB(0.25, 0.375, 0.75, 0.625),
          );
        });

        test('wl tl: BoxFit.contain', () {
          // equal to fitHeigth
          ctx.testScanWindow(
            BoxFit.contain,
            const Rect.fromLTRB(0.0, 0.25, 1.0, 0.75),
          );
        });

        test('wl tl: BoxFit.scaleDown', () {
          // equal to fitHeigth, contain
          ctx.testScanWindow(
            BoxFit.scaleDown,
            const Rect.fromLTRB(0.0, 0.25, 1.0, 0.75),
          );
        });
      });
    },
  );

  group(
    'calculateBoxFitRatio',
    () {
      group('Smaller camera preview size in portrait', () {
        const cameraPreviewSize = Size(480.0, 640.0);
        const size = Size(432.0, 256.0);

        test('scpsip: BoxFit.fill', () {
          final ratio = calculateBoxFitRatio(
            BoxFit.fill,
            cameraPreviewSize,
            size,
          );
          expect(ratio.widthRatio, 0.9);
          expect(ratio.heightRatio, 0.4);
        });

        test('scpsip: BoxFit.contain', () {
          final ratio = calculateBoxFitRatio(
            BoxFit.contain,
            cameraPreviewSize,
            size,
          );

          expect(ratio.widthRatio, 0.4);
          expect(ratio.heightRatio, 0.4);
        });

        test('scpsip: BoxFit.cover', () {
          final ratio = calculateBoxFitRatio(
            BoxFit.cover,
            cameraPreviewSize,
            size,
          );

          expect(ratio.widthRatio, 0.9);
          expect(ratio.heightRatio, 0.9);
        });

        test('scpsip: BoxFit.fitWidth', () {
          final ratio = calculateBoxFitRatio(
            BoxFit.fitWidth,
            cameraPreviewSize,
            size,
          );
          expect(ratio.widthRatio, 0.9);
          expect(ratio.heightRatio, 0.9);
        });

        test('scpsip: BoxFit.fitHeight', () {
          final ratio = calculateBoxFitRatio(
            BoxFit.fitHeight,
            cameraPreviewSize,
            size,
          );
          expect(ratio.widthRatio, 0.4);
          expect(ratio.heightRatio, 0.4);
        });

        test('scpsip: BoxFit.none', () {
          final ratio = calculateBoxFitRatio(
            BoxFit.none,
            cameraPreviewSize,
            size,
          );
          expect(ratio.widthRatio, 1.0);
          expect(ratio.heightRatio, 1.0);
        });

        test('scpsip: BoxFit.scaleDown', () {
          final ratio = calculateBoxFitRatio(
            BoxFit.scaleDown,
            cameraPreviewSize,
            size,
          );

          expect(ratio.widthRatio, 0.4);
          expect(ratio.heightRatio, 0.4);
        });
      });

      group('Smaller camera preview size in landscape', () {
        const cameraPreviewSize = Size(640.0, 480.0);
        const size = Size(320.0, 120.0);

        test('scpsil: BoxFit.fill', () {
          final ratio = calculateBoxFitRatio(
            BoxFit.fill,
            cameraPreviewSize,
            size,
          );
          expect(ratio.widthRatio, 0.5);
          expect(ratio.heightRatio, 0.25);
        });

        test('scpsil: BoxFit.contain', () {
          final ratio = calculateBoxFitRatio(
            BoxFit.contain,
            cameraPreviewSize,
            size,
          );

          expect(ratio.widthRatio, 0.25);
          expect(ratio.heightRatio, 0.25);
        });

        test('scpsil: BoxFit.cover', () {
          final ratio = calculateBoxFitRatio(
            BoxFit.cover,
            cameraPreviewSize,
            size,
          );

          expect(ratio.widthRatio, 0.5);
          expect(ratio.heightRatio, 0.5);
        });

        test('scpsil: BoxFit.fitWidth', () {
          final ratio = calculateBoxFitRatio(
            BoxFit.fitWidth,
            cameraPreviewSize,
            size,
          );
          expect(ratio.widthRatio, 0.5);
          expect(ratio.heightRatio, 0.5);
        });

        test('scpsil: BoxFit.fitHeight', () {
          final ratio = calculateBoxFitRatio(
            BoxFit.fitHeight,
            cameraPreviewSize,
            size,
          );
          expect(ratio.widthRatio, 0.25);
          expect(ratio.heightRatio, 0.25);
        });

        test('scpsil: BoxFit.none', () {
          final ratio = calculateBoxFitRatio(
            BoxFit.none,
            cameraPreviewSize,
            size,
          );
          expect(ratio.widthRatio, 1.0);
          expect(ratio.heightRatio, 1.0);
        });

        test('scpsil: BoxFit.scaleDown', () {
          final ratio = calculateBoxFitRatio(
            BoxFit.scaleDown,
            cameraPreviewSize,
            size,
          );

          expect(ratio.widthRatio, 0.25);
          expect(ratio.heightRatio, 0.25);
        });
      });
    },
  );
}

class ScanWindowTestContext {
  ScanWindowTestContext({
    required this.textureSize,
    required this.widgetSize,
    required this.scanWindow,
  });

  final Size textureSize;
  final Size widgetSize;
  final Rect scanWindow;

  void testScanWindow(BoxFit fit, Rect expected) {
    final actual = calculateScanWindowRelativeToTextureInPercentage(
      fit,
      scanWindow,
      textureSize: textureSize,
      widgetSize: widgetSize,
    );

    // don't use expect(actual, expected) because Rect.toString() only shows one digit after the comma which can be confusing
    expect(actual.left, expected.left);
    expect(actual.top, expected.top);
    expect(actual.right, expected.right);
    expect(actual.bottom, expected.bottom);
  }
}
