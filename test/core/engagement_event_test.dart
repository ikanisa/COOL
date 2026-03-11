import 'package:flutter_test/flutter_test.dart';

import 'package:cool_app/core/models/engagement_event.dart';

void main() {
  group('EngagementEvent.analyticsParameters', () {
    test('drops null values and converts booleans to integers', () {
      final event = EngagementEvent(
        name: EngagementEventName.deepLinkOpened,
        parameters: const <String, Object?>{
          'has_query': true,
          'campaign': null,
          'source': 'invite',
        },
      );

      expect(event.analyticsParameters, <String, Object>{
        'has_query': 1,
        'source': 'invite',
      });
    });

    test('truncates long strings for analytics safety', () {
      final longValue = 'x' * 140;
      final event = EngagementEvent(
        name: EngagementEventName.inviteSent,
        parameters: <String, Object?>{'invite_url': longValue},
      );

      expect((event.analyticsParameters['invite_url'] as String).length, 100);
    });
  });
}
