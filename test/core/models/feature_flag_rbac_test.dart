import 'package:flutter_test/flutter_test.dart';

import 'package:cool_app/core/models/engagement_feature_flags.dart';

void main() {
  // ─────────────────────────────────────────────────────────────
  // 2.5a — ManagedFeatureRollout RBAC enforcement
  // ─────────────────────────────────────────────────────────────
  group('ManagedFeatureRollout', () {
    group('kill switch', () {
      test('disabled when kill switch is on, regardless of role', () {
        const feature = ManagedFeatureRollout(key: 'momo', killSwitch: true);
        expect(feature.isEnabled(), isFalse);
        expect(feature.isEnabled(isAdmin: true), isFalse);
      });

      test('enabled when kill switch is off and stage is live', () {
        const feature = ManagedFeatureRollout(key: 'momo');
        expect(feature.isEnabled(), isTrue);
        expect(feature.isEnabled(isAdmin: true), isTrue);
      });
    });

    group('rollout stages', () {
      test('disabled stage blocks everyone', () {
        const feature = ManagedFeatureRollout(
          key: 'credit',
          stage: FeatureRolloutStage.disabled,
        );
        expect(feature.isEnabled(), isFalse);
        expect(feature.isEnabled(isAdmin: true), isFalse);
      });

      test('internal stage blocks non-admins', () {
        const feature = ManagedFeatureRollout(
          key: 'credit',
          stage: FeatureRolloutStage.internal,
        );
        expect(feature.isEnabled(), isFalse);
        expect(feature.isEnabled(isAdmin: true), isTrue);
      });

      test('pilot stage allows non-admins', () {
        const feature = ManagedFeatureRollout(
          key: 'credit',
          stage: FeatureRolloutStage.pilot,
        );
        expect(feature.isEnabled(), isTrue);
        expect(feature.isEnabled(isAdmin: true), isTrue);
      });

      test('live stage allows everyone', () {
        const feature = ManagedFeatureRollout(
          key: 'momo',
          stage: FeatureRolloutStage.live,
        );
        expect(feature.isEnabled(), isTrue);
      });
    });

    group('admin-only flag', () {
      test('admin-only blocks regular users', () {
        const feature = ManagedFeatureRollout(key: 'credit', adminOnly: true);
        expect(feature.isEnabled(), isFalse);
        expect(feature.isEnabled(isAdmin: true), isTrue);
      });

      test('admin-only + kill switch disables even for admins', () {
        const feature = ManagedFeatureRollout(
          key: 'credit',
          adminOnly: true,
          killSwitch: true,
        );
        expect(feature.isEnabled(isAdmin: true), isFalse);
      });
    });

    group('precedence', () {
      test('kill switch takes precedence over live stage', () {
        const feature = ManagedFeatureRollout(
          key: 'momo',
          stage: FeatureRolloutStage.live,
          killSwitch: true,
        );
        expect(feature.isEnabled(isAdmin: true), isFalse);
      });

      test('disabled stage takes precedence over admin-only=false', () {
        const feature = ManagedFeatureRollout(
          key: 'credit',
          stage: FeatureRolloutStage.disabled,
        );
        expect(feature.isEnabled(isAdmin: true), isFalse);
      });
    });

    group('copyWith', () {
      test('preserves key while updating fields', () {
        const original = ManagedFeatureRollout(key: 'credit');
        final copy = original.copyWith(killSwitch: true);
        expect(copy.key, 'credit');
        expect(copy.killSwitch, isTrue);
        expect(copy.stage, FeatureRolloutStage.live);
      });
    });

    group('round-trip through remote config', () {
      test('toRemoteConfigDefaults produces parseable values', () {
        const feature = ManagedFeatureRollout(
          key: 'momo',
          stage: FeatureRolloutStage.internal,
          adminOnly: true,
        );
        final defaults = feature.toRemoteConfigDefaults(
          killSwitchKey: 'kill_momo_payments',
        );
        final parsed = ManagedFeatureRollout.fromValues(
          key: 'momo',
          killSwitchKey: 'kill_momo_payments',
          values: defaults.cast<String, Object?>(),
          fallback: const ManagedFeatureRollout(key: 'momo'),
        );
        expect(parsed.stage, FeatureRolloutStage.internal);
        expect(parsed.adminOnly, isTrue);
        expect(parsed.killSwitch, isFalse);
      });
    });
  });

  // ─────────────────────────────────────────────────────────────
  // 2.5b — EngagementFeatureFlags RBAC enforcement
  // ─────────────────────────────────────────────────────────────
  group('EngagementFeatureFlags', () {
    test('defaults enable MoMo and BioPay for everyone', () {
      final flags = EngagementFeatureFlags.defaults();
      expect(flags.isMomoEnabled(), isTrue);
      expect(flags.isBiopayEnabled(), isTrue);
    });

    test('MoMo kill switch disables MoMo and BioPay', () {
      const flags = EngagementFeatureFlags(
        engagementEnabled: true,
        shareTrackingEnabled: true,
        groupCaptainEnabled: false,
        partnerChapterEnabled: false,
        biopayEnabled: true,
        momo: ManagedFeatureRollout(key: 'momo', killSwitch: true),
        credit: ManagedFeatureRollout(key: 'credit'),
      );
      expect(flags.isMomoEnabled(), isFalse);
      expect(flags.killMomoPayments, isTrue);
      // BioPay follows MoMo:
      expect(flags.isBiopayEnabled(), isFalse);
    });

    test('internal MoMo stage blocks non-admins, allows admins', () {
      const flags = EngagementFeatureFlags(
        engagementEnabled: true,
        shareTrackingEnabled: true,
        groupCaptainEnabled: false,
        partnerChapterEnabled: false,
        biopayEnabled: true,
        momo: ManagedFeatureRollout(
          key: 'momo',
          stage: FeatureRolloutStage.internal,
        ),
        credit: ManagedFeatureRollout(key: 'credit'),
      );
      expect(flags.isMomoEnabled(), isFalse);
      expect(flags.isMomoEnabled(isAdmin: true), isTrue);
      // BioPay tracks MoMo:
      expect(flags.isBiopayEnabled(), isFalse);
      expect(flags.isBiopayEnabled(isAdmin: true), isTrue);
    });

    test('credit kill switch is independent of MoMo', () {
      const flags = EngagementFeatureFlags(
        engagementEnabled: true,
        shareTrackingEnabled: true,
        groupCaptainEnabled: false,
        partnerChapterEnabled: false,
        biopayEnabled: true,
        momo: ManagedFeatureRollout(key: 'momo'),
        credit: ManagedFeatureRollout(key: 'credit', killSwitch: true),
      );
      expect(flags.isMomoEnabled(), isTrue);
      expect(flags.credit.isEnabled(), isFalse);
      expect(flags.killCreditFeatures, isTrue);
    });

    test('fromValues round-trip preserves flag states', () {
      const original = EngagementFeatureFlags(
        engagementEnabled: false,
        shareTrackingEnabled: false,
        groupCaptainEnabled: true,
        partnerChapterEnabled: true,
        biopayEnabled: false,
        momo: ManagedFeatureRollout(
          key: 'momo',
          stage: FeatureRolloutStage.pilot,
          adminOnly: true,
        ),
        credit: ManagedFeatureRollout(key: 'credit', killSwitch: true),
      );
      final configValues = original.toRemoteConfigDefaults();
      final parsed = EngagementFeatureFlags.fromValues(
        configValues.cast<String, Object?>(),
      );
      expect(parsed.engagementEnabled, isFalse);
      expect(parsed.shareTrackingEnabled, isFalse);
      expect(parsed.groupCaptainEnabled, isTrue);
      expect(parsed.partnerChapterEnabled, isTrue);
      expect(parsed.momo.stage, FeatureRolloutStage.pilot);
      expect(parsed.momo.adminOnly, isTrue);
      expect(parsed.credit.killSwitch, isTrue);
    });
  });

  // ─────────────────────────────────────────────────────────────
  // 2.5c — FeatureRolloutStage parsing
  // ─────────────────────────────────────────────────────────────
  group('FeatureRolloutStage', () {
    test('fromValue parses all valid values', () {
      expect(
        FeatureRolloutStage.fromValue(
          'live',
          fallback: FeatureRolloutStage.disabled,
        ),
        FeatureRolloutStage.live,
      );
      expect(
        FeatureRolloutStage.fromValue(
          'pilot',
          fallback: FeatureRolloutStage.disabled,
        ),
        FeatureRolloutStage.pilot,
      );
      expect(
        FeatureRolloutStage.fromValue(
          'internal',
          fallback: FeatureRolloutStage.disabled,
        ),
        FeatureRolloutStage.internal,
      );
      expect(
        FeatureRolloutStage.fromValue(
          'disabled',
          fallback: FeatureRolloutStage.live,
        ),
        FeatureRolloutStage.disabled,
      );
    });

    test('fromValue is case-insensitive', () {
      expect(
        FeatureRolloutStage.fromValue(
          'LIVE',
          fallback: FeatureRolloutStage.disabled,
        ),
        FeatureRolloutStage.live,
      );
      expect(
        FeatureRolloutStage.fromValue(
          'Pilot',
          fallback: FeatureRolloutStage.disabled,
        ),
        FeatureRolloutStage.pilot,
      );
    });

    test('fromValue returns fallback for unknown values', () {
      expect(
        FeatureRolloutStage.fromValue(
          'beta',
          fallback: FeatureRolloutStage.disabled,
        ),
        FeatureRolloutStage.disabled,
      );
      expect(
        FeatureRolloutStage.fromValue(null, fallback: FeatureRolloutStage.live),
        FeatureRolloutStage.live,
      );
    });
  });
}
