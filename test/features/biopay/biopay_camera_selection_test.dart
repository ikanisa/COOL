import 'package:camera/camera.dart';
import 'package:cool_app/features/biopay/services/biopay_camera_selection.dart';
import 'package:flutter_test/flutter_test.dart';

const _frontCamera = CameraDescription(
  name: 'front',
  lensDirection: CameraLensDirection.front,
  sensorOrientation: 90,
);

const _rearCamera = CameraDescription(
  name: 'rear',
  lensDirection: CameraLensDirection.back,
  sensorOrientation: 90,
);

void main() {
  group('biopay camera selection', () {
    test('defaults enrollment to the front camera', () {
      expect(
        biopayDefaultLensDirection(isEnrollMode: true),
        CameraLensDirection.front,
      );
    });

    test('defaults payment to the rear camera', () {
      expect(
        biopayDefaultLensDirection(isEnrollMode: false),
        CameraLensDirection.back,
      );
    });

    test('selects the preferred lens when it is available', () {
      final camera = selectBiopayCamera(
        cameras: const <CameraDescription>[_rearCamera, _frontCamera],
        preferredLensDirection: CameraLensDirection.front,
      );

      expect(camera, _frontCamera);
    });

    test(
      'falls back to the first available camera when preferred is missing',
      () {
        final camera = selectBiopayCamera(
          cameras: const <CameraDescription>[_rearCamera],
          preferredLensDirection: CameraLensDirection.front,
        );

        expect(camera, _rearCamera);
      },
    );

    test('reports when enrollment can switch between front and rear', () {
      expect(
        biopayEnrollmentSupportsCameraSwitch(const <CameraDescription>[
          _rearCamera,
          _frontCamera,
        ]),
        isTrue,
      );
      expect(
        biopayEnrollmentSupportsCameraSwitch(const <CameraDescription>[
          _frontCamera,
        ]),
        isFalse,
      );
    });

    test('toggles enrollment camera between front and rear lenses', () {
      expect(
        biopayNextEnrollmentLensDirection(
          currentLensDirection: CameraLensDirection.front,
          cameras: const <CameraDescription>[_rearCamera, _frontCamera],
        ),
        CameraLensDirection.back,
      );
      expect(
        biopayNextEnrollmentLensDirection(
          currentLensDirection: CameraLensDirection.back,
          cameras: const <CameraDescription>[_rearCamera, _frontCamera],
        ),
        CameraLensDirection.front,
      );
    });
  });
}
