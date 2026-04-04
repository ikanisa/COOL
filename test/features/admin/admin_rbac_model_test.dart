import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Session;

import 'package:cool_app/features/admin/models/admin_workspace_access.dart';
import 'package:cool_app/features/auth/providers/auth_provider.dart';

void main() {
  group('AdminRole', () {
    test('fromString parses all valid values', () {
      expect(AdminRole.fromString('admin'), AdminRole.admin);
      expect(AdminRole.fromString('bank'), AdminRole.bank);
    });

    test('fromString is case-insensitive', () {
      expect(AdminRole.fromString('ADMIN'), AdminRole.admin);
      expect(AdminRole.fromString('Bank'), AdminRole.bank);
    });

    test('fromString returns null for unknown values', () {
      expect(AdminRole.fromString(null), isNull);
      expect(AdminRole.fromString('unknown'), isNull);
      expect(AdminRole.fromString(''), isNull);
    });

    test('dbValue round-trips through fromString', () {
      for (final role in AdminRole.values) {
        expect(AdminRole.fromString(role.dbValue), role);
      }
    });

    test('label returns human-readable names', () {
      expect(AdminRole.admin.label, 'Platform Admin');
      expect(AdminRole.bank.label, 'Bank Admin');
    });
  });

  group('AdminRoleAssignment', () {
    test('fromJson parses a complete assignment', () {
      final json = <String, dynamic>{
        'id': 'assign-1',
        'user_id': 'user-abc',
        'role': 'bank',
        'partner_scope_id': 'partner-xyz',
        'partner_name': 'Equity Bank',
        'user_name': 'Jean',
        'user_phone': '+25078000000',
        'granted_by': 'admin-user',
        'granted_at': '2026-03-15T10:00:00Z',
        'revoked_at': null,
        'is_active': true,
        'notes': 'Initial assignment',
      };
      final assignment = AdminRoleAssignment.fromJson(json);
      expect(assignment.id, 'assign-1');
      expect(assignment.userId, 'user-abc');
      expect(assignment.role, AdminRole.bank);
      expect(assignment.bankId, 'partner-xyz');
      expect(assignment.bankName, 'Equity Bank');
      expect(assignment.userName, 'Jean');
      expect(assignment.userPhone, '+25078000000');
      expect(assignment.grantedBy, 'admin-user');
      expect(assignment.isActive, isTrue);
      expect(assignment.notes, 'Initial assignment');
      expect(assignment.revokedAt, isNull);
    });

    test('fromJson handles minimal fields', () {
      final json = <String, dynamic>{
        'id': 'a1',
        'user_id': 'u1',
        'role': 'admin',
        'granted_at': '2026-01-01T00:00:00Z',
        'is_active': true,
      };
      final assignment = AdminRoleAssignment.fromJson(json);
      expect(assignment.role, AdminRole.admin);
      expect(assignment.bankId, isNull);
    });
  });

  group('AdminWorkspaceAccess', () {
    group('fromRpcResponse', () {
      test('parses platform admin access', () {
        final access = AdminWorkspaceAccess.fromRpcResponse(<String, dynamic>{
          'has_platform_access': true,
          'has_bank_access': false,
          'bank_partner_ids': <dynamic>[],
          'role_assignments': <dynamic>[],
        });

        expect(access.hasPlatformAccess, isTrue);
        expect(access.hasBankAdminAccess, isTrue);
        expect(access.hasAnyAdminAccess, isTrue);
      });

      test('parses bank admin with scoped IDs', () {
        final access = AdminWorkspaceAccess.fromRpcResponse(<String, dynamic>{
          'has_platform_access': false,
          'has_bank_access': true,
          'bank_partner_ids': <dynamic>['bank-1', 'bank-2'],
          'role_assignments': <dynamic>[],
        });

        expect(access.hasPlatformAccess, isFalse);
        expect(access.hasBankAdminAccess, isTrue);
        expect(access.bankAdminIds, {'bank-1', 'bank-2'});
        expect(access.canAccessBankId('bank-1'), isTrue);
        expect(access.canAccessBankId('bank-3'), isFalse);
      });

      test('parses role_assignments array', () {
        final access = AdminWorkspaceAccess.fromRpcResponse(<String, dynamic>{
          'has_platform_access': true,
          'has_bank_access': false,
          'bank_partner_ids': <dynamic>[],
          'role_assignments': <dynamic>[
            <String, dynamic>{
              'id': 'a1',
              'user_id': 'u1',
              'role': 'admin',
              'granted_at': '2026-01-01T00:00:00Z',
              'is_active': true,
            },
            <String, dynamic>{
              'id': 'a2',
              'user_id': 'u2',
              'role': 'bank',
              'partner_scope_id': 'p1',
              'granted_at': '2026-02-01T00:00:00Z',
              'is_active': true,
            },
          ],
        });

        expect(access.roleAssignments.length, 2);
        expect(access.activeRoles, {AdminRole.admin, AdminRole.bank});
      });

      test('handles null or missing fields gracefully', () {
        final access = AdminWorkspaceAccess.fromRpcResponse(
          <String, dynamic>{},
        );

        expect(access.hasPlatformAccess, isFalse);
        expect(access.hasBankAdminAccess, isFalse);
        expect(access.hasAnyAdminAccess, isFalse);
        expect(access.roleAssignments, isEmpty);
      });
    });

    group('fromAuthState', () {
      Session sessionWithMetadata(Map<String, dynamic> appMetadata) {
        return Session.fromJson(<String, dynamic>{
          'access_token': 'token-user-1',
          'token_type': 'bearer',
          'expires_in': 3600,
          'refresh_token': 'refresh-user-1',
          'user': <String, dynamic>{
            'id': 'user-1',
            'phone': '+250788123456',
            'user_metadata': const <String, dynamic>{'phone': '+250788123456'},
            'app_metadata': appMetadata,
            'aud': 'authenticated',
            'created_at': DateTime(2026).toIso8601String(),
          },
        })!;
      }

      test('parses scoped bank ids from session metadata', () {
        final access = AdminWorkspaceAccess.fromAuthState(
          AuthState(
            session: sessionWithMetadata(const <String, dynamic>{
              'bank_admin_ids': ['bank-1'],
            }),
          ),
        );

        expect(access.hasAnyAdminAccess, isTrue);
        expect(access.hasBankAdminAccess, isTrue);
        expect(access.canAccessBankId('bank-1'), isTrue);
      });

      test('parses platform and bank booleans from session metadata', () {
        final access = AdminWorkspaceAccess.fromAuthState(
          AuthState(
            session: sessionWithMetadata(const <String, dynamic>{
              'is_admin': true,
              'is_bank_admin': true,
            }),
          ),
        );

        expect(access.hasPlatformAccess, isTrue);
        expect(access.canAccessBankId('any-id'), isTrue);
      });
    });

    group('permission checks', () {
      test('platform admin can access any bank ID', () {
        const access = AdminWorkspaceAccess(hasPlatformAccess: true);
        expect(access.canAccessBankId('any-id'), isTrue);
      });

      test('scoped bank admin can only access assigned bank IDs', () {
        const access = AdminWorkspaceAccess(bankAdminIds: {'bank-A'});
        expect(access.canAccessBankId('bank-A'), isTrue);
        expect(access.canAccessBankId('bank-B'), isFalse);
      });

      test('rejects empty or whitespace IDs', () {
        const access = AdminWorkspaceAccess(hasPlatformAccess: true);
        expect(access.canAccessBankId(''), isFalse);
        expect(access.canAccessBankId('  '), isFalse);
      });
    });

    group('platform admin inherits workspace admin rights', () {
      const platformAdmin = AdminWorkspaceAccess(hasPlatformAccess: true);

      test('has bank admin access by default', () {
        expect(platformAdmin.hasBankAdminAccess, isTrue);
      });

      test('has any admin access by default', () {
        expect(platformAdmin.hasAnyAdminAccess, isTrue);
      });

      test('can access any bank ID', () {
        expect(platformAdmin.canAccessBankId('equity-bank'), isTrue);
        expect(platformAdmin.canAccessBankId('random-bank'), isTrue);
      });
    });
  });
}
