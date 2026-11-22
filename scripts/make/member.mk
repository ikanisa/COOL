# Flutter development, native qualification, and retained member history.
.PHONY: flutter-clean flutter-pub-get format format-check
.PHONY: analyze test test-history-retained test-history-current14
.PHONY: mobile-route-render-smoke mobile-route-artifact-gate mobile-route-artifact-gate-json android-device-uat
.PHONY: ios-physical-route-uat ios-physical-lifecycle-uat ios-physical-camera-permission-uat ios-simulator-camera-permission-uat
.PHONY: ios-simulator-material-state-uat flutter-mobile-release-gate flutter-mobile-release-gate-json android-release-signing-preflight
.PHONY: android-release-signing-preflight-json android-kotlin-plugin-compat android-kotlin-plugin-compat-json ios-app-store-readiness-gate
.PHONY: ios-app-store-readiness-gate-json verify

flutter-clean:
	$(FLUTTER) clean

flutter-pub-get:
	$(FLUTTER) pub get

format:
	@DART="$(DART)" ruby scripts/qa/dart_format.rb --write

format-check:
	@DART="$(DART)" ruby scripts/qa/dart_format.rb --check

analyze:
	$(FLUTTER) analyze

# The maintained unit scope matches CI. Integration packets are never silently
# synthesized or skipped by their tests; invoke the exact named profile below.
test:
	"$(FLUTTER)" test --no-pub --concurrency=1 --exclude-tags=integration

test-history-retained:
	@FLUTTER_BIN="$(FLUTTER)" python3 scripts/qa/retained_member_history.py

test-history-current14:
	@test -n "$(DEFINES)" && test -f "$(DEFINES)" || { echo "DEFINES must name the reviewed historical current14 packet defines file." >&2; exit 2; }
	"$(FLUTTER)" test --no-pub --tags=integration --dart-define-from-file="$(DEFINES)" test/current14_member_history_sql_receipts_test.dart

mobile-route-render-smoke:
	@./scripts/mobile_route_render_smoke.sh

mobile-route-artifact-gate:
	@./scripts/mobile_route_artifact_gate.sh

mobile-route-artifact-gate-json:
	@./scripts/mobile_route_artifact_gate.sh --json

android-device-uat:
	@./scripts/android_device_uat.sh

ios-physical-route-uat:
	@./scripts/ios_physical_route_uat.sh $(ARGS)

ios-physical-lifecycle-uat:
	@IOS_PHYSICAL_UAT_MODE=lifecycle \
		IOS_PHYSICAL_UAT_TEST_TARGET=integration_test/mobile_ios_lifecycle_device_uat_test.dart \
		IOS_PHYSICAL_UAT_VARIANT_NAME=physical-lifecycle-dark \
		IOS_PHYSICAL_UAT_PREBUILD=true \
		IOS_PHYSICAL_UAT_UNLOCK_WAIT_SECONDS=180 \
		./scripts/ios_physical_route_uat.sh $(ARGS)

ios-physical-camera-permission-uat:
	@IOS_PHYSICAL_UAT_MODE=camera-settings \
		IOS_PHYSICAL_UAT_TEST_TARGET=integration_test/mobile_camera_permission_device_uat_test.dart \
		IOS_PHYSICAL_UAT_VARIANT_NAME=physical-camera-settings-dark \
		IOS_PHYSICAL_UAT_MOBILE_EVIDENCE_MODE=false \
		IOS_PHYSICAL_UAT_CAMERA_PHASE=physical-settings \
		IOS_PHYSICAL_UAT_RESET_STAGING_APP=true \
		IOS_PHYSICAL_UAT_PREBUILD=true \
		IOS_PHYSICAL_UAT_UNLOCK_WAIT_SECONDS=180 \
		./scripts/ios_physical_route_uat.sh $(ARGS)

ios-simulator-camera-permission-uat:
	@./scripts/ios_simulator_camera_permission_uat.sh $(ARGS)

ios-simulator-material-state-uat:
	@IOS_UAT_MODE=state \
		IOS_UAT_TEST_TARGET=integration_test/mobile_material_state_matrix_device_uat_test.dart \
		IOS_UAT_VARIANT_NAME=material-state-dark \
		IOS_UAT_THEME_MODE=dark \
		./scripts/ios_simulator_route_uat.sh $(ARGS)

flutter-mobile-release-gate:
	@./scripts/flutter_mobile_release_gate.sh

flutter-mobile-release-gate-json:
	@./scripts/flutter_mobile_release_gate.sh --json

android-release-signing-preflight:
	@./scripts/android_release_signing_preflight.sh

android-release-signing-preflight-json:
	@./scripts/android_release_signing_preflight.sh --json

android-kotlin-plugin-compat:
	@./scripts/android_kotlin_plugin_compat_gate.sh

android-kotlin-plugin-compat-json:
	@./scripts/android_kotlin_plugin_compat_gate.sh --json

ios-app-store-readiness-gate:
	@./scripts/ios_app_store_readiness_gate.sh

ios-app-store-readiness-gate-json:
	@./scripts/ios_app_store_readiness_gate.sh --json

verify: format-check analyze test
