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
  test('locale provider always returns English', () async {
    final store = FakeLocaleStore(readValue: 'sw');
    final container = createTestContainer(localeStore: store);

    expect(container.read(localeProvider).languageCode, 'en');

    await pumpEventQueue();

    expect(container.read(localeProvider).languageCode, 'en');
  });

  test('locale notifier ignores setLocale — always stays English', () async {
    final store = FakeLocaleStore(readValue: 'en');
    final container = createTestContainer(localeStore: store);

    await pumpEventQueue();

    // Try to switch to another locale — should be ignored.
    await container.read(localeProvider.notifier).setLocale('sw');
    expect(container.read(localeProvider).languageCode, 'en');
    expect(store.writes, isEmpty);
  });

  test('locale provider normalizes unsupported persisted languages', () async {
    final store = FakeLocaleStore(readValue: 'de');
    final container = createTestContainer(localeStore: store);

    expect(container.read(localeProvider).languageCode, 'en');

    await pumpEventQueue();
    // English-only — ignores German value.
    expect(container.read(localeProvider).languageCode, 'en');
  });
}
