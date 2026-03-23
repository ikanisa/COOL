import 'package:cool_app/l10n/app_localizations.dart';
import 'package:cool_app/shared/widgets/qr_share_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => ProviderScope(
  child: MaterialApp(
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: Scaffold(body: child),
  ),
);

void main() {
  group('QrShareSheet', () {
    testWidgets('renders the invite surface', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const QrShareSheet(
            groupName: 'Goal Getters',
            inviteUrl: 'https://cool.app/invite/goal-getters',
          ),
        ),
      );

      expect(find.text('Invite to Goal Getters'), findsOneWidget);
      expect(find.text('Scan QR or share the link'), findsOneWidget);
      expect(find.text('Copy'), findsOneWidget);
      expect(find.textContaining('https://cool.app/invite'), findsOneWidget);
    });
  });
}
