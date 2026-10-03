import 'dart:ui' as ui;

import 'package:collect_app/app/theme/app_theme.dart';
import 'package:collect_app/app/theme/collect_component_tokens.dart';
import 'package:collect_app/shared/widgets/collect_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Preserve the existing fix: disabled takes priority over pressed/hover/focus.
  for (final dark in [false, true]) {
    testWidgets(
      'raw filled controls keep disabled text and icons legible in ${dark ? 'dark' : 'light'} mode',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final theme = dark ? AppTheme.dark() : AppTheme.light();
        final colors = theme.extension<CollectColors>()!;
        var activations = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: Column(
                children: [
                  FilledButton.icon(
                    key: const ValueKey('disabled-raw-action'),
                    onPressed: null,
                    icon: const Icon(Icons.phonelink_ring_outlined),
                    label: const Text('Enroll device'),
                  ),
                  FilledButton.icon(
                    key: const ValueKey('active-raw-action'),
                    onPressed: () => activations++,
                    icon: const Icon(Icons.check),
                    label: const Text('Continue'),
                  ),
                ],
              ),
            ),
          ),
        );
        final disabled = find.byKey(const ValueKey('disabled-raw-action'));
        final labelColor = DefaultTextStyle.of(
          tester.element(find.text('Enroll device')),
        ).style.color!;
        final iconColor = IconTheme.of(
          tester.element(find.byIcon(Icons.phonelink_ring_outlined)),
        ).color!;
        expect(labelColor, colors.textMuted);
        expect(iconColor, colors.textMuted);
        final material = tester.widget<Material>(
          find.descendant(of: disabled, matching: find.byType(Material)).first,
        );
        expect(material.color, colors.neutralContainer);
        final paintedBackground = Color.alphaBlend(
          material.color!,
          theme.scaffoldBackgroundColor,
        );
        final textLuminance = labelColor.computeLuminance();
        final backgroundLuminance = paintedBackground.computeLuminance();
        final contrast = (textLuminance > backgroundLuminance)
            ? (textLuminance + 0.05) / (backgroundLuminance + 0.05)
            : (backgroundLuminance + 0.05) / (textLuminance + 0.05);
        expect(contrast, greaterThanOrEqualTo(4.5));
        for (final states in <Set<WidgetState>>[
          {WidgetState.disabled},
          {WidgetState.disabled, WidgetState.pressed},
          {WidgetState.disabled, WidgetState.hovered, WidgetState.focused},
        ]) {
          final style = theme.filledButtonTheme.style!;
          expect(style.foregroundColor!.resolve(states), colors.textMuted);
          expect(
            style.backgroundColor!.resolve(states),
            colors.neutralContainer,
          );
        }
        final disabledSemantics = tester
            .getSemantics(disabled)
            .getSemanticsData();
        expect(
          disabledSemantics.flagsCollection.isEnabled,
          ui.Tristate.isFalse,
        );
        expect(disabledSemantics.hasAction(ui.SemanticsAction.tap), isFalse);
        await tester.tap(disabled);
        expect(activations, 0);
        expect(
          DefaultTextStyle.of(
            tester.element(find.text('Continue')),
          ).style.color,
          colors.onAccent,
        );
        expect(
          IconTheme.of(tester.element(find.byIcon(Icons.check))).color,
          colors.onAccent,
        );
        final active = find.byKey(const ValueKey('active-raw-action'));
        expect(
          tester
              .widget<Material>(
                find
                    .descendant(of: active, matching: find.byType(Material))
                    .first,
              )
              .color,
          theme.colorScheme.primary,
        );
        await tester.tap(active);
        expect(activations, 1);
        semantics.dispose();
      },
    );

    testWidgets(
      'disabled danger styling remains neutral in ${dark ? 'dark' : 'light'} mode',
      (tester) async {
        late ButtonStyle style;
        late CollectColors colors;
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? AppTheme.dark() : AppTheme.light(),
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  colors = context.collectColors;
                  style = CollectComponentTokens.dangerButton(context);
                  return const CollectButton(
                    label: 'Delete test record',
                    variant: CollectButtonVariant.danger,
                  );
                },
              ),
            ),
          ),
        );
        for (final states in <Set<WidgetState>>[
          {WidgetState.disabled},
          {WidgetState.disabled, WidgetState.pressed},
          {WidgetState.disabled, WidgetState.hovered, WidgetState.focused},
        ]) {
          expect(
            style.backgroundColor!.resolve(states),
            colors.neutralContainer,
          );
          expect(style.foregroundColor!.resolve(states), colors.textMuted);
        }
        expect(
          tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNull,
        );
        expect(style.backgroundColor!.resolve({}), colors.danger);
      },
    );
  }

  testWidgets('disabled destructive action has no tap semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: CollectButton(
            label: 'Delete test record',
            variant: CollectButtonVariant.danger,
          ),
        ),
      ),
    );
    final data = tester
        .getSemantics(find.byType(FilledButton))
        .getSemanticsData();
    expect(data.flagsCollection.isButton, isTrue);
    expect(data.flagsCollection.isEnabled, ui.Tristate.isFalse);
    expect(data.hasAction(ui.SemanticsAction.tap), isFalse);
    semantics.dispose();
  });
}
