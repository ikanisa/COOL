import 'package:collect_app/admin/core/admin_evidence_mode.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _DirectoryRepository extends AdminEvidenceRepository {
  @override
  Future<AdminRuntimeConfig?> runtimeConfig() async => null;

  @override
  Future<AdminListResult> list(
    String rpcName, {
    String? search,
    String? status,
    int? limit,
    int? offset,
    String? sortBy,
    String? countryCode,
  }) async => const AdminListResult(
    total: 3,
    rows: [
      AdminTableRowData(
        id: 'synthetic-offline',
        title: 'Collect ID 900001',
        subtitle: 'Feature phone • +***1001',
        status: 'active',
        amount: '1 groups',
        extra: {
          'display_name': 'Synthetic offline member',
          'account_state': 'feature_phone',
          'momo_masked': '+***1001',
          'whatsapp_masked': null,
          'country_code': 'RW',
          'momo_provider': 'mtn_momo',
          'active_groups': 1,
        },
      ),
      AdminTableRowData(
        id: 'synthetic-app',
        title: 'Collect ID 900002',
        subtitle: 'App account • +***1002',
        status: 'admin',
        amount: '2 groups',
        extra: {
          'display_name': 'Synthetic app member',
          'account_state': 'app',
          'whatsapp_masked': '+***1002',
          'country_code': 'RW',
          'active_groups': 2,
        },
      ),
      AdminTableRowData(
        id: 'synthetic-claimed',
        title: 'Collect ID 900003',
        subtitle: 'App account • +***1003',
        status: 'active',
        amount: '1 groups',
        extra: {
          'account_state': 'app_claimed',
          'country_code': 'RW',
          'active_groups': 1,
        },
      ),
    ],
  );
}

void main() {
  for (final (width, scale) in [
    (390.0, 1.0),
    (1440.0, 1.0),
    (390.0, 2.0),
    (1440.0, 2.0),
  ]) {
    testWidgets('hybrid member identity at width $width and scale $scale', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            adminRepositoryProvider.overrideWithValue(_DirectoryRepository()),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: const Scaffold(
              body: AdminRpcListPage(
                title: 'Members',
                rpcName: 'admin_list_members',
                detailPathPrefix: '/admin/members',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Collect ID 900001'), findsOneWidget);
      expect(find.text('Synthetic offline member'), findsOneWidget);
      expect(find.text('Feature phone'), findsOneWidget);
      expect(find.text('MoMo +***1001'), findsOneWidget);
      expect(find.text('App account'), findsOneWidget);
      expect(find.text('WhatsApp +***1002'), findsOneWidget);
      expect(find.text('Claimed app account'), findsOneWidget);
      expect(find.text('Contact not recorded'), findsOneWidget);
      expect(find.text('Open member account'), findsNothing);
      expect(
        find.byTooltip('Open member record Collect ID 900001'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });
  }
}
