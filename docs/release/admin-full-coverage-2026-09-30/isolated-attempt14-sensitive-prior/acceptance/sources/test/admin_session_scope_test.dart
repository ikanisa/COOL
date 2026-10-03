import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_evidence_mode.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/core/supabase/supabase_module.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _accountA = AdminIdentity(
  userId: 'operator-a',
  displayName: 'Operator A',
  roles: ['admin'],
  permissions: ['payments.read'],
);
const _accountB = AdminIdentity(
  userId: 'operator-b',
  displayName: 'Operator B',
  roles: ['admin'],
  permissions: ['payments.read'],
);

class _SwitchingRepository extends AdminEvidenceRepository {
  _SwitchingRepository(this.current);

  AdminIdentity? current;

  @override
  Future<AdminIdentity?> currentIdentity() async => current;
}

void main() {
  test(
    'Admin identity never exposes the previous operator after a switch',
    () async {
      final userId = StateProvider<String?>((_) => 'operator-a');
      final repository = _SwitchingRepository(_accountA);
      final container = ProviderContainer(
        overrides: [
          adminAuthUserIdProvider.overrideWith((ref) => ref.watch(userId)),
          adminRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);

      expect(await container.read(adminIdentityProvider.future), _accountA);
      container.read(userId.notifier).state = 'operator-b';
      expect(await container.read(adminIdentityProvider.future), isNull);
      repository.current = _accountB;
      container.invalidate(adminIdentityProvider);
      expect(await container.read(adminIdentityProvider.future), _accountB);
      container.read(userId.notifier).state = null;
      expect(await container.read(adminIdentityProvider.future), isNull);
    },
  );

  test('Admin repository state is recreated for a different auth user', () {
    final userId = StateProvider<String?>((_) => 'operator-a');
    final container = ProviderContainer(
      overrides: [
        supabaseClientProvider.overrideWithValue(null),
        adminAuthUserIdProvider.overrideWith((ref) => ref.watch(userId)),
      ],
    );
    addTearDown(container.dispose);

    final first = container.read(adminRepositoryProvider);
    container.read(userId.notifier).state = 'operator-b';
    final second = container.read(adminRepositoryProvider);
    expect(identical(first, second), isFalse);
    container.read(userId.notifier).state = null;
    expect(identical(second, container.read(adminRepositoryProvider)), isFalse);
  });
}
