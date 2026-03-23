import 'package:cool_app/core/config/country_catalog.dart';
import 'package:cool_app/l10n/app_localizations.dart';
import 'package:cool_app/shared/widgets/kill_switch_gate.dart';
import 'package:cool_app/shared/widgets/member_row.dart';
import 'package:cool_app/shared/widgets/momo_route_type_selector.dart';
import 'package:cool_app/shared/widgets/vehicle_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  home: Scaffold(body: Center(child: child)),
);

void main() {
  group('utility and selection widgets', () {
    testWidgets('MemberRow renders identity and formatted contribution', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const MemberRow(
            userId: 'user_1234567890',
            displayName: '123456',
            contributionAmount: 125000,
            isAdmin: true,
          ),
        ),
      );

      expect(find.text('123456'), findsOneWidget);
      expect(find.text('Admin'), findsOneWidget);
      expect(find.text('125,000'), findsOneWidget);
    });

    testWidgets('VehicleChip invokes onTap', (tester) async {
      var tapped = false;

      await tester.pumpWidget(
        _wrap(
          VehicleChip(
            label: 'Car',
            isSelected: true,
            onTap: () => tapped = true,
          ),
        ),
      );

      await tester.tap(find.byType(VehicleChip));
      await tester.pumpAndSettle();

      expect(tapped, isTrue);
    });

    testWidgets('MomoRouteTypeSelector switches option', (tester) async {
      var selected = MomoRecipientType.phoneNumber;

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            return _wrap(
              MomoRouteTypeSelector(
                value: selected,
                onChanged: (value) {
                  setState(() {
                    selected = value;
                  });
                },
              ),
            );
          },
        ),
      );

      await tester.tap(find.text('MoMo Code'));
      await tester.pumpAndSettle();

      expect(selected, MomoRecipientType.code);
    });

    testWidgets('KillSwitchGate shows unavailable copy when disabled', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const KillSwitchGate(
            enabled: false,
            featureName: 'Mobile Money',
            child: SizedBox.shrink(),
          ),
        ),
      );

      expect(find.text('Temporarily Unavailable'), findsOneWidget);
      expect(find.textContaining('Mobile Money'), findsOneWidget);
    });
  });
}
