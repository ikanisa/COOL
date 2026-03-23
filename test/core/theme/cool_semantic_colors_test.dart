import 'package:cool_app/core/theme/cool_foundations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CoolSemanticColors', () {
    group('dark / light parity', () {
      test('dark and light define the same set of non-null properties', () {
        final dark = CoolSemanticColors.dark;
        final light = CoolSemanticColors.light;

        // Core surfaces
        expect(dark.appBackground, isNotNull);
        expect(light.appBackground, isNotNull);
        expect(dark.cardSurface, isNotNull);
        expect(light.cardSurface, isNotNull);
        expect(dark.glassSurface, isNotNull);
        expect(light.glassSurface, isNotNull);

        // Text
        expect(dark.primaryText, isNotNull);
        expect(light.primaryText, isNotNull);

        // Accents
        expect(dark.accent, isNotNull);
        expect(light.accent, isNotNull);
        expect(dark.buttonPrimaryBackground, isNotNull);
        expect(light.buttonPrimaryBackground, isNotNull);
      });

      test('dark and light produce different backgrounds', () {
        expect(
          CoolSemanticColors.dark.appBackground,
          isNot(equals(CoolSemanticColors.light.appBackground)),
        );
      });

      test('dark and light share the same primary action color', () {
        expect(
          CoolSemanticColors.dark.buttonPrimaryBackground,
          equals(CoolSemanticColors.light.buttonPrimaryBackground),
        );
      });
    });

    group('status colors', () {
      test('success, warning, danger, info are distinct', () {
        final colors = CoolSemanticColors.dark;
        final statusSet = {
          colors.success,
          colors.warning,
          colors.danger,
          colors.info,
        };
        expect(statusSet.length, 4, reason: 'All status colors must be unique');
      });

      test('status colors exist in both brightness variants', () {
        // Status colors may differ across brightness for contrast
        expect(CoolSemanticColors.dark.success, isNotNull);
        expect(CoolSemanticColors.light.success, isNotNull);
        expect(CoolSemanticColors.dark.danger, isNotNull);
        expect(CoolSemanticColors.light.danger, isNotNull);
        expect(CoolSemanticColors.dark.warning, isNotNull);
        expect(CoolSemanticColors.light.warning, isNotNull);
        expect(CoolSemanticColors.dark.info, isNotNull);
        expect(CoolSemanticColors.light.info, isNotNull);
      });
    });

    group('domain surfaces', () {
      test('domain surfaces are all non-null and distinct', () {
        final c = CoolSemanticColors.dark;
        final surfaceSet = {
          c.operationalSurface,
          c.financialSurface,
          c.analyticsSurface,
          c.teamSurface,
          c.commerceSurface,
          c.routeSurface,
          c.proximitySurface,
          c.contactSurface,
        };
        expect(surfaceSet.length, 8, reason: 'All domain surfaces unique');
      });
    });

    group('gradient tokens', () {
      test('accentGradient has exactly 2 blue-toned colors', () {
        final gradient = CoolSemanticColors.dark.accentGradient;
        expect(gradient.colors.length, 2);
        // Both should be blue-range (hue ~210-230)
        for (final color in gradient.colors) {
          final hsl = HSLColor.fromColor(color);
          expect(hsl.hue, inInclusiveRange(200, 230),
              reason: 'Gradient colors should be blue');
        }
      });

      test('accentGradient is consistent across brightness', () {
        expect(
          CoolSemanticColors.dark.accentGradient.colors,
          CoolSemanticColors.light.accentGradient.colors,
        );
      });
    });

    group('lerp', () {
      test('lerp at 0.0 returns a-like colors', () {
        final a = CoolSemanticColors.dark;
        final b = CoolSemanticColors.light;
        final lerped = a.lerp(b, 0.0);

        expect(lerped.appBackground, a.appBackground);
        expect(lerped.primaryText, a.primaryText);
        expect(lerped.accent, a.accent);
      });

      test('lerp at 1.0 returns b-like colors', () {
        final a = CoolSemanticColors.dark;
        final b = CoolSemanticColors.light;
        final lerped = a.lerp(b, 1.0);

        expect(lerped.appBackground, b.appBackground);
        expect(lerped.primaryText, b.primaryText);
        expect(lerped.accent, b.accent);
      });

      test('lerp at 0.5 produces an intermediate color', () {
        final a = CoolSemanticColors.dark;
        final b = CoolSemanticColors.light;
        final lerped = a.lerp(b, 0.5);

        // Intermediate should differ from both endpoints
        expect(lerped.appBackground, isNot(a.appBackground));
        expect(lerped.appBackground, isNot(b.appBackground));
      });
    });

    group('copyWith', () {
      test('copyWith preserves all fields when no args given', () {
        final original = CoolSemanticColors.dark;
        final copy = original.copyWith();

        expect(copy.appBackground, original.appBackground);
        expect(copy.primaryText, original.primaryText);
        expect(copy.accent, original.accent);
        expect(copy.buttonPrimaryBackground,
            original.buttonPrimaryBackground);
        expect(copy.cardSurface, original.cardSurface);
        expect(copy.success, original.success);
        expect(copy.danger, original.danger);
      });

      test('copyWith overrides only the specified field', () {
        final original = CoolSemanticColors.dark;
        const override = Color(0xFFFF00FF);
        final copy = original.copyWith(appBackground: override);

        expect(copy.appBackground, override);
        // All other fields unchanged
        expect(copy.primaryText, original.primaryText);
        expect(copy.accent, original.accent);
        expect(copy.cardSurface, original.cardSurface);
      });
    });

    group('demand colors', () {
      test('demand colors form a severity gradient', () {
        final c = CoolSemanticColors.dark;
        // All three should exist and be distinct
        expect({c.demandHigh, c.demandMedium, c.demandLow}.length, 3);
      });
    });
  });
}
