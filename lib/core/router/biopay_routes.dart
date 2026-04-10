import 'package:go_router/go_router.dart';

import '../../features/biopay/models/biopay_enrollment_draft.dart';
import '../../features/biopay/screens/biopay_enrollment_success_screen.dart';
import '../../features/biopay/screens/biopay_home_screen.dart';
import '../../features/biopay/screens/biopay_nfc_screen.dart';

import '../../features/biopay/screens/biopay_qr_screen.dart';
import '../../features/biopay/screens/biopay_register_screen.dart';
import '../../features/biopay/screens/biopay_scan_screen.dart';
import '../../shared/widgets/kill_switch_gate.dart';
import '../../shared/widgets/secure_screen_wrapper.dart';
import 'app_routes.dart';
import 'cool_page_transition.dart';

/// BioPay route list (4 routes: home, register, scan, nfc).
/// All routes are gated through the KillSwitchGate feature flag config.
List<GoRoute> biopayRoutes({
  required CoolPageBuilder coolPageTransition,
  required bool Function() readIsBiopayEnabled,
}) {
  return [
    GoRoute(
      path: AppRoutes.biopayHome,
      pageBuilder: (context, state) {
        return coolPageTransition(
          context: context,
          state: state,
          child: KillSwitchGate(
            enabled: readIsBiopayEnabled(),
            featureName: 'BioPay',
            child: const SecureScreenWrapper(child: BiopayHomeScreen()),
          ),
        );
      },
    ),

    GoRoute(
      path: AppRoutes.biopayRegister,
      pageBuilder: (context, state) {
        return coolPageTransition(
          context: context,
          state: state,
          child: KillSwitchGate(
            enabled: readIsBiopayEnabled(),
            featureName: 'BioPay',
            child: const SecureScreenWrapper(child: BiopayRegisterScreen()),
          ),
        );
      },
    ),
    GoRoute(
      path: AppRoutes.biopayQr,
      pageBuilder: (context, state) {
        return coolPageTransition(
          context: context,
          state: state,
          child: KillSwitchGate(
            enabled: readIsBiopayEnabled(),
            featureName: 'BioPay',
            child: const SecureScreenWrapper(child: BiopayQrScreen()),
          ),
        );
      },
    ),
    GoRoute(
      path: AppRoutes.biopayScan,
      pageBuilder: (context, state) {
        final modeParam = state.uri.queryParameters['mode']?.trim();
        final mode = modeParam == 'enroll'
            ? BiopayScanMode.enroll
            : BiopayScanMode.pay;
        final draft = state.extra is BiopayEnrollmentDraft
            ? state.extra! as BiopayEnrollmentDraft
            : null;
        return coolPageTransition(
          context: context,
          state: state,
          child: KillSwitchGate(
            enabled: readIsBiopayEnabled(),
            featureName: 'BioPay',
            child: SecureScreenWrapper(
              child: BiopayScanScreen(mode: mode, enrollmentDraft: draft),
            ),
          ),
        );
      },
    ),
    GoRoute(
      path: AppRoutes.biopayNfc,
      pageBuilder: (context, state) {
        return coolPageTransition(
          context: context,
          state: state,
          child: KillSwitchGate(
            enabled: readIsBiopayEnabled(),
            featureName: 'BioPay',
            child: const SecureScreenWrapper(child: BiopayNfcScreen()),
          ),
        );
      },
    ),
    GoRoute(
      path: AppRoutes.biopayEnrollmentSuccess,
      pageBuilder: (context, state) {
        return coolPageTransition(
          context: context,
          state: state,
          child: KillSwitchGate(
            enabled: readIsBiopayEnabled(),
            featureName: 'BioPay',
            child: SecureScreenWrapper(
              child: BiopayEnrollmentSuccessScreen(
                publicId: state.uri.queryParameters['id'],
              ),
            ),
          ),
        );
      },
    ),
  ];
}
