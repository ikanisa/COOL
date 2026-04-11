import '../../features/auth/models/user_profile.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/momo/services/momo_sms_autoread_service.dart';
import '../providers/notification_settings_provider.dart';
import '../services/app_access_service.dart';
import 'crashlytics_service.dart';
import 'engagement_tracker.dart';

class AppSessionCoordinator {
  AppSessionCoordinator({
    required NotificationSettingsNotifier notificationSettings,
    required EngagementTracker engagementTracker,
    required CrashlyticsService crashlytics,
    required AppAccessService appAccessService,
    required MomoSmsAutoreadService momoSmsAutoreadService,
  }) : _notificationSettings = notificationSettings,
       _engagementTracker = engagementTracker,
       _crashlytics = crashlytics,
       _appAccessService = appAccessService,
       _momoSmsAutoreadService = momoSmsAutoreadService;

  final NotificationSettingsNotifier _notificationSettings;
  final EngagementTracker _engagementTracker;
  final CrashlyticsService _crashlytics;
  final AppAccessService _appAccessService;
  final MomoSmsAutoreadService _momoSmsAutoreadService;

  Future<void> bootstrap(AuthState authState) async {
    await _identifyUserIfAvailable(authState.user);

    if (authState.session == null) {
      await _momoSmsAutoreadService.stop(resetPermissionPromptState: true);
      return;
    }

    await _momoSmsAutoreadService.refresh();
    await _notificationSettings.initializeForAuthState(authState);
    await _engagementTracker.trackSessionStarted(
      userId: authState.user?.id ?? authState.session!.user.id,
      isAuthenticated: true,
      isProfileComplete: authState.user?.isProfileComplete ?? false,
      source: 'app_launch',
    );
  }

  Future<void> handleAuthStateChanged(
    AuthState? previous,
    AuthState next,
  ) async {
    final hadSession = previous?.session != null;
    final hasSession = next.session != null;
    final previousUserId = previous?.user?.id ?? previous?.session?.user.id;

    if (previous?.user?.id != next.user?.id) {
      if (next.user != null) {
        await _identifyUserIfAvailable(next.user);
      } else if (!hasSession) {
        await _clearIdentifiedUser();
      }
    }

    if (!hadSession && hasSession) {
      // Only force-request SMS permission if user has completed onboarding.
      final onboardingComplete = await _appAccessService
          .hasCompletedPermissionOnboarding();
      await _momoSmsAutoreadService.refresh(
        forcePermissionRequest: onboardingComplete,
      );
      await _notificationSettings.initializeForAuthState(next);
      await _engagementTracker.trackSessionStarted(
        userId: next.user?.id ?? next.session!.user.id,
        isAuthenticated: true,
        isProfileComplete: next.user?.isProfileComplete ?? false,
        source: 'auth_transition',
      );
    }

    if (hadSession && !hasSession) {
      await _momoSmsAutoreadService.stop(resetPermissionPromptState: true);
      await _clearIdentifiedUser();
      if (previousUserId != null && previousUserId.isNotEmpty) {
        await _notificationSettings.clearSession(userId: previousUserId);
      }
    }
  }

  Future<void> _identifyUserIfAvailable(UserProfile? user) async {
    if (user == null) {
      return;
    }
    await _engagementTracker.identifyUser(user);
    await _crashlytics.identifyUser(user.id);
  }

  Future<void> _clearIdentifiedUser() async {
    await _engagementTracker.clearUser();
    await _crashlytics.clearUser();
  }
}
