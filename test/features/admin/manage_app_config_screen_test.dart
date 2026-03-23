import 'package:cool_app/core/config/country_catalog.dart';
import 'package:cool_app/core/config/app_config_repository.dart';
import 'package:cool_app/core/models/engagement_feature_flags.dart';
import 'package:cool_app/core/providers/engagement_providers.dart';
import 'package:cool_app/core/providers/supported_countries_provider.dart';
import 'package:cool_app/core/services/feature_flags_service.dart';
import 'package:cool_app/core/services/firebase_bootstrap_service.dart';
import 'package:cool_app/features/admin/providers/admin_providers.dart';
import 'package:cool_app/features/admin/repositories/admin_content_repository.dart';
import 'package:cool_app/features/admin/screens/manage_app_config_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}

class FakeFirebaseBootstrapService extends FirebaseBootstrapService {
  FakeFirebaseBootstrapService(this.available);

  final bool available;

  @override
  Future<bool> initialize() async => available;
}

class FakeFeatureFlagsService extends FeatureFlagsService {
  FakeFeatureFlagsService()
    : super(bootstrapService: FakeFirebaseBootstrapService(false));

  int refreshCalls = 0;

  @override
  Future<EngagementFeatureFlags> initialize() async {
    refreshCalls += 1;
    return current;
  }
}

class FakeAdminContentRepository extends AdminContentRepository {
  FakeAdminContentRepository(
    List<Map<String, dynamic>> configs, {
    List<Map<String, dynamic>> partners = const <Map<String, dynamic>>[],
    List<Map<String, dynamic>> paymentRoutes = const <Map<String, dynamic>>[],
  }) : _configs = configs.map(Map<String, dynamic>.from).toList(),
       _partners = partners.map(Map<String, dynamic>.from).toList(),
       _paymentRoutes = paymentRoutes.map(Map<String, dynamic>.from).toList(),
       super(client: MockSupabaseClient());

  final List<Map<String, dynamic>> _configs;
  final List<Map<String, dynamic>> _partners;
  final List<Map<String, dynamic>> _paymentRoutes;
  final List<Map<String, dynamic>> singleUpserts = <Map<String, dynamic>>[];
  final List<List<Map<String, dynamic>>> batchUpserts =
      <List<Map<String, dynamic>>>[];
  final List<Map<String, dynamic>> paymentRouteUpserts =
      <Map<String, dynamic>>[];
  final List<String> paymentRouteDeletes = <String>[];
  int fetchCount = 0;

  @override
  Future<List<Map<String, dynamic>>> fetchAppConfig({String? country}) async {
    fetchCount += 1;
    return _configs.map(Map<String, dynamic>.from).toList(growable: false);
  }

  @override
  Future<void> upsertAppConfig(Map<String, dynamic> config) async {
    singleUpserts.add(Map<String, dynamic>.from(config));
    _upsert(config);
  }

  @override
  Future<void> upsertAppConfigs(List<Map<String, dynamic>> configs) async {
    batchUpserts.add(
      configs.map(Map<String, dynamic>.from).toList(growable: false),
    );
    for (final config in configs) {
      _upsert(config);
    }
  }

  @override
  Future<List<Map<String, dynamic>>> fetchPartners({String? country}) async {
    return _partners.map(Map<String, dynamic>.from).toList(growable: false);
  }

  @override
  Future<List<Map<String, dynamic>>> fetchPartnerPaymentRoutes({
    String? partnerId,
    String? country,
  }) async {
    return _paymentRoutes
        .map(Map<String, dynamic>.from)
        .toList(growable: false);
  }

  @override
  Future<void> upsertPartnerPaymentRoute(Map<String, dynamic> route) async {
    final normalized = Map<String, dynamic>.from(route);
    paymentRouteUpserts.add(normalized);
    final routeId = normalized['id']?.toString();
    final index = _paymentRoutes.indexWhere(
      (row) => row['id']?.toString() == routeId && routeId != null,
    );
    if (index >= 0) {
      _paymentRoutes[index] = normalized;
    } else {
      _paymentRoutes.add(<String, dynamic>{
        ...normalized,
        'id': routeId ?? 'route-${_paymentRoutes.length + 1}',
        'partner_name': _partners.firstWhere(
          (partner) => partner['id'] == normalized['partner_id'],
          orElse: () => const <String, dynamic>{'name': 'Partner'},
        )['name'],
      });
    }
  }

  @override
  Future<void> deletePartnerPaymentRoute(String id) async {
    paymentRouteDeletes.add(id);
    _paymentRoutes.removeWhere((row) => row['id']?.toString() == id);
  }

  void _upsert(Map<String, dynamic> config) {
    final key = config['key'];
    final country = config['country'];
    final normalized = Map<String, dynamic>.from(config);
    final index = _configs.indexWhere(
      (row) => row['key'] == key && row['country'] == country,
    );
    if (index >= 0) {
      _configs[index] = normalized;
    } else {
      _configs.add(normalized);
    }
  }
}

Finder _textFieldWithLabel(String label) {
  return find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.labelText == label,
    description: 'TextField(labelText: $label)',
  );
}

