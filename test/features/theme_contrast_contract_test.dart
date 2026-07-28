import 'package:collect_app/app/theme/app_theme.dart';
import 'package:collect_app/app/theme/collect_colors.dart';
import 'package:collect_app/app/theme/collect_component_tokens.dart';
import 'package:collect_app/app/theme/collect_runtime_tokens.dart';
import 'package:collect_app/app/theme/collect_universal_tokens.dart';
import 'package:collect_app/admin/shared/components/admin_status_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _normalTextMinimum = 4.5;
const _nonTextMinimum = 3.0;

void main() {
  group('WCAG contrast contract', () {
    for (final entry in <String, ThemeData>{
      'light': AppTheme.light(),
      'dark': AppTheme.dark(),
    }.entries) {
      test('${entry.key} text roles remain readable on every core surface', () {
        final colors = entry.value.extension<CollectColors>()!;
        final foregrounds = <String, Color>{
          'primary': colors.textPrimary,
          'secondary': colors.textSecondary,
          'muted': colors.textMuted,
        };
        final backgrounds = <String, Color>{
          'canvas': colors.canvas,
          'surface': colors.surfaceReadable,
          'raised': colors.surfaceRaised,
          'muted surface': colors.surfaceMuted,
        };

        for (final foreground in foregrounds.entries) {
          for (final background in backgrounds.entries) {
            _expectContrast(
              '${entry.key} ${foreground.key} text on ${background.key}',
              foreground.value,
              background.value,
              _normalTextMinimum,
            );
          }
        }
      });

      test('${entry.key} semantic status pairs remain readable', () {
        final colors = entry.value.extension<CollectColors>()!;
        for (final tone in CollectStatusTone.values) {
          _expectContrast(
            '${entry.key} ${tone.name} status',
            colors.statusForeground(tone),
            colors.statusBackground(tone),
            _normalTextMinimum,
          );
        }
      });

      test('${entry.key} Material semantic pairs remain readable', () {
        final scheme = entry.value.colorScheme;
        final pairs = <String, (Color, Color)>{
          'primary': (scheme.onPrimary, scheme.primary),
          'primary container': (
            scheme.onPrimaryContainer,
            scheme.primaryContainer,
          ),
          'secondary': (scheme.onSecondary, scheme.secondary),
          'secondary container': (
            scheme.onSecondaryContainer,
            scheme.secondaryContainer,
          ),
          'tertiary': (scheme.onTertiary, scheme.tertiary),
          'tertiary container': (
            scheme.onTertiaryContainer,
            scheme.tertiaryContainer,
          ),
          'error': (scheme.onError, scheme.error),
          'error container': (scheme.onErrorContainer, scheme.errorContainer),
          'surface': (scheme.onSurface, scheme.surface),
          'surface variant': (
            scheme.onSurfaceVariant,
            scheme.surfaceContainerHighest,
          ),
        };

        for (final pair in pairs.entries) {
          _expectContrast(
            '${entry.key} ${pair.key}',
            pair.value.$1,
            pair.value.$2,
            _normalTextMinimum,
          );
        }
      });

      testWidgets('${entry.key} shared action styles resolve to safe pairs', (
        tester,
      ) async {
        late ButtonStyle primary;
        late ButtonStyle destructive;
        late ButtonStyle outlined;
        await tester.pumpWidget(
          MaterialApp(
            theme: entry.value,
            home: Builder(
              builder: (context) {
                primary = CollectComponentTokens.filledButton(context);
                destructive = CollectComponentTokens.dangerButton(context);
                outlined = CollectComponentTokens.outlinedButton(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        );

        _expectStyleContrast(
          '${entry.key} primary action',
          primary,
          _normalTextMinimum,
        );
        _expectStyleContrast(
          '${entry.key} destructive action',
          destructive,
          _normalTextMinimum,
        );
        final colors = entry.value.extension<CollectColors>()!;
        final side = outlined.side?.resolve(<WidgetState>{});
        expect(side, isNotNull);
        _expectContrast(
          '${entry.key} outlined action boundary',
          side!.color,
          colors.surfaceReadable,
          _nonTextMinimum,
        );
      });

      test('${entry.key} enabled and focused controls remain perceivable', () {
        final colors = entry.value.extension<CollectColors>()!;
        final tokens = entry.value.extension<CollectUniversalTokens>()!;
        for (final surface in <String, Color>{
          'surface': colors.surfaceReadable,
          'muted surface': colors.surfaceMuted,
        }.entries) {
          final inputFill = Color.alphaBlend(
            CollectRuntimeTokens.inputFill(colors),
            surface.value,
          );
          _expectContrast(
            '${entry.key} enabled control on ${surface.key}',
            CollectRuntimeTokens.inputBorder(colors),
            inputFill,
            _nonTextMinimum,
          );
          _expectContrast(
            '${entry.key} focus ring on ${surface.key}',
            tokens.focusRing,
            inputFill,
            _nonTextMinimum,
          );
        }
      });
    }

    test('high-contrast themes use a 3:1-or-better focus and outline role', () {
      for (final entry in <String, ThemeData>{
        'high contrast light': AppTheme.highContrastLight(),
        'high contrast dark': AppTheme.highContrastDark(),
      }.entries) {
        final colors = entry.value.extension<CollectColors>()!;
        final tokens = entry.value.extension<CollectUniversalTokens>()!;
        expect(tokens.highContrast, isTrue);
        expect(tokens.focusRingWidth, greaterThanOrEqualTo(3));
        for (final surface in <String, Color>{
          'surface': colors.surfaceReadable,
          'muted surface': colors.surfaceMuted,
        }.entries) {
          _expectContrast(
            '${entry.key} focus on ${surface.key}',
            tokens.focusRing,
            surface.value,
            _nonTextMinimum,
          );
          _expectContrast(
            '${entry.key} outline on ${surface.key}',
            entry.value.colorScheme.outline,
            surface.value,
            _nonTextMinimum,
          );
        }
      }
    });

    test('primary and muted chrome copy clears every route gradient stop', () {
      const colors = CollectColors.light;
      final primary = CollectRuntimeTokens.chromeForeground(colors);
      final muted = CollectRuntimeTokens.chromeMutedForeground(colors);
      const routePaths = <String>[
        '/home',
        '/groups',
        '/groups/create',
        '/groups/example/contribute',
        '/groups/example/share',
        '/settings',
        '/settings/legal/privacy',
        '/offline',
      ];

      for (final path in routePaths) {
        final gradient = colors.screenGradientForPath(path) as LinearGradient;
        for (var index = 0; index < gradient.colors.length; index += 1) {
          final background = gradient.colors[index];
          _expectContrast(
            '$path primary chrome at stop $index',
            primary,
            background,
            _normalTextMinimum,
          );
          _expectContrast(
            '$path muted chrome at stop $index',
            muted,
            background,
            _normalTextMinimum,
          );
        }
      }
    });

    for (final theme in <String, ThemeData>{
      'light': AppTheme.light(),
      'dark': AppTheme.dark(),
    }.entries) {
      testWidgets('${theme.key} Admin status chips use compliant token pairs', (
        tester,
      ) async {
        for (final label in <String>[
          'pending',
          'blocked',
          'active',
          'unknown',
        ]) {
          await tester.pumpWidget(
            MaterialApp(
              theme: theme.value,
              home: Scaffold(
                body: Center(child: AdminStatusChip(label: label)),
              ),
            ),
          );

          final chip = find.byType(AdminStatusChip);
          final decorated = tester.widget<DecoratedBox>(
            find.descendant(of: chip, matching: find.byType(DecoratedBox)),
          );
          final decoration = decorated.decoration as BoxDecoration;
          final text = tester.widget<Text>(find.text(label));
          _expectContrast(
            '${theme.key} Admin $label status chip',
            text.style!.color!,
            decoration.color!,
            _normalTextMinimum,
          );
        }
      });
    }
  });
}

void _expectStyleContrast(String label, ButtonStyle style, double minimum) {
  final states = <WidgetState>{};
  final foreground = style.foregroundColor?.resolve(states);
  final background = style.backgroundColor?.resolve(states);
  expect(foreground, isNotNull, reason: '$label foreground is unresolved');
  expect(background, isNotNull, reason: '$label background is unresolved');
  _expectContrast(label, foreground!, background!, minimum);
}

void _expectContrast(
  String label,
  Color foreground,
  Color background,
  double minimum,
) {
  final opaqueBackground = _onOpaque(background, CollectColors.publicWhite);
  final visibleForeground = _onOpaque(foreground, opaqueBackground);
  final ratio = _contrastRatio(visibleForeground, opaqueBackground);
  expect(
    ratio,
    greaterThanOrEqualTo(minimum),
    reason:
        '$label measured ${ratio.toStringAsFixed(3)}:1; '
        'required ${minimum.toStringAsFixed(1)}:1',
  );
}

Color _onOpaque(Color color, Color background) {
  return color.a < 1 ? Color.alphaBlend(color, background) : color;
}

double _contrastRatio(Color foreground, Color background) {
  final foregroundLuminance = foreground.computeLuminance();
  final backgroundLuminance = background.computeLuminance();
  final lighter = foregroundLuminance > backgroundLuminance
      ? foregroundLuminance
      : backgroundLuminance;
  final darker = foregroundLuminance > backgroundLuminance
      ? backgroundLuminance
      : foregroundLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}
