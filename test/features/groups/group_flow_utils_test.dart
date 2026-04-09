import 'package:cool_app/features/groups/group_flow_utils.dart';
import 'package:cool_app/features/groups/models/group.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('group flow helpers', () {
    const group = Group(
      id: 'group-123',
      creatorId: 'creator-1',
      name: 'Kigali Circle',
      type: 'saving',
      visibility: 'public',
      amount: 0,
      targetAmount: 60000,
      country: 'RW',
      monthlyContribution: 5000,
      momoNumber: '0788123456',
      momoRouteType: 'phone_number',
      inviteCode: 'JOIN1234',
    );

    test('detects contribution route availability from MoMo details', () {
      expect(groupHasContributionRoute(group), isTrue);
      expect(
        groupHasContributionRoute(group.copyWith(momoNumber: '')),
        isFalse,
      );
    });

    test('builds a prefilled MoMo contribution route', () {
      final uri = Uri.parse(buildGroupContributionLocation(group));

      expect(uri.path, '/momo');
      expect(uri.queryParameters['action'], 'qr_pay');
      expect(uri.queryParameters['recipient'], '0788123456');
      expect(uri.queryParameters['recipient_type'], 'phone_number');
      expect(uri.queryParameters['country'], 'RW');
      expect(uri.queryParameters['reference'], 'group-123');
      expect(uri.queryParameters['amount'], '5000');
    });

    test('builds a shareable invite link from the group invite code', () {
      expect(buildGroupInviteUrl(group), 'https://cool.app/invite/JOIN1234');
      expect(buildGroupInviteUrl(group.copyWith(inviteCode: '')), isNull);
    });
  });
}
