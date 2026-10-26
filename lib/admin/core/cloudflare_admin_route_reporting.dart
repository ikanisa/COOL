import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Preserves encoded Admin URLs at the Flutter 3.44.4 web reporting boundary.
///
/// That engine decodes the complete `uri` navigation message before handing it
/// to the URL strategy. This flattens nested return queries and turns encoded
/// search punctuation into query delimiters. A URL strategy runs too late to
/// recover the original URI.
///
/// GoRouter still owns listeners, restoration state and push/replace decisions.
/// Its normal report is immediately followed by an encoded `location` report,
/// which the same engine accepts unchanged. Ordered navigation messages replace
/// that same entry and state; they do not introduce another Back entry. This is
/// an Admin-only compatibility adapter, not an engine or mobile change.
class CloudflareAdminRouteReporting extends RouteInformationProvider {
  CloudflareAdminRouteReporting({
    required this.delegate,
    this.preserveWebEncoding = kIsWeb,
  });

  final GoRouteInformationProvider delegate;
  final bool preserveWebEncoding;

  @override
  RouteInformation get value => delegate.value;

  @override
  void addListener(VoidCallback listener) => delegate.addListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      delegate.removeListener(listener);

  @override
  void routerReportsNewRouteInformation(
    RouteInformation routeInformation, {
    RouteInformationReportingType type = RouteInformationReportingType.none,
  }) {
    final before = delegate.value;
    delegate.routerReportsNewRouteInformation(routeInformation, type: type);
    if (!preserveWebEncoding ||
        !identical(delegate.value, routeInformation) ||
        type == RouteInformationReportingType.none &&
            identical(before, delegate.value)) {
      return;
    }
    // Invoke immediately after the delegate: the web engine serializes these
    // messages in arrival order, including rapid navigation and restoration.
    unawaited(
      SystemChannels.navigation
          .invokeMethod<void>('routeInformationUpdated', <String, Object?>{
            'location': routeInformation.uri.toString(),
            'state': routeInformation.state,
            'replace': true,
          }),
    );
  }
}
