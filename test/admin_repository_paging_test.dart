import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _RpcRepository extends AdminRepository {
  _RpcRepository(this.respond) : super(null);

  final Future<Map<String, dynamic>> Function() respond;
  final requests = <({String rpc, Map<String, dynamic> params})>[];

  @override
  Future<Map<String, dynamic>> rpcMap(
    String rpcName, {
    Map<String, dynamic>? params,
    bool automaticRetry = true,
  }) {
    requests.add((rpc: rpcName, params: Map.of(params ?? {})));
    return respond();
  }
}

void main() {
  test('default list is a 25-row server request', () async {
    final repository = _RpcRepository(() async => {'rows': [], 'total': 0});
    await repository.list('admin_list_audit_logs');
    expect(repository.requests, hasLength(1));
    expect(repository.requests.single.params, {
      'p_search': null,
      'p_status': null,
      'p_limit': 25,
      'p_offset': 0,
      'p_sort': 'created_at_desc',
    });
  });

  test(
    'Rwanda list keeps every query argument on the scoped endpoint',
    () async {
      final repository = _RpcRepository(() async => {'rows': [], 'total': 0});
      await repository.list(
        'admin_list_collections',
        search: ' group ',
        status: ' active ',
        countryCode: ' rw ',
        limit: 25,
        offset: 100,
        sortBy: 'created_at_asc',
      );
      expect(repository.requests.single.rpc, 'admin_list_country_scoped');
      expect(repository.requests.single.params, {
        'p_rpc_name': 'admin_list_collections',
        'p_country': 'RW',
        'p_search': 'group',
        'p_status': 'active',
        'p_limit': 25,
        'p_offset': 100,
        'p_sort': 'created_at_asc',
      });
    },
  );

  for (final scoped in [false, true]) {
    for (final code in ['PGRST202', '42501', 'P0001']) {
      test('error $code never triggers a fallback; scoped=$scoped', () async {
        final failure = PostgrestException(
          message: 'Synthetic p_limit function failure',
          code: code,
        );
        final repository = _RpcRepository(() async => throw failure);
        await expectLater(
          repository.list(
            scoped ? 'admin_list_collections' : 'admin_list_audit_logs',
            countryCode: scoped ? 'RW' : null,
          ),
          throwsA(same(failure)),
        );
        expect(repository.requests, hasLength(1));
      });
    }
  }

  test(
    'a malformed list response is not converted to an empty result',
    () async {
      final repository = _RpcRepository(() async => {});
      await expectLater(
        repository.list('admin_list_audit_logs'),
        throwsFormatException,
      );
      expect(repository.requests, hasLength(1));
    },
  );

  test('legacy response without a total is not client-paginated', () async {
    final repository = _RpcRepository(() async => {'rows': []});
    await expectLater(
      repository.list('admin_list_audit_logs'),
      throwsFormatException,
    );
    expect(repository.requests, hasLength(1));
  });

  for (final country in [null, 'MT', 'ZZ']) {
    test('Rwanda scoped result rejects country $country', () async {
      final repository = _RpcRepository(
        () async => {
          'rows': [
            {'id': 'row-1', 'country_code': ?country, 'rail': 'rw_momo'},
          ],
          'total': 1,
        },
      );
      await expectLater(
        repository.list('admin_list_collections', countryCode: 'RW'),
        throwsFormatException,
      );
      expect(repository.requests.single.rpc, 'admin_list_country_scoped');
    });
  }

  test('Rwanda scoped result accepts explicit Rwanda rows', () async {
    final repository = _RpcRepository(
      () async => {
        'rows': [
          {'id': 'row-1', 'country_code': 'RW'},
        ],
        'total': 1,
      },
    );
    final result = await repository.list(
      'admin_list_collections',
      countryCode: 'RW',
    );
    expect(result.rows.single.id, 'row-1');
  });

  test('invalid window bounds fail before the RPC', () async {
    final repository = _RpcRepository(() async => {'rows': [], 'total': 0});
    await expectLater(
      repository.list('admin_list_audit_logs', limit: 0),
      throwsRangeError,
    );
    await expectLater(
      repository.list('admin_list_audit_logs', limit: 101),
      throwsRangeError,
    );
    await expectLater(
      repository.list('admin_list_audit_logs', offset: -1),
      throwsRangeError,
    );
    expect(repository.requests, isEmpty);
  });
}
