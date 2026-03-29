import 'package:cool_app/features/admin/models/admin_workspace_access.dart';
import 'package:cool_app/features/admin/providers/admin_providers.dart';
import 'package:cool_app/features/admin/providers/admin_workspace_access_provider.dart';
import 'package:cool_app/features/admin/repositories/admin_role_repository.dart';
import 'package:cool_app/features/admin/screens/manage_admin_roles_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}

class FakeAdminRoleRepository extends AdminRoleRepository {
  FakeAdminRoleRepository({
    List<AdminRoleAssignment> assignments = const <AdminRoleAssignment>[],
  }) : _assignments = List<AdminRoleAssignment>.from(assignments),
       super(client: MockSupabaseClient());

  final List<AdminRoleAssignment> _assignments;
  final List<Map<String, dynamic>> assignedRoles = <Map<String, dynamic>>[];
  final List<String> revokedAssignmentIds = <String>[];

  @override
  Future<AdminWorkspaceAccess?> fetchAdminAccess({String? userId}) async =>
      null;

  @override
  Future<List<AdminRoleAssignment>> listRoleAssignments({
    AdminRole? role,
    bool activeOnly = true,
  }) async {
    return _assignments
        .where((assignment) {
          if (activeOnly && !assignment.isActive) {
            return false;
          }
          if (role != null && assignment.role != role) {
            return false;
          }
          return true;
        })
        .toList(growable: false);
  }

  @override
  Future<Map<String, dynamic>> assignRole({
    required String targetUserId,
    required AdminRole role,
    String? partnerScopeId,
    String? notes,
  }) async {
    assignedRoles.add(<String, dynamic>{
      'targetUserId': targetUserId,
      'role': role,
      'partnerScopeId': partnerScopeId,
      'notes': notes,
    });
    return <String, dynamic>{'id': 'assignment-${assignedRoles.length}'};
  }

  @override
  Future<Map<String, dynamic>> revokeRole({
    required String assignmentId,
    String? notes,
  }) async {
    revokedAssignmentIds.add(assignmentId);
    return <String, dynamic>{'id': assignmentId};
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
        widget is DropdownButtonFormField<String> &&
        widget.decoration.labelText == label,
    description: 'DropdownButtonFormField(labelText: $label)',
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

void main() {
  testWidgets('assigns a bank admin role with partner scope', (tester) async {
    _configureTallViewport(tester);
    final repository = FakeAdminRoleRepository(
      assignments: <AdminRoleAssignment>[
        AdminRoleAssignment(
          id: 'assignment-1',
          userId: 'user-1',
          role: AdminRole.admin,
          userName: 'Alice',
          grantedAt: DateTime(2026, 3, 1),
          isActive: true,
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          adminRoleRepositoryProvider.overrideWithValue(repository),
          adminPartnersProvider.overrideWith(
            (ref) async => <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'partner-bank-1',
                'name': 'Urwego',
                'category': 'bank',
              },
              <String, dynamic>{
                'id': 'partner-rayon-1',
                'name': 'Rayon Sports',
                'category': 'football',
              },
            ],
          ),
        ],
        child: const MaterialApp(home: ManageAdminRolesScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    await tester.enterText(_textFieldWithLabel('User ID'), 'user-42');
    await tester.tap(find.widgetWithText(ChoiceChip, 'Bank Admin'));
    await tester.pumpAndSettle();

    await tester.tap(_dropdownFieldWithLabel('Partner Scope'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Urwego').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Assign Role'));
    await tester.pumpAndSettle();

    expect(repository.assignedRoles, hasLength(1));
    expect(repository.assignedRoles.single['targetUserId'], 'user-42');
    expect(repository.assignedRoles.single['role'], AdminRole.bank);
    expect(repository.assignedRoles.single['partnerScopeId'], 'partner-bank-1');
  });

  testWidgets('revokes an existing admin role assignment', (tester) async {
    _configureTallViewport(tester);
    final repository = FakeAdminRoleRepository(
      assignments: <AdminRoleAssignment>[
        AdminRoleAssignment(
          id: 'assignment-1',
          userId: 'user-1',
          role: AdminRole.bank,
          partnerName: 'Urwego',
          userName: 'Alice',
          userPhone: '+250788000111',
          grantedAt: DateTime(2026, 3, 1),
          isActive: true,
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          adminRoleRepositoryProvider.overrideWithValue(repository),
          adminPartnersProvider.overrideWith(
            (ref) async => const <Map<String, dynamic>>[],
          ),
        ],
        child: const MaterialApp(home: ManageAdminRolesScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Bank Admin'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Revoke'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Revoke'));
    await tester.pumpAndSettle();

    expect(repository.revokedAssignmentIds, contains('assignment-1'));
  });
}
