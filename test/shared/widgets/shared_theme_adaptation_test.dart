import 'package:cool_app/core/theme/app_theme.dart';
import 'package:cool_app/core/theme/cool_foundations.dart';
import 'package:cool_app/shared/widgets/balance_card.dart';
import 'package:cool_app/shared/widgets/cool_button.dart';
import 'package:cool_app/shared/widgets/cool_card.dart';
import 'package:cool_app/shared/widgets/cool_screen_scaffold.dart';
import 'package:cool_app/shared/widgets/driver_card.dart';
import 'package:cool_app/shared/widgets/tab_pill.dart';
import 'package:cool_app/shared/widgets/trip_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrapWithBrightness(Brightness brightness, Widget child) {
  return MaterialApp(
    theme: brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  group('Shared widgets adapt to theme brightness', () {
    testWidgets('CoolCard resolves light semantic surface by brightness', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrapWithBrightness(
          Brightness.light,
          const CoolCard(useGradient: false, child: Text('Card content')),
        ),
      );

      final ink = tester.widget<Ink>(
        find.descendant(of: find.byType(CoolCard), matching: find.byType(Ink)),
      );
      final decoration = ink.decoration! as ShapeDecoration;

      expect(decoration.color, CoolSemanticColors.light.cardSurface);
    });

    testWidgets('CoolButton secondary variant resolves light surface tokens', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrapWithBrightness(
          Brightness.light,
          CoolButton(
            label: 'Cancel',
            onTap: () {},
            variant: CoolButtonVariant.secondary,
          ),
        ),
      );

      final ink = tester.widget<Ink>(
        find.descendant(
          of: find.byType(CoolButton),
          matching: find.byType(Ink),
        ),
      );
      final decoration = ink.decoration! as BoxDecoration;

      expect(decoration.color, Colors.transparent);
      expect(decoration.border, isNull);
    });

    testWidgets('CoolScreenScaffold resolves light background token', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: const CoolScreenScaffold(child: Text('Body')),
        ),
      );

      // CoolScreenScaffold uses CoolScreenBackground wrapper with a
      // transparent Scaffold — verify that pattern.
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.backgroundColor, Colors.transparent);
    });

    testWidgets('TabPill active state resolves light accent tokens', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrapWithBrightness(
          Brightness.light,
          TabPill(label: 'Selected', isActive: true, onTap: () {}),
        ),
      );

      final container = tester.widget<AnimatedContainer>(
        find.byType(AnimatedContainer),
      );
      final decoration = container.decoration! as BoxDecoration;

      expect(
        decoration.color,
        CoolSemanticColors.light.buttonPrimaryBackground,
      );
      expect(decoration.border, isNull);
    });

    testWidgets('DriverCard resolves light proximity surface token', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrapWithBrightness(
          Brightness.light,
          const DriverCard(
            driverId: 'd1',
            displayName: 'Jean Driver',
            vehicleType: 'Car',
            distanceKm: 2.5,
            isOnline: true,
            onWhatsAppTap: _noop,
          ),
        ),
      );

      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Container &&
              widget.decoration is BoxDecoration &&
              (widget.decoration! as BoxDecoration).color ==
                  CoolSemanticColors.light.proximitySurface,
        ),
        findsOneWidget,
      );
    });

    testWidgets('TripCard resolves light route surface token', (tester) async {
      await tester.pumpWidget(
        _wrapWithBrightness(
          Brightness.light,
          TripCard(
            fromLocation: 'Kigali',
            toLocation: 'Musanze',
            departureTime: DateTime(2026, 3, 22, 9, 30),
            vehicleType: 'Car',
            onTap: _noop,
          ),
        ),
      );

      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Container &&
              widget.decoration is BoxDecoration &&
              (widget.decoration! as BoxDecoration).color ==
                  CoolSemanticColors.light.routeSurface,
        ),
        findsOneWidget,
      );
    });

    testWidgets('BalanceCard resolves light financial surface token', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrapWithBrightness(
          Brightness.light,
          const BalanceCard(
            amount: 125000,
            currency: 'RWF',
            changeAmount: 4500,
          ),
        ),
      );

      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Container &&
              widget.decoration is BoxDecoration &&
              (widget.decoration! as BoxDecoration).color ==
                  CoolSemanticColors.light.financialSurface,
        ),
        findsOneWidget,
      );
    });
  });
}

void _noop() {}
