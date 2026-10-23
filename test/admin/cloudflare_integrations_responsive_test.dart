import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/admin/core/cloudflare_admin_email_pages.dart';
import 'package:collect_app/admin/core/cloudflare_admin_gateway_pages.dart';
import 'package:collect_app/admin/shared/components/admin_data_table.dart';
import 'package:collect_app/admin/core/cloudflare_admin_receipt_pages.dart';
import 'package:collect_app/admin/core/cloudflare_admin_session.dart';
import 'package:collect_app/app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'cloudflare_integrations_fixtures.dart';
import 'cloudflare_operating_repository_test.dart' show operatingResponse;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/typefaces/Inter-Variable.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  for (final width in [320.0, 1440.0]) {
    for (final scale in [1.0, 2.0]) {
      for (final area in ['email', 'receipt', 'gateway']) {
        testWidgets(
          '$area list at ${width}px and ${scale}x text stays readable and filterable',
          (tester) async {
            tester.view.physicalSize = Size(width, 1000);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final filters = <String?>[];
            final repo = await integrationRepository((request) async {
              filters.add(request.url.queryParameters['status']);
              if (area == 'email') {
                final status =
                    request.url.queryParameters['status'] ?? 'accepted';
                return operatingResponse({
                  'rows': [
                    {
                      ...integrationEmail(),
                      'status': status,
                      if (status != 'accepted') 'accepted_at': null,
                    },
                  ],
                  'total': 1,
                  'limit': 25,
                  'offset': 0,
                });
              }
              if (area == 'gateway') {
                return operatingResponse({
                  'rows': [integrationDevice()],
                  'total': 1,
                });
              }
              return operatingResponse({
                'rows': [integrationReceipt()],
                'total': 1,
              });
            });
            final container = ProviderContainer(
              overrides: [
                adminRepositoryProvider.overrideWithValue(repo),
                cloudflareAdminSessionProvider.overrideWith(
                  (ref) => repo.session,
                ),
              ],
            );
            addTearDown(container.dispose);
            await tester.pumpWidget(
              UncontrolledProviderScope(
                container: container,
                child: MaterialApp(
                  theme: AppTheme.light(),
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: TextScaler.linear(scale)),
                    child: child!,
                  ),
                  home: Scaffold(
                    body: switch (area) {
                      'email' => const CloudflareEmailPage(),
                      'gateway' => const CloudflareGatewayListPage(),
                      _ => const CloudflareMemberReceiptListPage(),
                    },
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            expect(find.byType(AdminDataTable), findsOneWidget);
            expect(find.byType(ListTile), findsNothing);
            final table = tester.widget<AdminDataTable>(
              find.byType(AdminDataTable),
            );
            final expected = switch (area) {
              'email' => [
                'Notification',
                'Recipient',
                'Status',
                'Attempts',
                'Created',
                'Updated',
                'Provider accepted',
                'Delivery recorded',
                'Event ID',
              ],
              'gateway' => [
                'Device',
                'State',
                'App ID',
                'Last heartbeat',
                'Created',
                'Activated',
                'Revoked',
                'Version',
                'Device ID',
              ],
              _ => [
                'Member ID',
                'Member name',
                'Review status',
                'Received',
                'Created',
                'Reviewed',
                'Attached transaction ID',
                'Version',
                'Submission ID',
                'User record ID',
                'Source SHA-256',
              ],
            };
            expect(table.columns!.map((column) => column.label), expected);
            final numeric = tester
                .widget<DataTable>(find.byType(DataTable))
                .columns;
            for (var i = 0; i < table.columns!.length; i++) {
              expect(numeric[i].numeric, table.columns![i].numeric);
            }
            expect(
              tester
                  .widget<Scrollbar>(
                    find.descendant(
                      of: find.byType(AdminDataTable),
                      matching: find.byType(Scrollbar),
                    ),
                  )
                  .thumbVisibility,
              isTrue,
            );
            final horizontal = tester
                .state<ScrollableState>(
                  find
                      .descendant(
                        of: find.byType(AdminDataTable),
                        matching: find.byType(Scrollable),
                      )
                      .first,
                )
                .position;
            expect(horizontal.maxScrollExtent, greaterThan(0));
            final focus = tester.widget<Focus>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is Focus &&
                    widget.focusNode?.debugLabel ==
                        'Admin table horizontal scrolling',
              ),
            );
            focus.focusNode!.requestFocus();
            await tester.pump();
            await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
            await tester.pump();
            expect(horizontal.pixels, greaterThan(0));
            final name = switch (area) {
              'email' => 'Member Notification',
              'gateway' => 'Example gateway',
              _ => 'Example member',
            };
            expect(find.text(name), findsOneWidget);
            expect(tester.takeException(), isNull);
            if (area == 'email') {
              final field = find.byType(DropdownButtonFormField<String>);
              await tester.ensureVisible(field);
              await tester.pumpAndSettle();
              await tester.tap(field);
              await tester.pumpAndSettle();
              await tester.tap(find.text('Reserved for sending').last);
              await tester.pumpAndSettle();
              expect(filters.last, 'leased');
              expect(find.text('Reserved for sending'), findsWidgets);
              expect(tester.takeException(), isNull);
            }
            repo.session.clear();
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpAndSettle();
          },
        );
      }
    }
  }
}
