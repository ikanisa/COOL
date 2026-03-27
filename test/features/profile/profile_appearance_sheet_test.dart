import 'package:cool_app/core/theme/app_theme.dart';
import 'package:cool_app/core/theme/theme_preference.dart';
import 'package:cool_app/features/profile/widgets/profile_settings_widgets.dart';
import 'package:cool_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpSheet(
    WidgetTester tester, {
    required AppThemePreference currentPreference,
    required Future<void> Function(AppThemePreference preference) onSelected,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ProfileAppearanceSheet(
            currentPreference: currentPreference,
            onSelected: onSelected,
          ),
        ),
      ),
    );
  }

  testWidgets('shows all appearance options and descriptions', (tester) async {
    await pumpSheet(
      tester,
      currentPreference: AppThemePreference.system,
      onSelected: (_) async {},
    );

    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('System'), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget);
    expect(find.text('Light'), findsNothing);
  });

  testWidgets('reports the selected theme preference', (tester) async {
    AppThemePreference? selectedPreference;

    await pumpSheet(
      tester,
      currentPreference: AppThemePreference.system,
      onSelected: (preference) async {
        selectedPreference = preference;
      },
    );

    await tester.tap(find.text('Dark'));
    await tester.pump();

    expect(selectedPreference, AppThemePreference.dark);
  });
}
