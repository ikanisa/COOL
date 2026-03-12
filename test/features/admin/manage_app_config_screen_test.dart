import 'package:cool_app/core/config/country_catalog.dart';
import 'package:cool_app/core/models/engagement_feature_flags.dart';
import 'package:cool_app/core/providers/engagement_providers.dart';
import 'package:cool_app/core/providers/supported_countries_provider.dart';
import 'package:cool_app/core/services/feature_flags_service.dart';
import 'package:cool_app/core/services/firebase_bootstrap_service.dart';
import 'package:cool_app/features/admin/providers/admin_providers.dart';
import 'package:cool_app/features/admin/repositories/admin_repository.dart';
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

class FakeAdminRepository extends AdminRepository {
  FakeAdminRepository(List<Map<String, dynamic>> configs)
    : _configs = configs.map(Map<String, dynamic>.from).toList(),
      super(client: MockSupabaseClient());

  final List<Map<String, dynamic>> _configs;
  final List<Map<String, dynamic>> singleUpserts = <Map<String, dynamic>>[];
  final List<List<Map<String, dynamic>>> batchUpserts =
      <List<Map<String, dynamic>>>[];
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

void main() {
  final countries = <CoolCountry>[
    CoolCountryCatalog.resolve(country: 'RW'),
    CoolCountryCatalog.resolve(country: 'KE'),
  ];

  testWidgets(
    'renders rollout cards, hides managed keys from generic list, and saves rollout changes',
    (tester) async {
      final repository = FakeAdminRepository(<Map<String, dynamic>>[
        <String, dynamic>{
          'key': 'feature_mobility_stage',
          'value': 'pilot',
          'description': 'Mobility rollout stage',
          'country': null,
        },
        <String, dynamic>{
          'key': 'feature_mobility_allowed_countries',
          'value': 'RW, KE',
          'description': 'Mobility allow list',
          'country': null,
        },
        <String, dynamic>{
          'key': 'kill_mobility',
          'value': 'false',
          'description': 'Mobility kill switch',
          'country': null,
        },
        <String, dynamic>{
          'key': 'feature_mobility_admin_only',
          'value': 'false',
          'description': 'Mobility admin only',
          'country': null,
        },
        <String, dynamic>{
          'key': 'support_whatsapp',
          'value': '250700000000',
          'description': 'Support line',
          'country': null,
        },
      ]);
      final featureFlagsService = FakeFeatureFlagsService();

      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            adminRepositoryProvider.overrideWithValue(repository),
            supportedCountriesProvider.overrideWith((ref) async => countries),
            featureFlagsServiceProvider.overrideWithValue(featureFlagsService),
          ],
          child: const MaterialApp(home: ManageAppConfigScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Rollout Governance'), findsOneWidget);
      expect(find.text('Mobility'), findsOneWidget);
      expect(find.text('PILOT'), findsOneWidget);
      expect(find.text('2 countries'), findsOneWidget);

      await tester.ensureVisible(find.byIcon(Icons.tune_rounded).at(3));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.tune_rounded).last);
      await tester.pumpAndSettle();

      expect(find.text('Mobility rollout'), findsOneWidget);
      await tester.tap(find.text('Kill switch'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save rollout'));
      await tester.pumpAndSettle();

      expect(repository.batchUpserts, hasLength(1));
      expect(
        repository.batchUpserts.single.firstWhere(
          (row) => row['key'] == 'kill_mobility',
        )['value'],
        'true',
      );
      expect(featureFlagsService.refreshCalls, 1);
      expect(repository.fetchCount, greaterThan(1));
      expect(find.text('Killed'), findsOneWidget);

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
      expect(find.text('feature_mobility_stage'), findsNothing);
    },
  );

  testWidgets('generic editor blocks managed feature keys', (tester) async {
    final repository = FakeAdminRepository(const <Map<String, dynamic>>[]);
    final featureFlagsService = FakeFeatureFlagsService();

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          adminRepositoryProvider.overrideWithValue(repository),
          supportedCountriesProvider.overrideWith((ref) async => countries),
          featureFlagsServiceProvider.overrideWithValue(featureFlagsService),
        ],
        child: const MaterialApp(home: ManageAppConfigScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    await tester.enterText(_textFieldWithLabel('Key'), 'kill_mobility');
    await tester.enterText(_textFieldWithLabel('Value'), 'true');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(
      find.text('Use the rollout governance cards for managed feature keys.'),
      findsOneWidget,
    );
    expect(repository.singleUpserts, isEmpty);
    expect(repository.batchUpserts, isEmpty);
    expect(featureFlagsService.refreshCalls, 0);
  });
}
