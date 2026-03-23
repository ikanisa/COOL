import 'package:cool_app/core/config/country_catalog.dart';
import 'package:cool_app/features/biopay/models/biopay_match_result.dart';
import 'package:cool_app/features/biopay/models/biopay_profile.dart';
import 'package:cool_app/features/biopay/providers/biopay_providers.dart';
import 'package:cool_app/features/biopay/screens/biopay_confirm_screen.dart';
import 'package:cool_app/features/biopay/services/biopay_auth_gate_service.dart';
import 'package:cool_app/features/biopay/services/biopay_dialer_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeBiopayAuthAdapter implements BiopayAuthAdapter {
  FakeBiopayAuthAdapter({
    this.isSupported = true,
    this.authenticateResult = true,
  });

  final bool isSupported;
  final bool authenticateResult;

  @override
  Future<bool> authenticate({
    required String localizedReason,
    bool biometricOnly = false,
    bool sensitiveTransaction = true,
    bool persistAcrossBackgrounding = false,
  }) async {
    return authenticateResult;
  }

  @override
  Future<bool> isDeviceSupported() async => isSupported;
}

class FakeBiopayDialerService extends BiopayDialerService {
  FakeBiopayDialerService({required this.shouldLaunch});

  final bool shouldLaunch;
  int dialCalls = 0;

  @override
  Future<bool> dialProfile(BiopayProfile profile) async {
    dialCalls += 1;
    return shouldLaunch;
  }
}

const _profile = BiopayProfile(
  id: 'profile-1',
  publicId: '123456',
  userId: 'user-1',
  displayName: 'Marie',
  routeType: MomoRecipientType.phoneNumber,
  recipientValue: '0781234567',
  countryCode: 'RW',
  active: true,
  consentVersion: 'biopay-v1',
);

const _matchResult = BiopayMatchResult(
  match: true,
  score: 0.93,
  profile: _profile,
);

void main() {
  testWidgets('blocks dial handoff when auth is denied', (tester) async {
    final dialer = FakeBiopayDialerService(shouldLaunch: true);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          biopayAuthGateServiceProvider.overrideWithValue(
            BiopayAuthGateService(
              adapter: FakeBiopayAuthAdapter(authenticateResult: false),
            ),
          ),
          biopayDialerServiceProvider.overrideWithValue(dialer),
        ],
        child: const MaterialApp(
          home: BiopayConfirmScreen(result: _matchResult),
        ),
      ),
    );

    await tester.tap(find.text('Tap to Dial'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(dialer.dialCalls, 0);
    expect(
      find.text(
        'BioPay payment handoff was canceled before identity confirmation completed.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('opens dialer after successful auth', (tester) async {
    final dialer = FakeBiopayDialerService(shouldLaunch: true);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          biopayAuthGateServiceProvider.overrideWithValue(
            BiopayAuthGateService(adapter: FakeBiopayAuthAdapter()),
          ),
          biopayDialerServiceProvider.overrideWithValue(dialer),
        ],
        child: const MaterialApp(
          home: BiopayConfirmScreen(result: _matchResult),
        ),
      ),
    );

    await tester.tap(find.text('Tap to Dial'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(dialer.dialCalls, 1);
    expect(find.text('MoMo dialer opened'), findsOneWidget);
  });
}
