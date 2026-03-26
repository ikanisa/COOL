import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/engagement_feature_flags.dart';

import '../../features/biopay/models/biopay_enrollment_draft.dart';
import '../../features/biopay/models/biopay_match_result.dart';
import '../../features/biopay/screens/biopay_confirm_screen.dart';
import '../../features/biopay/screens/biopay_home_screen.dart';
import '../../features/biopay/screens/biopay_register_screen.dart';
import '../../features/biopay/screens/biopay_scan_screen.dart';
import '../../shared/widgets/kill_switch_gate.dart';
import '../../shared/widgets/secure_screen_wrapper.dart';
import 'app_routes.dart';

/// Typedef matching the auth snapshot shape used by BioPay route builders.
typedef BiopayAuthReader = ({bool isAdmin}) Function();

/// Typedef for reading feature flags.
typedef BiopayFlagsReader = EngagementFeatureFlags Function();

/// Typedef for building a Cool page transition.
typedef CoolPageBuilder =
    CustomTransitionPage<dynamic> Function({
      required BuildContext context,
      required GoRouterState state,
      required Widget child,
    });

/// BioPay route list (4 routes: home, register, scan, confirm).
List<GoRoute> biopayRoutes({
  required BiopayAuthReader readAuthSnapshot,
  required BiopayFlagsReader readFeatureFlags,
  required CoolPageBuilder coolPageTransition,
}) {
  return [
    GoRoute(
      path: AppRoutes.biopayHome,
      pageBuilder: (context, state) {
        final authSnapshot = readAuthSnapshot();
        final featureFlags = readFeatureFlags();
        return coolPageTransition(
          context: context,
          state: state,
          child: KillSwitchGate(
            enabled: featureFlags.isBiopayEnabled(
              isAdmin: authSnapshot.isAdmin,
            ),
            featureName: 'BioPay',
            child: const SecureScreenWrapper(child: BiopayHomeScreen()),
          ),
        );
      },
    ),
    GoRoute(
      path: AppRoutes.biopayRegister,
      pageBuilder: (context, state) {
        final authSnapshot = readAuthSnapshot();
        final featureFlags = readFeatureFlags();
        return coolPageTransition(
          context: context,
          state: state,
          child: KillSwitchGate(
            enabled: featureFlags.isBiopayEnabled(
              isAdmin: authSnapshot.isAdmin,
            ),
            featureName: 'BioPay',
            child: const SecureScreenWrapper(child: BiopayRegisterScreen()),
          ),
        );
      },
    ),
    GoRoute(
      path: AppRoutes.biopayScan,
      pageBuilder: (context, state) {
        final authSnapshot = readAuthSnapshot();
        final featureFlags = readFeatureFlags();
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
            enabled: featureFlags.isBiopayEnabled(
              isAdmin: authSnapshot.isAdmin,
            ),
            featureName: 'BioPay',
            child: SecureScreenWrapper(
              child: BiopayScanScreen(mode: mode, enrollmentDraft: draft),
            ),
          ),
        );
      },
    ),
    GoRoute(
      path: AppRoutes.biopayConfirm,
      pageBuilder: (context, state) {
        final authSnapshot = readAuthSnapshot();
        final featureFlags = readFeatureFlags();
        final result = state.extra is BiopayMatchResult
            ? state.extra! as BiopayMatchResult
            : null;
        return coolPageTransition(
          context: context,
          state: state,
          child: KillSwitchGate(
            enabled: featureFlags.isBiopayEnabled(
              isAdmin: authSnapshot.isAdmin,
            ),
            featureName: 'BioPay',
            child: SecureScreenWrapper(
              child: BiopayConfirmScreen(result: result),
            ),
          ),
        );
      },
    ),
  ];
}
