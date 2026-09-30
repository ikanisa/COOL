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
