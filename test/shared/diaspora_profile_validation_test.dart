import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  const profile = CollectProfile(
    id: 'fixture-member',
    publicId: '123456',
    whatsappPhone: '+250788123456',
    countryCode: 'DE',
    currencyCode: 'EUR',
    revolutAccount: '000123456789',
  );

  test('diaspora completeness requires account only, not MoMo or a link', () {
    expect(profile.isComplete, isTrue);
    expect(profile.momoNumber, isEmpty);
    expect(profile.revolutLink, isEmpty);
    expect(
      profile.copyWith(revolutLink: 'retired-invalid-link').isComplete,
      isTrue,
    );
    expect(profile.copyWith(revolutAccount: '').isComplete, isFalse);
  });

  for (final account in [
    '',
    '123',
    'a' * 12,
    '💶1234',
    'https://bank/1234',
    '1' * 35,
  ]) {
    test(
      'invalid account is rejected by completeness and save: $account',
      () async {
        expect(profile.copyWith(revolutAccount: account).isComplete, isFalse);
        final repository = CollectRepository.fixture(profileOverride: profile);
        addTearDown(repository.dispose);
        await expectLater(
          repository.updateCurrentProfile(
            countryCode: 'DE',
            revolutAccount: account,
          ),
          throwsFormatException,
        );
        expect(
          repository.state.currentProfile?.revolutAccount,
          profile.revolutAccount,
        );
      },
    );
  }

  test(
    'account-only save preserves leading zeros and numeric identity',
    () async {
      final repository = CollectRepository.fixture(profileOverride: profile);
      addTearDown(repository.dispose);
      final saved = await repository.updateCurrentProfile(
        countryCode: 'DE',
        revolutAccount: '0001-2345 6789',
      );
      expect(saved.revolutAccount, '000123456789');
      expect(saved.publicId, profile.publicId);
      expect(saved.whatsappPhone, profile.whatsappPhone);
      expect(saved.isComplete, isTrue);
    },
  );

  test('account identifiers allow IBAN and local alphanumeric syntax', () {
    for (final account in [
      'DE89 3704 0044 0532 0130 00',
      'AB123456',
      '0' * 34,
    ]) {
      expect(profile.copyWith(revolutAccount: account).isComplete, isTrue);
    }
  });
}
