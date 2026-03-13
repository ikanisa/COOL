import 'package:cool_app/core/identity/user_identity_lookup.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('user identity lookup', () {
    test('buildUserIdentitySelect includes public_user_id by default', () {
      expect(
        buildUserIdentitySelect(extraColumns: const <String>['avatar_url']),
        'id, public_user_id, avatar_url, phone',
      );
    });

    test('buildUserIdentitySelect omits duplicate reserved columns', () {
      expect(
        buildUserIdentitySelect(
          includePublicUserId: false,
          extraColumns: const <String>[
            'avatar_url',
            'id',
            'phone',
            'public_user_id',
          ],
        ),
        'id, avatar_url, phone',
      );
    });

    test(
      'fetchUserIdentityRows uses primary query when schema is current',
      () async {
        var calls = 0;

        final rows = await fetchUserIdentityRows(
          fetchRows: ({required includePublicUserId}) async {
            calls += 1;
            expect(includePublicUserId, isTrue);
            return <Map<String, dynamic>>[
              {'id': 'user-1', 'public_user_id': '123456', 'phone': '0788'},
            ];
          },
        );

        expect(calls, 1);
        expect(rows.single['public_user_id'], '123456');
      },
    );

    test(
      'fetchUserIdentityRows falls back when public_user_id column is missing',
      () async {
        var calls = 0;

        final rows = await fetchUserIdentityRows(
          fetchRows: ({required includePublicUserId}) async {
            calls += 1;
            if (includePublicUserId) {
              throw const PostgrestException(
                message: 'column users.public_user_id does not exist',
                code: '42703',
                details: 'Bad Request',
              );
            }

            return <Map<String, dynamic>>[
              {'id': 'user-1', 'phone': '0788'},
            ];
          },
        );

        expect(calls, 2);
        expect(rows.single, {'id': 'user-1', 'phone': '0788'});
      },
    );

    test(
      'fetchUserIdentityRows rethrows unrelated PostgrestException',
      () async {
        expect(
          () => fetchUserIdentityRows(
            fetchRows: ({required includePublicUserId}) async {
              throw const PostgrestException(
                message: 'permission denied',
                code: '42501',
              );
            },
          ),
          throwsA(isA<PostgrestException>()),
        );
      },
    );

    test(
      'isMissingPublicUserIdColumnError recognizes undefined column variant',
      () {
        expect(
          isMissingPublicUserIdColumnError(
            const PostgrestException(
              message: 'undefined column',
              code: '42703',
              hint: 'public_user_id',
            ),
          ),
          isTrue,
        );
      },
    );
  });
}
