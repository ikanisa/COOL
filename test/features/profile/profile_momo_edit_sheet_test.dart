import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cool_app/core/config/country_catalog.dart';
import 'package:cool_app/features/profile/widgets/profile_momo_edit_sheet.dart';
import 'package:cool_app/l10n/app_localizations.dart';

void main() {
  group('ProfileMomoEditSheet', () {
    testWidgets(
      'saves a code-only route without triggering MoMo number validation',
      (tester) async {
        ProfileMomoEditResult? result;

        await tester.pumpWidget(
          _SheetHarness(
            onResult: (value) => result = value,
            child: ProfileMomoEditSheet(
              currentMomoNumber: '',
              currentMomoCode: '',
              currentMomoRouteType: null,
              country: CoolCountryCatalog.resolve(country: 'RW'),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField).at(1), '445566');
        await tester.tap(find.text('MoMo Code').last);
        await tester.pumpAndSettle();

        await tester.ensureVisible(find.text('Save'));
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();

        expect(
          find.text('MoMo number is required for the selected default route'),
          findsNothing,
        );
        expect(result, isNotNull);
        expect(result!.momoNumber, isEmpty);
        expect(result!.momoCode, '445566');
        expect(result!.momoRouteType, MomoRecipientType.code);
      },
    );

    testWidgets(
      'returns a code default route when both number and code are saved',
      (tester) async {
        ProfileMomoEditResult? result;

        await tester.pumpWidget(
          _SheetHarness(
            onResult: (value) => result = value,
            child: ProfileMomoEditSheet(
              currentMomoNumber: '',
              currentMomoCode: '',
              currentMomoRouteType: null,
              country: CoolCountryCatalog.resolve(country: 'RW'),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField).first, '0788000000');
        await tester.enterText(find.byType(TextField).at(1), '445566');
        await tester.tap(find.text('MoMo Code').last);
        await tester.pumpAndSettle();

        await tester.ensureVisible(find.text('Save'));
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();

        expect(result, isNotNull);
        expect(result!.momoNumber, '0788000000');
        expect(result!.momoCode, '445566');
        expect(result!.momoRouteType, MomoRecipientType.code);
      },
    );
  });
}

class _SheetHarness extends StatelessWidget {
  const _SheetHarness({required this.child, required this.onResult});

  final Widget child;
  final ValueChanged<ProfileMomoEditResult?> onResult;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Navigator(
        onGenerateRoute: (_) => MaterialPageRoute<void>(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  final result =
                      await showModalBottomSheet<ProfileMomoEditResult>(
                        context: context,
                        isScrollControlled: true,
                        builder: (_) => child,
                      );
                  onResult(result);
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
