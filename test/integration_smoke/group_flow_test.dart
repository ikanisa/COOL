import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cool_app/features/groups/screens/create_group_screen.dart';
import 'package:cool_app/features/partners/models/partner.dart';
import 'package:cool_app/features/partners/providers/partner_provider.dart';
import 'package:cool_app/shared/widgets/cool_button.dart';

import 'test_harness.dart';

void main() {
  group('Group (IBIMINA) smoke', () {
    const bankPartners = <Partner>[
      Partner(
        id: 'bank-1',
        name: 'BK Rwanda',
        slug: 'bk-rwanda',
        category: PartnerCategory.bank,
        country: 'RW',
      ),
    ];

    testWidgets('CreateGroupScreen renders type selector and form fields', (
      tester,
    ) async {
      await pumpScopedApp(
        tester,
        child: const CreateGroupScreen(),
        session: fakeSession(),
        user: fakeUser(momoNumber: '0788123456'),
        overrides: <Override>[
          currentCountryBankPartnersProvider.overrideWith(
            (ref) async => bankPartners,
          ),
        ],
      );

      expect(find.text('Create Group'), findsWidgets);

      // Both type cards visible
      expect(find.text('Group Saving'), findsOneWidget);
      expect(find.text('Community Fund'), findsOneWidget);

      // Form fields visible
      expect(find.text('Group Name'), findsOneWidget);
      expect(find.text('Saving Target (RWF)'), findsOneWidget);
      expect(find.text('More options'), findsOneWidget);
      expect(find.text('Description'), findsNothing);
    });

    testWidgets('form validation requires group name', (tester) async {
      await pumpScopedApp(
        tester,
        child: const CreateGroupScreen(),
        session: fakeSession(),
        user: fakeUser(momoNumber: '0788123456'),
        overrides: <Override>[
          currentCountryBankPartnersProvider.overrideWith(
            (ref) async => bankPartners,
          ),
        ],
      );

      final createButton = find.byType(CoolButton);
      await tester.ensureVisible(createButton);
      await tester.tap(createButton);
      await settleTestApp(tester);

      expect(find.text('Group name is required'), findsOneWidget);
    });

    testWidgets('form validation requires valid target amount', (
      tester,
    ) async {
      await pumpScopedApp(
        tester,
        child: const CreateGroupScreen(),
        session: fakeSession(),
        user: fakeUser(momoNumber: '0788123456'),
        overrides: <Override>[
          currentCountryBankPartnersProvider.overrideWith(
            (ref) async => bankPartners,
          ),
        ],
      );

      await tester.enterText(find.byType(TextFormField).first, 'Test Savings');
      await settleTestApp(tester);

      final createButton = find.byType(CoolButton);
      await tester.ensureVisible(createButton);
      await tester.tap(createButton);
      await settleTestApp(tester);

      expect(find.text('Enter a valid target amount'), findsOneWidget);
    });

    testWidgets('switching to Community Fund shows MOMO route fields', (
      tester,
    ) async {
      await pumpScopedApp(
        tester,
        child: const CreateGroupScreen(),
        session: fakeSession(),
        user: fakeUser(momoNumber: '0788123456'),
        overrides: <Override>[
          currentCountryBankPartnersProvider.overrideWith(
            (ref) async => bankPartners,
          ),
        ],
      );

      // Tap Community Fund type
      await tester.tap(find.text('Community Fund'));
      await settleTestApp(tester);

      // Should now show Collection Route section
      expect(find.text('Collection Route'), findsOneWidget);
      expect(find.text('Phone Number'), findsOneWidget);

      // Bank partner section should NOT be visible
      expect(find.text('Bank Partner (country matched)'), findsNothing);
    });

    testWidgets('displays frequency options (daily, weekly, monthly)', (
      tester,
    ) async {
      await pumpScopedApp(
        tester,
        child: const CreateGroupScreen(),
        session: fakeSession(),
        user: fakeUser(momoNumber: '0788123456'),
        overrides: <Override>[
          currentCountryBankPartnersProvider.overrideWith(
            (ref) async => bankPartners,
          ),
        ],
      );

      expect(find.text('Daily'), findsOneWidget);
      expect(find.text('Weekly'), findsOneWidget);
      expect(find.text('Monthly'), findsOneWidget);
    });
  });
}
