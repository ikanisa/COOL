import 'package:cool_app/core/theme/app_theme.dart';
import 'package:cool_app/features/admin/providers/admin_providers.dart';
import 'package:cool_app/features/admin/repositories/admin_users_repository.dart';
import 'package:cool_app/features/admin/screens/manage_users_screen.dart';
import 'package:cool_app/shared/widgets/cool_button.dart';
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

Widget _wrapAdminScreen(Widget child, {required List<Override> overrides}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      theme: AppTheme.dark,
      builder: (context, widget) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: widget!,
      ),
      home: child,
    ),
  );
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
            'is_admin': false,
            'is_mock': false,
          },
        ],
      );

      await tester.pumpWidget(
        _wrapAdminScreen(
          const ManageUsersScreen(),
          overrides: <Override>[
            adminUsersRepositoryProvider.overrideWithValue(repository),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Rwanda · EN · airtel'), findsOneWidget);
      expect(find.text('Make Admin'), findsNothing);
      expect(find.text('Remove Admin'), findsNothing);
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
          'is_admin': false,
          'is_mock': false,
        },
      ],
    );

    await tester.pumpWidget(
      _wrapAdminScreen(
        const ManageUsersScreen(),
        overrides: <Override>[
          adminUsersRepositoryProvider.overrideWithValue(repository),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byType(TextButton).first);
    await tester.tap(find.byType(TextButton).first);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byWidgetPredicate(
        (widget) => widget is TextField && widget.controller?.text == 'Alice',
        description: 'Name field',
      ),
      'Alice Updated',
    );

    await tester.tap(find.byType(CoolButton).last);
    await tester.pumpAndSettle();

    expect(repository.updatedUsers, hasLength(1));
    expect(repository.updatedUsers.single['id'], 'user-1');
    final savedFields =
        repository.updatedUsers.single['fields'] as Map<String, dynamic>;
    expect(savedFields['full_name'], 'Alice Updated');
    // P1 RBAC alignment: is_admin must never be written from the edit sheet.
    expect(savedFields.containsKey('is_admin'), isFalse);
  });
}
