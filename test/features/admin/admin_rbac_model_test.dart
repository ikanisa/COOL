import 'package:flutter_test/flutter_test.dart';

import 'package:cool_app/features/admin/models/admin_workspace_access.dart';

void main() {
  group('AdminRole', () {
    test('fromString parses all valid values', () {
      expect(AdminRole.fromString('admin'), AdminRole.admin);
      expect(AdminRole.fromString('bank'), AdminRole.bank);
      expect(AdminRole.fromString('rayon_sport'), AdminRole.rayonSport);
    });

    test('fromString is case-insensitive', () {
      expect(AdminRole.fromString('ADMIN'), AdminRole.admin);
      expect(AdminRole.fromString('Bank'), AdminRole.bank);
      expect(AdminRole.fromString('RAYON_SPORT'), AdminRole.rayonSport);
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
      expect(AdminRole.rayonSport.label, 'Rayon Sport Admin');
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
      final a = AdminRoleAssignment.fromJson(json);
      expect(a.id, 'assign-1');
      expect(a.userId, 'user-abc');
      expect(a.role, AdminRole.bank);
      expect(a.partnerScopeId, 'partner-xyz');
      expect(a.partnerName, 'Equity Bank');
      expect(a.userName, 'Jean');
      expect(a.userPhone, '+25078000000');
      expect(a.grantedBy, 'admin-user');
      expect(a.isActive, true);
      expect(a.notes, 'Initial assignment');
      expect(a.revokedAt, isNull);
    });

    test('fromJson handles minimal fields', () {
      final json = <String, dynamic>{
        'id': 'a1',
        'user_id': 'u1',
        'role': 'admin',
        'granted_at': '2026-01-01T00:00:00Z',
        'is_active': true,
      };
      final a = AdminRoleAssignment.fromJson(json);
      expect(a.role, AdminRole.admin);
      expect(a.partnerScopeId, isNull);
    });
  });

  group('AdminWorkspaceAccess', () {
    group('fromRpcResponse', () {
      test('parses platform admin access', () {
        final json = <String, dynamic>{
          'has_platform_access': true,
          'has_bank_access': false,
          'has_rayon_access': false,
          'bank_partner_ids': <dynamic>[],
          'partner_admin_ids': <dynamic>[],
          'role_assignments': <dynamic>[],
        };
        final access = AdminWorkspaceAccess.fromRpcResponse(json);
        expect(access.hasPlatformAccess, isTrue);
        // Platform admins inherit bank + partner access (impersonation)
        expect(access.hasBankAdminAccess, isTrue);
        expect(access.hasPartnerAdminAccess, isTrue);
        expect(access.hasAnyAdminAccess, isTrue);
      });

      test('parses bank admin with scoped IDs', () {
        final json = <String, dynamic>{
          'has_platform_access': false,
          'has_bank_access': true,
          'has_rayon_access': false,
          'bank_partner_ids': <dynamic>['bank-1', 'bank-2'],
          'partner_admin_ids': <dynamic>[],
          'role_assignments': <dynamic>[],
        };
        final access = AdminWorkspaceAccess.fromRpcResponse(json);
        expect(access.hasPlatformAccess, isFalse);
        expect(access.hasBankAdminAccess, isTrue);
        expect(access.bankAdminIds, {'bank-1', 'bank-2'});
        expect(access.canAccessBankId('bank-1'), isTrue);
        expect(access.canAccessBankId('bank-3'), isFalse);
      });

      test('parses rayon admin access', () {
        final json = <String, dynamic>{
          'has_platform_access': false,
          'has_bank_access': false,
          'has_rayon_access': true,
          'bank_partner_ids': <dynamic>[],
          'partner_admin_ids': <dynamic>['rayon-id'],
          'role_assignments': <dynamic>[],
        };
        final access = AdminWorkspaceAccess.fromRpcResponse(json);
        expect(access.hasPartnerAdminAccess, isTrue);
        expect(access.hasGlobalPartnerAccess, isTrue);
        expect(access.canAccessPartnerId('rayon-id'), isTrue);
        expect(access.canAccessPartnerId('other-id'), isTrue); // global
      });

      test('parses role_assignments array', () {
        final json = <String, dynamic>{
          'has_platform_access': true,
          'has_bank_access': false,
          'has_rayon_access': false,
          'bank_partner_ids': <dynamic>[],
          'partner_admin_ids': <dynamic>[],
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
        };
        final access = AdminWorkspaceAccess.fromRpcResponse(json);
        expect(access.roleAssignments.length, 2);
        expect(access.activeRoles, {AdminRole.admin, AdminRole.bank});
      });

      test('handles null/missing fields gracefully', () {
        final json = <String, dynamic>{};
        final access = AdminWorkspaceAccess.fromRpcResponse(json);
        expect(access.hasPlatformAccess, isFalse);
        expect(access.hasBankAdminAccess, isFalse);
        expect(access.hasPartnerAdminAccess, isFalse);
        expect(access.hasAnyAdminAccess, isFalse);
        expect(access.roleAssignments, isEmpty);
      });
    });

    group('permission checks', () {
      test('platform admin can access any partner or bank ID', () {
        const access = AdminWorkspaceAccess(hasPlatformAccess: true);
        expect(access.canAccessPartnerId('any-id'), isTrue);
        expect(access.canAccessBankId('any-id'), isTrue);
      });

      test('scoped bank admin can only access their bank IDs', () {
        const access = AdminWorkspaceAccess(bankAdminIds: {'bank-A'});
        expect(access.canAccessBankId('bank-A'), isTrue);
        expect(access.canAccessBankId('bank-B'), isFalse);
        expect(access.canAccessPartnerId('bank-A'), isFalse);
      });

      test('rejects empty or whitespace IDs', () {
        const access = AdminWorkspaceAccess(hasPlatformAccess: true);
        expect(access.canAccessPartnerId(''), isFalse);
        expect(access.canAccessPartnerId('  '), isFalse);
        expect(access.canAccessBankId(''), isFalse);
      });
    });

    group('platform admin inherits workspace admin rights', () {
      const platformAdmin = AdminWorkspaceAccess(hasPlatformAccess: true);

      test('has partner admin access by default', () {
        expect(platformAdmin.hasPartnerAdminAccess, isTrue);
      });

      test('has bank admin access by default', () {
        expect(platformAdmin.hasBankAdminAccess, isTrue);
      });

      test('has any admin access by default', () {
        expect(platformAdmin.hasAnyAdminAccess, isTrue);
      });

      test('can access any partner ID', () {
        expect(platformAdmin.canAccessPartnerId('rayon-sports'), isTrue);
        expect(platformAdmin.canAccessPartnerId('random-partner'), isTrue);
      });

      test('can access any bank ID', () {
        expect(platformAdmin.canAccessBankId('equity-bank'), isTrue);
        expect(platformAdmin.canAccessBankId('random-bank'), isTrue);
      });
    });
  });
}
