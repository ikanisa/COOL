import 'package:cool_app/core/l10n/locale_provider.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/test_bootstrap.dart';

class FakeLocaleStore implements LocaleStore {
  FakeLocaleStore({required this.readValue});

  String readValue;
  final List<String> writes = <String>[];

  @override
  Future<String> readLanguageCode() async => readValue;

  @override
  Future<void> writeLanguageCode(String languageCode) async {
    writes.add(languageCode);
    readValue = languageCode;
  }
}

void main() {
  test(
    'locale provider loads persisted language from the injected store',
    () async {
      final store = FakeLocaleStore(readValue: 'fr');
      final container = createTestContainer(localeStore: store);

      expect(container.read(localeProvider).languageCode, 'en');

      await pumpEventQueue();

      expect(container.read(localeProvider).languageCode, 'fr');
    },
  );

  test('locale provider normalizes unsupported persisted languages', () async {
    final store = FakeLocaleStore(readValue: 'de');
    final container = createTestContainer(localeStore: store);

    expect(container.read(localeProvider).languageCode, 'en');

    await pumpEventQueue();
    expect(container.read(localeProvider).languageCode, 'en');
  });

  test('locale notifier persists updates through the injected store', () async {
    final store = FakeLocaleStore(readValue: 'en');
    final container = createTestContainer(localeStore: store);

    expect(container.read(localeProvider).languageCode, 'en');

    await pumpEventQueue();
    expect(container.read(localeProvider).languageCode, 'en');

    await container.read(localeProvider.notifier).setLocale('fr');

    expect(container.read(localeProvider).languageCode, 'fr');
    expect(store.writes, <String>['fr']);
  });

  test(
    'locale notifier falls back to english for unsupported updates',
    () async {
      final store = FakeLocaleStore(readValue: 'en');
      final container = createTestContainer(localeStore: store);

      await pumpEventQueue();
      await container.read(localeProvider.notifier).setLocale('rw');

      expect(container.read(localeProvider).languageCode, 'en');
      expect(store.writes, <String>['en']);
    },
  );
}
