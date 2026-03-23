import 'dart:io';

import 'package:cool_app/core/config/country_catalog.dart';
import 'package:cool_app/features/biopay/models/biopay_match_result.dart';
import 'package:cool_app/features/biopay/models/biopay_profile.dart';
import 'package:cool_app/features/biopay/services/biopay_cache_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory hiveDir;
  late BiopayCacheService cacheService;

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('cool_biopay_cache');
    Hive.init(hiveDir.path);
  });

  setUp(() {
    cacheService = BiopayCacheService(openBox: Hive.openBox<dynamic>);
  });

  tearDown(() async {
    if (Hive.isBoxOpen(BiopayCacheService.boxName)) {
      await Hive.box<dynamic>(BiopayCacheService.boxName).clear();
      await Hive.box<dynamic>(BiopayCacheService.boxName).close();
    }
    await Hive.deleteBoxFromDisk(BiopayCacheService.boxName);
  });

  tearDownAll(() async {
    await hiveDir.delete(recursive: true);
  });

  group('BiopayCacheService', () {
    test(
      'returns the nearest cached match above the similarity threshold',
      () async {
        const ownerUserId = 'requester-1';
        final resultA = _resultFor(
          const BiopayProfile(
            id: 'profile-a',
            publicId: '111111',
            userId: 'user-a',
            displayName: 'Uwimana Marie',
            routeType: MomoRecipientType.phoneNumber,
            recipientValue: '0781234567',
            countryCode: 'RW',
            active: true,
            consentVersion: 'biopay-v1',
          ),
          score: 0.88,
        );
        final resultB = _resultFor(
          const BiopayProfile(
            id: 'profile-b',
            publicId: '222222',
            userId: 'user-b',
            displayName: 'Bizimana Claude',
            routeType: MomoRecipientType.code,
            recipientValue: '445566',
            countryCode: 'RW',
            active: true,
            consentVersion: 'biopay-v1',
          ),
          score: 0.91,
        );

        await cacheService.storeMatch(ownerUserId, const <double>[
          1.0,
          0.0,
          0.0,
        ], resultA);
        await cacheService.storeMatch(ownerUserId, const <double>[
          0.0,
          1.0,
          0.0,
        ], resultB);

        final match = await cacheService.findNearestMatch(
          const <double>[0.98, 0.18, 0.0],
          ownerUserId: ownerUserId,
          similarityThreshold: 0.80,
        );

        expect(match, isNotNull);
        expect(match!.cached, isTrue);
        expect(match.profile?.id, 'profile-a');
        expect(match.profile?.displayName, 'Uwimana Marie');
        expect(match.profile?.recipientValue, isEmpty);
      },
    );

    test('drops expired cache entries before returning a match', () async {
      const ownerUserId = 'requester-1';
      final result = _resultFor(
        const BiopayProfile(
          id: 'profile-expired',
          publicId: '333333',
          userId: 'user-expired',
          displayName: 'Expired Payee',
          routeType: MomoRecipientType.phoneNumber,
          recipientValue: '0780000000',
          countryCode: 'RW',
          active: true,
          consentVersion: 'biopay-v1',
        ),
      );

      await cacheService.storeMatch(
        ownerUserId,
        const <double>[1.0, 0.0, 0.0],
        result,
        ttl: const Duration(milliseconds: 1),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final match = await cacheService.findNearestMatch(
        const <double>[1.0, 0.0, 0.0],
        ownerUserId: ownerUserId,
        similarityThreshold: 0.80,
      );
      final box = await Hive.openBox<dynamic>(BiopayCacheService.boxName);

      expect(match, isNull);
      expect(box.isEmpty, isTrue);
    });

    test('does not leak cached matches across signed-in users', () async {
      final result = _resultFor(
        const BiopayProfile(
          id: 'profile-owned',
          publicId: '444444',
          userId: 'payee-1',
          displayName: 'Owner Only',
          routeType: MomoRecipientType.code,
          recipientValue: '112233',
          countryCode: 'RW',
          active: true,
          consentVersion: 'biopay-v1',
        ),
      );

      await cacheService.storeMatch('requester-a', const <double>[
        1.0,
        0.0,
        0.0,
      ], result);

      final leakedMatch = await cacheService.findNearestMatch(
        const <double>[1.0, 0.0, 0.0],
        ownerUserId: 'requester-b',
        similarityThreshold: 0.80,
      );

      expect(leakedMatch, isNull);
    });
  });
}

BiopayMatchResult _resultFor(BiopayProfile profile, {double score = 0.94}) {
  return BiopayMatchResult(match: true, score: score, profile: profile);
}
