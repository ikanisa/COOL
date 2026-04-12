import 'dart:io';

import 'package:cool_app/core/config/country_catalog.dart';
import 'package:cool_app/core/theme/app_theme.dart';
import 'package:cool_app/features/admin/providers/admin_providers.dart';
import 'package:cool_app/features/admin/repositories/admin_savings_repository.dart';
import 'package:cool_app/features/admin/screens/admin_savings_detail_screen.dart';
import 'package:cool_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _MockSupabaseClient extends Mock implements SupabaseClient {}

class _FakeAdminSavingsRepository extends AdminSavingsRepository {
  _FakeAdminSavingsRepository() : super(client: _MockSupabaseClient());

  final List<Map<String, dynamic>> bulkAddCalls = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> removeCalls = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> allocationCalls = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> updateCalls = <Map<String, dynamic>>[];

  @override
  Future<Map<String, dynamic>> fetchSavingsGroupsDetail() async {
    return <String, dynamic>{
      'savings_groups': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'group-1',
          'name': 'Alpha Circle',
          'description': 'Shared goal',
          'target_amount': 500000,
          'monthly_contribution': 25000,
          'total_collected': 120000,
          'frequency': 'monthly',
          'invite_code': 'JOIN1234',
          'is_closed': false,
          'members': <Map<String, dynamic>>[
            <String, dynamic>{
              'user_id': 'user-1',
              'display_name': 'Alice',
              'phone': '+250788000111',
            },
            <String, dynamic>{
              'user_id': 'user-2',
              'display_name': 'Bob',
              'phone': '+250788000222',
            },
          ],
        },
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> bulkAddGroupMembers({
    required String groupId,
    required List<Map<String, String>> members,
  }) async {
    bulkAddCalls.add(<String, dynamic>{'groupId': groupId, 'members': members});
    return const <String, dynamic>{'status': 'success'};
  }

  @override
  Future<Map<String, dynamic>> removeGroupMember({
    required String groupId,
    required String userId,
  }) async {
    removeCalls.add(<String, dynamic>{'groupId': groupId, 'userId': userId});
    return const <String, dynamic>{'status': 'success'};
  }

  @override
  Future<Map<String, dynamic>> allocateSavingsContribution({
    required String groupId,
    required String memberUserId,
    required int amount,
    String? reference,
    String? note,
  }) async {
    allocationCalls.add(<String, dynamic>{
      'groupId': groupId,
      'memberUserId': memberUserId,
      'amount': amount,
      'reference': reference,
      'note': note,
    });
    return const <String, dynamic>{'status': 'success'};
  }

  @override
  Future<Map<String, dynamic>> updateSavingsGroup({
    required String groupId,
    String? name,
    String? description,
    int? targetAmount,
    int? monthlyContribution,
    String? frequency,
    bool? isClosed,
  }) async {
    updateCalls.add(<String, dynamic>{
      'groupId': groupId,
      'name': name,
      'description': description,
      'targetAmount': targetAmount,
      'monthlyContribution': monthlyContribution,
      'frequency': frequency,
      'isClosed': isClosed,
    });
    return const <String, dynamic>{'status': 'success'};
  }
}

Finder _textFieldByHint(String hintText) {
  return find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.hintText == hintText,
    description: 'TextField(hintText: $hintText)',
  );
}

void _configureTallViewport(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1440, 2560);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

Future<void> _pumpScreen(
  WidgetTester tester,
  _FakeAdminSavingsRepository repository,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        adminSavingsRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(
        theme: AppTheme.dark,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: const AdminSavingsDetailScreen(groupId: 'group-1'),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await CoolCountryCatalog.initialize(
      await File('assets/countries.json').readAsString(),
    );
  });

  testWidgets('admin savings flow covers add, allocate, remove, and close', (
    tester,
  ) async {
    _configureTallViewport(tester);
    final repository = _FakeAdminSavingsRepository();
    await _pumpScreen(tester, repository);

    await tester.enterText(_textFieldByHint('+250788…'), '+250788111333');
    await tester.enterText(_textFieldByHint('Name'), 'Jeanne');
    await tester.ensureVisible(find.text('Add'));
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ChoiceChip, 'Allocations'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bob').last);
    await tester.pumpAndSettle();
    await tester.enterText(_textFieldByHint('Amount'), '45000');
    await tester.enterText(_textFieldByHint('Note'), 'Manual correction');
    await tester.ensureVisible(find.text('Allocate'));
    await tester.tap(find.text('Allocate'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ChoiceChip, 'Members'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Remove member').first);
    await tester.tap(find.byTooltip('Remove member').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove member').last);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Close Group'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Close Group'));
    await tester.pumpAndSettle();

    expect(repository.bulkAddCalls, hasLength(1));
    expect(repository.bulkAddCalls.single['groupId'], 'group-1');
    expect(repository.bulkAddCalls.single['members'], <Map<String, String>>[
      <String, String>{'phone': '+250788111333', 'display_name': 'Jeanne'},
    ]);

    expect(repository.allocationCalls, hasLength(1));
    expect(repository.allocationCalls.single['groupId'], 'group-1');
    expect(repository.allocationCalls.single['memberUserId'], 'user-2');
    expect(repository.allocationCalls.single['amount'], 45000);
    expect(repository.allocationCalls.single['note'], 'Manual correction');

    expect(repository.removeCalls, hasLength(1));
    expect(repository.removeCalls.single['groupId'], 'group-1');
    expect(repository.removeCalls.single['userId'], 'user-1');

    expect(repository.updateCalls, hasLength(1));
    expect(repository.updateCalls.single['groupId'], 'group-1');
    expect(repository.updateCalls.single['isClosed'], isTrue);
  });
}
