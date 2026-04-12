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

    test('treats merchant-code routes as valid contribution routes', () {
      const codeGroup = Group(
        id: 'group-code',
        creatorId: 'creator-1',
        name: 'Code Circle',
        type: 'community',
        visibility: 'public',
        amount: 0,
        targetAmount: 0,
        country: 'RW',
        momoNumber: '23456',
        momoRouteType: 'code',
      );

      expect(groupHasContributionRoute(codeGroup), isTrue);
    });

    test('builds a shareable invite link from the group invite code', () {
      expect(buildGroupInviteUrl(group), 'https://cool.app/invite/JOIN1234');
      expect(buildGroupInviteUrl(group.copyWith(inviteCode: '')), isNull);
    });
  });
}