Finder _dropdownFieldWithLabel(String label) {
  return find.byWidgetPredicate(
    (widget) =>
        widget is DropdownButtonFormField &&
        widget.decoration.labelText == label,
    description: 'DropdownButtonFormField(labelText: $label)',
  );
}

Future<void> _tapPrimaryButton(WidgetTester tester, String label) async {
  final button = find.widgetWithText(ElevatedButton, label);
  await tester.ensureVisible(button);
  await tester.tap(button);
}

void main() {
  final countries = <CoolCountry>[CoolCountryCatalog.resolve(country: 'RW')];

  testWidgets(
    'renders rollout cards, hides managed keys from generic list, and saves rollout changes',
    (tester) async {
      final repository = FakeAdminContentRepository(<Map<String, dynamic>>[
        <String, dynamic>{
          'key': 'feature_momo_stage',
          'value': 'pilot',
          'description': 'MoMo rollout stage',
          'country': null,
        },
        <String, dynamic>{
          'key': 'feature_momo_allowed_scope',
          'value': 'legacy-hidden',
          'description': 'Legacy hidden rollout key',
          'country': null,
        },
        <String, dynamic>{
          'key': 'kill_momo_payments',
          'value': 'false',
          'description': 'MoMo kill switch',
          'country': null,
        },
        <String, dynamic>{
          'key': 'feature_momo_admin_only',
          'value': 'false',
          'description': 'MoMo admin only',
          'country': null,
        },
        <String, dynamic>{
          'key': 'support_whatsapp',
          'value': '250700000000',
          'description': 'Support line',
          'country': null,
        },
        <String, dynamic>{
          'key': AppConfigKeys.mobilitySubscriptionMomoCode,
          'value': '008000',
          'description':
              'MoMo code used to receive mobility subscription payments.',
          'country': null,
        },
      ]);
      final featureFlagsService = FakeFeatureFlagsService();

      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            adminContentRepositoryProvider.overrideWithValue(repository),
            supportedCountriesProvider.overrideWith((ref) => countries),
            featureFlagsServiceProvider.overrideWithValue(featureFlagsService),
          ],
          child: const MaterialApp(home: ManageAppConfigScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Rollout Governance'), findsOneWidget);
      expect(find.text('Mobile Money'), findsOneWidget);
      expect(find.text('PILOT'), findsOneWidget);
      expect(find.text('Rwanda only'), findsWidgets);
      expect(find.text('feature_momo_allowed_scope'), findsNothing);

      await tester.ensureVisible(find.byIcon(Icons.tune_rounded).first);
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.tune_rounded).first);
      await tester.pumpAndSettle();

      expect(find.text('Mobile Money rollout'), findsOneWidget);
      await tester.tap(find.text('Kill switch'));
      await tester.pumpAndSettle();
      await _tapPrimaryButton(tester, 'Save rollout');
      await tester.pumpAndSettle();

      expect(repository.batchUpserts, hasLength(1));
      expect(
        repository.batchUpserts.single.firstWhere(
          (row) => row['key'] == 'kill_momo_payments',
        )['value'],
        'true',
      );
      expect(
        repository.batchUpserts.single.every((row) => row['country'] == 'RW'),
        isTrue,
      );
      expect(featureFlagsService.refreshCalls, 1);
      expect(repository.fetchCount, greaterThan(1));
      expect(find.text('Killed'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Mobility Subscription Recipient'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('Mobility Subscription Recipient'), findsOneWidget);
      expect(find.textContaining('MoMo code: 008000'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Additional Config'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('support_whatsapp'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(find.text('Additional Config'), findsOneWidget);
      expect(find.text('support_whatsapp'), findsOneWidget);
      expect(find.byIcon(Icons.edit_rounded), findsWidgets);
      expect(find.text('feature_momo_stage'), findsNothing);
      expect(find.text('mobility_subscription_momo_code'), findsNothing);
    },
  );

  testWidgets('mobility subscription section saves admin-managed MoMo code', (
    tester,
  ) async {
    final repository = FakeAdminContentRepository(
      const <Map<String, dynamic>>[],
    );
    final featureFlagsService = FakeFeatureFlagsService();

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          adminContentRepositoryProvider.overrideWithValue(repository),
          supportedCountriesProvider.overrideWith((ref) => countries),
          featureFlagsServiceProvider.overrideWithValue(featureFlagsService),
        ],
        child: const MaterialApp(home: ManageAppConfigScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Mobility Subscription Recipient'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Mobility Subscription Recipient'), findsOneWidget);
    await tester.tap(find.text('Add Recipient'));
    await tester.pumpAndSettle();

    expect(_dropdownFieldWithLabel('Country scope'), findsNothing);
    await tester.enterText(_textFieldWithLabel('MoMo code'), '0788000000');
    await _tapPrimaryButton(tester, 'Save code');
    await tester.pumpAndSettle();

    expect(repository.singleUpserts, hasLength(1));
    expect(
      repository.singleUpserts.single,
      containsPair('key', AppConfigKeys.mobilitySubscriptionMomoCode),
    );
    expect(
      repository.singleUpserts.single,
      containsPair('value', '0788000000'),
    );
    expect(
      repository.singleUpserts.single,
      containsPair(
        'description',
        'MoMo code used to receive mobility subscription payments.',
      ),
    );
    expect(repository.singleUpserts.single, containsPair('country', 'RW'));
    expect(find.textContaining('MoMo code: 0788000000'), findsOneWidget);
  });

  testWidgets(
    'partner payment routes section saves admin-managed checkout path',
    (tester) async {
      final repository = FakeAdminContentRepository(
        const <Map<String, dynamic>>[],
        partners: const <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'partner-1',
            'name': 'Rayon Sports',
            'slug': 'rayon-sports',
            'country': 'RW',
          },
        ],
      );
      final featureFlagsService = FakeFeatureFlagsService();

      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            adminContentRepositoryProvider.overrideWithValue(repository),
            supportedCountriesProvider.overrideWith((ref) => countries),
            featureFlagsServiceProvider.overrideWithValue(featureFlagsService),
          ],
          child: const MaterialApp(home: ManageAppConfigScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Partner Payment Routes'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(find.text('Partner Payment Routes'), findsOneWidget);
      await tester.tap(find.text('Add route'));
      await tester.pumpAndSettle();

      await tester.tap(_dropdownFieldWithLabel('Partner'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rayon Sports').last);
      await tester.pumpAndSettle();

      expect(_dropdownFieldWithLabel('Country'), findsNothing);
      expect(_textFieldWithLabel('Market'), findsOneWidget);
      await tester.enterText(_textFieldWithLabel('Provider id'), 'mtn_rwanda');
      await tester.enterText(_textFieldWithLabel('Merchant code'), '008000');
      await tester.enterText(
        _textFieldWithLabel('Reconciliation label'),
        'rayon_ticket_checkout',
      );

      await tester.tap(_dropdownFieldWithLabel('Status'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Active').last);
      await tester.pumpAndSettle();

      await _tapPrimaryButton(tester, 'Save route');
      await tester.pumpAndSettle();

      expect(repository.paymentRouteUpserts, hasLength(1));
      expect(
        repository.paymentRouteUpserts.single,
        containsPair('partner_id', 'partner-1'),
      );
      expect(
        repository.paymentRouteUpserts.single,
        containsPair('country', 'RW'),
      );
      expect(
        repository.paymentRouteUpserts.single,
        containsPair('recipient_code', '008000'),
      );
      expect(
        repository.paymentRouteUpserts.single,
        containsPair('status', 'active'),
      );
      expect(find.textContaining('MTN_RWANDA · code 008000'), findsOneWidget);
      expect(
        find.textContaining('Reconciliation: rayon_ticket_checkout'),
        findsOneWidget,
      );
    },
  );

  testWidgets('generic editor blocks managed feature keys', (tester) async {
    final repository = FakeAdminContentRepository(
      const <Map<String, dynamic>>[],
    );
    final featureFlagsService = FakeFeatureFlagsService();

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          adminContentRepositoryProvider.overrideWithValue(repository),
          supportedCountriesProvider.overrideWith((ref) => countries),
          featureFlagsServiceProvider.overrideWithValue(featureFlagsService),
        ],
        child: const MaterialApp(home: ManageAppConfigScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    expect(_dropdownFieldWithLabel('Country scope'), findsNothing);
    expect(_textFieldWithLabel('Market'), findsOneWidget);
    await tester.enterText(_textFieldWithLabel('Key'), 'kill_mobility');
    await tester.enterText(_textFieldWithLabel('Value'), 'true');
    await _tapPrimaryButton(tester, 'Save');
    await tester.pumpAndSettle();

    expect(
      find.text('Use the rollout governance cards for managed feature keys.'),
      findsOneWidget,
    );
    expect(repository.singleUpserts, isEmpty);
    expect(repository.batchUpserts, isEmpty);
    expect(featureFlagsService.refreshCalls, 0);
  });

  testWidgets('generic editor blocks mobility subscription code key', (
    tester,
  ) async {
    final repository = FakeAdminContentRepository(
      const <Map<String, dynamic>>[],
    );
    final featureFlagsService = FakeFeatureFlagsService();

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          adminContentRepositoryProvider.overrideWithValue(repository),
          supportedCountriesProvider.overrideWith((ref) => countries),
          featureFlagsServiceProvider.overrideWithValue(featureFlagsService),
        ],
        child: const MaterialApp(home: ManageAppConfigScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    expect(_dropdownFieldWithLabel('Country scope'), findsNothing);
    await tester.enterText(
      _textFieldWithLabel('Key'),
      AppConfigKeys.mobilitySubscriptionMomoCode,
    );
    await tester.enterText(_textFieldWithLabel('Value'), '0788000000');
    await _tapPrimaryButton(tester, 'Save');
    await tester.pumpAndSettle();

    expect(
      find.text('Use the mobility subscription card for this MoMo code.'),
      findsOneWidget,
    );
    expect(repository.singleUpserts, isEmpty);
  });
}
