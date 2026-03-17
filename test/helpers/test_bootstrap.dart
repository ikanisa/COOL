import 'package:cool_app/core/l10n/locale_provider.dart';
import 'package:cool_app/core/providers/supabase_client_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show GoTrueClient, SupabaseClient;

import 'package:cool_app/core/providers/app_access_provider.dart';
import 'package:cool_app/core/services/app_access_service.dart';
import 'fake_app_access_service.dart';

class MockGoTrueClient extends Mock implements GoTrueClient {}

class MockSupabaseClient extends Mock implements SupabaseClient {
  @override
  GoTrueClient get auth => MockGoTrueClient();
}

class MemoryLocaleStore implements LocaleStore {
  MemoryLocaleStore([this._languageCode = 'en']);

  String _languageCode;

  @override
  Future<String> readLanguageCode() async => _languageCode;

  @override
  Future<void> writeLanguageCode(String languageCode) async {
    _languageCode = languageCode;
  }
}

ProviderContainer createTestContainer({
  List<Override> overrides = const <Override>[],
  LocaleStore? localeStore,
  ProviderContainer? parent,
}) {
  final container = ProviderContainer(
    parent: parent,
    overrides: <Override>[
      localeStoreProvider.overrideWithValue(localeStore ?? MemoryLocaleStore()),
      supabaseClientProvider.overrideWithValue(MockSupabaseClient()),
      appAccessServiceProvider.overrideWithValue(FakeAppAccessService()),
      ...overrides,
    ],
  );
  addTearDown(container.dispose);
  return container;
}
