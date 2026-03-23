import 'package:cool_app/features/admin/providers/admin_providers.dart';
import 'package:cool_app/features/admin/repositories/admin_users_repository.dart';
import 'package:cool_app/features/admin/screens/manage_users_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}

class FakeUsersAdminRepository extends AdminUsersRepository {
  FakeUsersAdminRepository({required List<Map<String, dynamic>> users})
    : _users = users.map(Map<String, dynamic>.from).toList(),
      super(client: MockSupabaseClient());

  final List<Map<String, dynamic>> _users;
  final List<Map<String, dynamic>> updatedUsers = <Map<String, dynamic>>[];

  @override
  Future<List<Map<String, dynamic>>> fetchUsers() async {
    return _users.map(Map<String, dynamic>.from).toList(growable: false);
  }

  @override
  Future<void> updateUserFields(
    String userId,
    Map<String, dynamic> fields,
  ) async {
    updatedUsers.add(<String, dynamic>{'id': userId, 'fields': fields});
  }
}

void _configureTallViewport(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1440, 2560);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

void main() {
  testWidgets(
    'users screen renders Rwanda and English as fixed app invariants',
    (tester) async {
      _configureTallViewport(tester);
      final repository = FakeUsersAdminRepository(
        users: const <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'user-1',
            'public_user_id': 'cool-user-1',
            'phone': '+256700000000',
            'country': '',
            'language_code': 'sw',
            'momo_provider': 'airtel',
            'is_driver': false,
            'is_admin': false,
            'is_mock': false,
          },
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            adminUsersRepositoryProvider.overrideWithValue(repository),
          ],
          child: const MaterialApp(home: ManageUsersScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Rwanda · EN · airtel'), findsOneWidget);
      expect(find.text('Make Admin'), findsOneWidget);
      expect(find.textContaining('FR'), findsNothing);
    },
  );

  testWidgets('edit user sheet saves updated fields', (tester) async {
    _configureTallViewport(tester);
    final repository = FakeUsersAdminRepository(
      users: const <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'user-1',
          'public_user_id': 'cool-user-1',
          'phone': '+250788000111',
          'full_name': 'Alice',
          'country': 'RW',
          'language_code': 'en',
          'momo_provider': 'mtn',
          'is_driver': false,
          'is_admin': false,
          'is_mock': false,
        },
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          adminUsersRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: ManageUsersScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Edit').first);
    await tester.tap(find.text('Edit').first);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byWidgetPredicate(
        (widget) => widget is TextField && widget.controller?.text == 'Alice',
        description: 'Name field',
      ),
      'Alice Updated',
    );

    await tester.tap(find.text('Save User').last);
    await tester.pumpAndSettle();

    expect(repository.updatedUsers, hasLength(1));
    expect(repository.updatedUsers.single['id'], 'user-1');
    expect(
      (repository.updatedUsers.single['fields']
          as Map<String, dynamic>)['full_name'],
      'Alice Updated',
    );
  });
}
