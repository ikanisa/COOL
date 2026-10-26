import 'dart:convert';

import 'package:collect_app/shared/models/member_history_page.dart';
import 'package:flutter_test/flutter_test.dart';

import 'member_data_authority_test.dart' as authority;
import 'member_signed_history_test.dart' as fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'live history explicitly requests and consumes signed v2 events',
    () async {
      final payload = fixture.wire([
        fixture.event(2, amount: -1000, kind: 'reversal', reverses: 1),
        fixture.event(1),
      ]);
      final h = await authority.Harness.create((request) {
        expect(request.url.path, '/v1/rpc/list_current_member_history_page');
        final body = jsonDecode(request.body) as Map;
        expect(body['p_contract_version'], 2);
        expect(body['p_limit'], 50);
        expect(request.headers['Authorization'], startsWith('Bearer '));
        return authority.jsonResponse(payload);
      });
      final page = await h.repo.fetchHistoryPage(const MemberHistoryQuery());
      expect(page.contractVersion, 2);
      expect(page.totals['RWF'], 0);
      expect(page.items.map((row) => row.id), [
        fixture.uuid(2),
        fixture.uuid(1),
      ]);
      expect(page.items.map((row) => row.paymentId).toSet(), {
        fixture.uuid(100),
      });
    },
  );
  for (final version in [null, 1, 3, '2']) {
    test(
      'live history rejects server contract $version rather than downgrading',
      () async {
        final payload = fixture.wire([]);
        if (version == null) {
          payload.remove('contract_version');
        } else {
          payload['contract_version'] = version;
        }
        final h = await authority.Harness.create(
          (_) => authority.jsonResponse(payload),
        );
        await expectLater(
          h.repo.fetchHistoryPage(const MemberHistoryQuery()),
          throwsFormatException,
        );
      },
    );
  }
  test(
    'live history does not accept a private payer name in a v2 reply',
    () async {
      final payload = fixture.wire([
        {...fixture.event(1), 'supporter_label': 'Private receipt name'},
      ]);
      final h = await authority.Harness.create(
        (_) => authority.jsonResponse(payload),
      );
      await expectLater(
        h.repo.fetchHistoryPage(const MemberHistoryQuery()),
        throwsFormatException,
      );
    },
  );
}
