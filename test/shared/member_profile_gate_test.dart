import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  const rw = CollectProfile(
    id: 'rw',
    publicId: '123456',
    whatsappPhone: '+250788123456',
    countryCode: 'RW',
    currencyCode: 'RWF',
    momoProvider: 'mtn_momo',
    momoNumber: '0788123456',
  );
  const diaspora = CollectProfile(
    id: 'diaspora',
    publicId: '654321',
    whatsappPhone: '+35699123456',
    countryCode: 'MT',
    currencyCode: 'EUR',
    revolutAccount: '000123456789',
  );

  for (final profile in [
    rw.copyWith(momoNumber: ''),
    rw.copyWith(momoProvider: ''),
    rw.copyWith(currencyCode: 'EUR'),
    diaspora.copyWith(revolutAccount: ''),
    diaspora.copyWith(revolutAccount: 'not an account'),
  ]) {
    test(
      'incomplete ${profile.id} cannot join, contribute or create: ${profile.momoNumber}/${profile.momoProvider}/${profile.currencyCode}/${profile.revolutAccount}',
      () async {
        final repo = CollectRepository.fixture(profileOverride: profile);
        addTearDown(repo.dispose);
        final priorIntents = [...repo.state.paymentIntents];
        final group = repo.state.collections.first;
        await expectLater(
          repo.joinGroupBySlug(group.slug),
          throwsFormatException,
        );
        await expectLater(
          repo.createPaymentIntent(
            PaymentIntentDraft(collectionId: group.id, amountRwf: 1000),
          ),
          throwsFormatException,
        );
        await expectLater(
          repo.createCollection(title: 'Fixture group', description: ''),
          throwsFormatException,
        );
        expect(repo.state.paymentIntents, priorIntents);
      },
    );
  }

  for (final profile in [rw, diaspora]) {
    test(
      'complete ${profile.id} can join without the other country rail',
      () async {
        final repo = CollectRepository.fixture(profileOverride: profile);
        addTearDown(repo.dispose);
        final group = repo.state.collections.first;
        expect((await repo.joinGroupBySlug(group.slug)).id, group.id);
      },
    );
  }
}
