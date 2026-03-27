import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../features/biopay/models/biopay_enrollment_draft.dart';
import '../../features/biopay/screens/biopay_home_screen.dart';
import '../../features/biopay/screens/biopay_nfc_screen.dart';
import '../../features/biopay/screens/biopay_register_screen.dart';
import '../../features/biopay/screens/biopay_scan_screen.dart';
import '../../shared/widgets/kill_switch_gate.dart';
import '../../shared/widgets/secure_screen_wrapper.dart';
import 'app_routes.dart';

/// Typedef for building a Cool page transition.
typedef CoolPageBuilder =
    CustomTransitionPage<dynamic> Function({
      required BuildContext context,
      required GoRouterState state,
      required Widget child,
    });

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
  ];
}
