import 'dart:async';

import 'package:collect_app/admin/core/admin_error_boundary.dart';
import 'package:collect_app/app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:collect_app/core/cloudflare/collect_cloudflare_client.dart';

const _privateMarker = 'synthetic-private-provider-secret-970011';
const _phone = '+250788970011';
const _receipt = 'Transaction970011 payer $_phone amount42000';

void main() {
  final corpus = <String, Object>{
    'SDK Auth': const CollectAuthException('$_privateMarker phone=$_phone JWT'),
    'SDK database': const CollectApiException(
      message: 'permission denied $_privateMarker',
      code: '42501',
      details: 'SELECT raw_sms FROM private_table WHERE phone=$_phone',
      hint: _receipt,
    ),
    'SQL format': const FormatException(
      'INSERT INTO private_table VALUES ($_privateMarker, $_phone)',
    ),
    'nested provider JSON': const CollectFunctionException(
      status: 502,
      details: {
        'authorization': 'Bearer $_privateMarker',
        'request': {'phone': _phone, 'receipt': _receipt},
        'provider': {'trace': 'SELECT * FROM private_table'},
      },
      reasonPhrase: 'Upstream secret $_privateMarker',
    ),
    'provider timeout': TimeoutException(
      'https://synthetic.invalid?token=$_privateMarker&phone=$_phone',
    ),
    'unknown body': StateError('$_privateMarker $_phone $_receipt'),
    'raw receipt': _receipt,
    'session SDK': const CollectAuthException(
      'Session unavailable $_privateMarker',
    ),
    'network SDK': StateError('Socket failure $_privateMarker $_phone'),
  };
  const safeMessages = {
    'Your admin session needs to be refreshed.',
    'This admin profile is not allowed to perform that action.',
    'The admin service could not be reached.',
    'The admin request could not be completed.',
  };
  for (final entry in corpus.entries) {
    test('${entry.key} exposes only an allowlisted recovery message', () {
      final result = adminSafeErrorMessage(entry.value);
      expect(safeMessages, contains(result));
      for (final private in [
        _privateMarker,
        _phone,
        _receipt,
        'private_table',
      ]) {
        expect(result, isNot(contains(private)));
      }
    });
  }
  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'rendered error has no private text or semantics at ${scale}x',
      (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final semantics = tester.ensureSemantics();
        var retries = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(
              body: SingleChildScrollView(
                child: AdminSafeErrorPanel(
                  error: corpus['nested provider JSON']!,
                  onRetry: () => retries++,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (final private in [
          _privateMarker,
          _phone,
          _receipt,
          'private_table',
        ]) {
          expect(find.textContaining(private), findsNothing);
          expect(
            find.bySemanticsLabel(RegExp(RegExp.escape(private))),
            findsNothing,
          );
        }
        await tester.ensureVisible(find.text('Retry'));
        await tester.tap(find.text('Retry'));
        expect(retries, 1);
        expect(tester.takeException(), isNull);
        semantics.dispose();
      },
    );
  }
}
