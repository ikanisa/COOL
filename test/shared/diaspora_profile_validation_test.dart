import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const profile = CollectProfile(
    id: 'fixture-member',
    publicId: '123456',
    whatsappPhone: '+250788123456',
    countryCode: 'DE',
    currencyCode: 'EUR',
    revolutLink: 'https://revolut.me/fixture',
    revolutAccount: 'Synthetic account',
  );

  for (final link in [
    'https://notrevolut.me/fixture',
    'http://revolut.me/fixture',
    'ftp://revolut.me/fixture',
    'https://revolut.me',
    'https://revolut.me/',
    'https://user:password@revolut.me/fixture',
    'https://revolut.me:444/fixture',
    'https://revolut.me/fixture?redirect=elsewhere',
    'https://revolut.me/fixture#fragment',
    'https://revolut.me/fixture/extra',
  ]) {
    test('profile and save reject non-contract Revolut URL: $link', () async {
      final candidate = profile.copyWith(revolutLink: link);
      expect(candidate.isComplete, isFalse);
      final repository = CollectRepository.fixture(profileOverride: profile);
      addTearDown(repository.dispose);
      await expectLater(
        repository.updateCurrentProfile(
          countryCode: 'DE',
          revolutLink: link,
          revolutAccount: 'Synthetic account',
        ),
        throwsFormatException,
      );
      expect(repository.state.currentProfile?.revolutLink, profile.revolutLink);
    });
  }

  test('complete profile enforces the saved account length limit', () {
    expect(profile.copyWith(revolutAccount: 'a' * 121).isComplete, isFalse);
    expect(profile.copyWith(revolutAccount: 'abc').isComplete, isFalse);
    expect(profile.copyWith(revolutAccount: 'a' * 120).isComplete, isTrue);
    expect(profile.copyWith(revolutAccount: '💶' * 120).isComplete, isTrue);
    expect(profile.copyWith(revolutAccount: '💶' * 121).isComplete, isFalse);
  });

  test('the existing backend URL contract remains accepted', () {
    for (final link in [
      'https://revolut.me/fixture',
      'https://revolut.me/fixture_1/',
      'https://www.revolut.me/fixture.1',
    ]) {
      expect(profile.copyWith(revolutLink: link).isComplete, isTrue);
    }
  });
}
