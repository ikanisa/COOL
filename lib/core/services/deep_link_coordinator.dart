import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../config/deep_link_config.dart';

class DeepLinkCoordinator {
  DeepLinkCoordinator({
    AppLinks? appLinks,
    required GoRouter Function() readRouter,
    required void Function(Uri uri, {required String route})
    captureReferralAttribution,
    required Future<void> Function() markReferralInviteOpenedIfNeeded,
    required Future<void> Function(Uri uri, String route) trackDeepLinkOpened,
  }) : _appLinks = appLinks ?? AppLinks(),
       _readRouter = readRouter,
       _captureReferralAttribution = captureReferralAttribution,
       _markReferralInviteOpenedIfNeeded = markReferralInviteOpenedIfNeeded,
       _trackDeepLinkOpened = trackDeepLinkOpened;

  final AppLinks _appLinks;
  final GoRouter Function() _readRouter;
  final void Function(Uri uri, {required String route})
  _captureReferralAttribution;
  final Future<void> Function() _markReferralInviteOpenedIfNeeded;
  final Future<void> Function(Uri uri, String route) _trackDeepLinkOpened;

  StreamSubscription<Uri>? _deepLinkSubscription;
  bool _started = false;

  Future<void> start() async {
    if (_started) {
      return;
    }
    _started = true;

    try {
      final initialUri = await _appLinks.getInitialLink();
      await _handleDeepLink(initialUri);
    } catch (_) {
      // Ignore deep-link bootstrap failures and fall back to normal startup.
    }

    _deepLinkSubscription = _appLinks.uriLinkStream.listen(
      (uri) => unawaited(_handleDeepLink(uri)),
      onError: (_) {
        // Ignore malformed links instead of interrupting the app session.
      },
    );
  }

  Future<void> _handleDeepLink(Uri? uri) async {
    if (uri == null) {
      return;
    }

    final route = DeepLinkConfig.routeForUri(uri);
    if (route == null) {
      return;
    }

    _captureReferralAttribution(uri, route: route);
    await _markReferralInviteOpenedIfNeeded();
    await _trackDeepLinkOpened(uri, route);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final router = _readRouter();
      if (router.routeInformationProvider.value.uri.toString() == route) {
        return;
      }
      router.go(route);
    });
  }

  void dispose() {
    _deepLinkSubscription?.cancel();
    _deepLinkSubscription = null;
    _started = false;
  }
}
