import 'package:cool_app/core/status/screens/referral_screen.dart';
import 'package:cool_app/features/auth/models/user_profile.dart';
import 'package:cool_app/features/auth/providers/auth_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('ReferralScreen renders the tracked invite share surface', (
    tester,
  ) async {
    const user = UserProfile(
      id: 'a24625ec-1be4-4af6-9cc6-b5635dbf4da4',
      phone: '+250788000111',
      fullName: 'Amina Test',
      publicUserId: 'CU-REF-99',
      momoNumber: '0788000111',
      momoProvider: 'mtn',
      country: 'RW',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [currentUserProvider.overrideWith((ref) => user)],
        child: const MaterialApp(home: ReferralScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Invite friends to COOL'), findsOneWidget);
    expect(find.text('Referral rewards'), findsOneWidget);
    expect(find.text('Share your referral link'), findsOneWidget);
    expect(find.text('Invite code'), findsOneWidget);
    expect(find.text('QR / Share'), findsOneWidget);
  });
}
