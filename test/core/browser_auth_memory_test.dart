import 'package:collect_app/core/cloudflare/collect_cloudflare_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('browser page memory is independent and discarded at reload', () async {
    final first = CollectMemorySessionStorage();
    final second = CollectMemorySessionStorage();
    await first.write('synthetic-session-only');
    expect(await first.read(), 'synthetic-session-only');
    expect(await second.read(), isNull);
    expect(await CollectMemorySessionStorage().read(), isNull);
    await first.clear();
    expect(await first.read(), isNull);
  });
  test('separate clients do not share browser credentials or events', () async {
    final first = CollectCloudflareClient('https://fixture.example.invalid');
    final second = CollectCloudflareClient('https://fixture.example.invalid');
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    await first.initialize();
    await second.initialize();
    expect(first.auth.currentSession, isNull);
    expect(second.auth.currentSession, isNull);
    expect(first.auth, isNot(same(second.auth)));
  });
}
