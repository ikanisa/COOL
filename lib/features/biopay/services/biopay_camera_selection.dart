import 'package:camera/camera.dart';

CameraLensDirection biopayDefaultLensDirection({required bool isEnrollMode}) {
  return isEnrollMode ? CameraLensDirection.front : CameraLensDirection.back;
}

CameraDescription selectBiopayCamera({
  required List<CameraDescription> cameras,
  required CameraLensDirection preferredLensDirection,
}) {
  if (cameras.isEmpty) {
    throw ArgumentError.value(cameras, 'cameras', 'must not be empty');
  }

  return cameras.firstWhere(
    (candidate) => candidate.lensDirection == preferredLensDirection,
    orElse: () => cameras.first,
  );
}

bool biopayEnrollmentSupportsCameraSwitch(List<CameraDescription> cameras) {
  final lensDirections = cameras
      .map((camera) => camera.lensDirection)
      .where(
        (lensDirection) =>
            lensDirection == CameraLensDirection.front ||
            lensDirection == CameraLensDirection.back,
      )
      .toSet();

  return lensDirections.contains(CameraLensDirection.front) &&
      lensDirections.contains(CameraLensDirection.back);
}

CameraLensDirection? biopayNextEnrollmentLensDirection({
  required CameraLensDirection currentLensDirection,
  required List<CameraDescription> cameras,
}) {
  if (!biopayEnrollmentSupportsCameraSwitch(cameras)) {
    return null;
  }

  return currentLensDirection == CameraLensDirection.front
      ? CameraLensDirection.back
      : CameraLensDirection.front;
}
