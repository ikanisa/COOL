import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

abstract final class AppRoutes {
  static const splash = '/';
  static const home = '/home';

  // ── Contribution groups ─────────────────────────────────────────
  static const groups = '/groups';
  static const groupCreate = '/groups/create';
  static const groupDetail = '/groups/:id';
  static const groupLedger = '/groups/:id/ledger';
  static const groupInvite = '/invite/:code';

  // ── MoMo ────────────────────────────────────────────────────────
  /// @deprecated — standalone MoMo screen removed; kept for deep-link compat.
  static const momo = '/momo';
  static const momoWallet = '/momo/wallet';

  // ── BioPay ──────────────────────────────────────────────────────
  static const biopayHome = '/momo/biopay';
  static const biopayRegister = '/momo/biopay/register';
  static const biopayQr = '/momo/biopay/qr';
  static const biopayScan = '/momo/biopay/scan';
  static const biopayNfc = '/momo/biopay/nfc';
  static const biopayNfcTap = '/momo/biopay/nfc/tap';
  static const biopayEnrollmentSuccess = '/momo/biopay/success';

  // ── Contribution Circles ────────────────────────────────────────
  static const contributionCircles = '/contribution-circles';
  static const contributionCircleDetail = '/contribution-circles/:groupId';
  static const contributionCircleSettings =
      '/contribution-circles/:groupId/settings';
  static const contributionCircleStatements =
      '/contribution-circles/:groupId/statements';

  // ── Rewards / Engagement ────────────────────────────────────────
  static const referral = '/referral';

  // ── Profile ─────────────────────────────────────────────────────
  static const profile = '/profile';
  static const profileWallet = '/profile/wallet';
  static const profileAccount = '/profile/account';
  static const settings = profile;
  static const settingsWallet = profileWallet;
  static const settingsAccount = profileAccount;

  // ── Utilities ───────────────────────────────────────────────────
  static const scanner = '/scanner';

  // ── Admin ───────────────────────────────────────────────────────
  static const admin = '/admin';
  static const adminPlatform = '/admin/platform';
  static const adminBankWorkspace = '/admin/banks/:bankId';
  static const adminUsers = '/admin/users';
  static const adminAppConfig = '/admin/app-config';
  static const adminOperations = '/admin/operations';

  static const adminRoles = '/admin/roles';
  static const adminAnalytics = '/admin/analytics';
  static const adminAuditLog = '/admin/audit-log';
  static const adminGroups = '/admin/groups';

  // ── Location builders ─────────────────────────────────────────

  static String splashLocation({String? redirect}) {
    return _location(splash, redirect: redirect);
  }

  static String profileWalletLocation({String? redirect}) {
    return _location(profileWallet, redirect: redirect);
  }

  static String settingsWalletLocation({String? redirect}) {
    return profileWalletLocation(redirect: redirect);
  }

  static String inviteLocation(String code) {
    return '/invite/${code.trim().toUpperCase()}';
  }

  static String contributionCircleDetailLocation(String groupId) {
    return '/contribution-circles/$groupId';
  }

  static String contributionCircleStatementsLocation(String groupId) {
    return '/contribution-circles/$groupId/statements';
  }

  static String contributionCircleSettingsLocation(String groupId) {
    return '/contribution-circles/$groupId/settings';
  }

  static String adminBankWorkspaceLocation(String bankId) {
    return '/admin/banks/${bankId.trim()}';
  }

  static String biopayScanLocation({required String mode}) {
    return _location(
      biopayScan,
      queryParameters: <String, String>{'mode': mode.trim()},
    );
  }

  static String biopayEnrollmentSuccessLocation({String? publicId}) {
    return _location(
      biopayEnrollmentSuccess,
      queryParameters: publicId == null || publicId.trim().isEmpty
          ? null
          : <String, String>{'id': publicId.trim()},
    );
  }

  static String scannerLocation({String mode = 'momo'}) {
    return _location(
      scanner,
      queryParameters: <String, String>{'mode': mode.trim()},
    );
  }

  static String _location(
    String path, {
    Map<String, String>? queryParameters,
    String? redirect,
  }) {
    final parameters = <String, String>{
      ...?queryParameters,
      if (redirect != null && redirect.trim().isNotEmpty)
        'redirect': redirect.trim(),
    };
    if (parameters.isEmpty) {
      return path;
    }
    return Uri(path: path, queryParameters: parameters).toString();
  }
}

const appShellRootLocations = {
  AppRoutes.home,
  AppRoutes.biopayHome,
  AppRoutes.profile,
};

bool isShellRootLocation(String location) {
  final trimmed = location.trim();
  if (trimmed.isEmpty) {
    return false;
  }

  final uri = Uri.tryParse(trimmed);
  final path = uri?.path.isNotEmpty == true ? uri!.path : trimmed;
  return appShellRootLocations.contains(path);
}

void openQuickActionRoute(BuildContext context, String location) {
  final trimmed = location.trim();
  if (trimmed.isEmpty) {
    return;
  }

  if (isShellRootLocation(trimmed)) {
    context.go(trimmed);
    return;
  }

  context.push(trimmed);
}
