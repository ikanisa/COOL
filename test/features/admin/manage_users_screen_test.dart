import 'package:cool_app/features/admin/providers/admin_providers.dart';
import 'package:cool_app/features/admin/repositories/admin_repository.dart';
import 'package:cool_app/features/admin/screens/manage_users_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}

class FakeUsersAdminRepository extends AdminRepository {
  FakeUsersAdminRepository({required List<Map<String, dynamic>> users})
    : _users = users.map(Map<String, dynamic>.from).toList(),
      super(client: MockSupabaseClient());

  final List<Map<String, dynamic>> _users;

  @override
  Future<List<Map<String, dynamic>>> fetchUsers() async {
    return _users.map(Map<String, dynamic>.from).toList(growable: false);
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
            adminRepositoryProvider.overrideWithValue(repository),
          ],
          child: const MaterialApp(home: ManageUsersScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Rwanda · EN · airtel'), findsOneWidget);
      expect(find.textContaining('FR'), findsNothing);
    },
  );
}
