import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class PageTitleObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _updateTitle(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (newRoute != null) {
      _updateTitle(newRoute);
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute != null) {
      _updateTitle(previousRoute);
    }
  }

  void _updateTitle(Route<dynamic> route) {
    if (!kIsWeb) {
      return;
    }

    final name = route.settings.name;
    final title = routeTitleFor(name);
    SystemChrome.setApplicationSwitcherDescription(
      ApplicationSwitcherDescription(label: title, primaryColor: 0xFF0D0A27),
    );
  }
}

/// Maps route paths to human-readable page titles for the browser tab.
String routeTitleFor(String? path) {
  if (path == null || path.isEmpty || path == '/') {
    return 'COOL';
  }

  final basePath = path.split('?').first;
  const titles = <String, String>{
    '/home': 'Home — COOL',
    '/groups': 'Groups — COOL',
    '/contribution-circles': 'Contribution Circles — COOL',
    '/referral': 'Referrals — COOL',
    '/momo': 'MoMo — COOL',
    '/momo/statements': 'MoMo Statements — COOL',
    '/momo/biopay': 'BioPay — COOL',
    '/momo/biopay/profile': 'BioPay Profile — COOL',
    '/momo/biopay/register': 'BioPay Register — COOL',
    '/momo/biopay/qr': 'BioPay QR — COOL',
    '/momo/biopay/scan': 'BioPay Scan — COOL',
    '/momo/biopay/nfc': 'BioPay NFC — COOL',
    '/momo/biopay/success': 'BioPay Ready — COOL',
    '/profile': 'Profile — COOL',
    '/profile/wallet': 'Wallet — COOL',
    '/profile/account': 'Account — COOL',
    '/profile/notifications': 'Notifications — COOL',
    '/profile/privacy': 'Privacy & Security — COOL',
    '/profile/orders': 'Orders — COOL',
    '/profile/help': 'Help — COOL',
    '/profile/about': 'About — COOL',
    '/admin': 'Admin — COOL',
    '/admin/platform': 'Platform — COOL Admin',
    '/admin/users': 'Users — COOL Admin',
    '/admin/app-config': 'App Config — COOL Admin',
    '/admin/operations': 'Operations — COOL Admin',
    '/admin/roles': 'Roles — COOL Admin',
    '/admin/analytics': 'Analytics — COOL Admin',
    '/admin/audit-log': 'Audit Log — COOL Admin',
    '/scanner': 'Scanner — COOL',
  };

  final exact = titles[basePath];
  if (exact != null) {
    return exact;
  }

  if (basePath.startsWith('/contribution-circles/')) {
    return 'Group Details — COOL';
  }
  if (basePath.startsWith('/invite/')) {
    return 'Invitation — COOL';
  }
  if (basePath.startsWith('/admin/banks/')) {
    return 'Bank Workspace — COOL Admin';
  }

  return 'COOL';
}
