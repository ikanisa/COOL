import 'package:collect_app/features/collections/group_link_screen.dart';
import 'package:collect_app/shared/repositories/pending_shared_group_intent_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('QR and App Link entry paths resolve the same canonical group', () {
    final uri = Uri.parse(
      'https://collect.ikanisa.com/c/qa-private-group?utm_source=qr',
    );
    expect(pendingSharedGroupSlugFromAppLink(uri), 'qa-private-group');
    expect(collectGroupSlugFromInput(uri.toString()), 'qa-private-group');
    expect(collectGroupSlugFromInput('qa-private-group'), 'qa-private-group');
    expect(
      collectGroupSlugFromInput('collect://group/qa-private-group'),
      'qa-private-group',
    );
  });

  test('conflicting and foreign QR URLs cannot change the target', () {
    for (final raw in [
      'https://collect.ikanisa.com/c/trusted?code=attacker-code',
      'https://collect.ikanisa.com/c/trusted#c/attacker-code',
      'https://evil.example/c/trusted?code=attacker-code',
      'https://user@collect.ikanisa.com/c/trusted',
    ]) {
      expect(pendingSharedGroupSlugFromAppLink(Uri.parse(raw)), isNull);
      expect(collectGroupSlugFromInput(raw), isEmpty);
    }
  });

  test(
    'an explicitly configured share origin is accepted only at its path',
    () {
      final origin = Uri.parse('https://share.example.com/collect');
      const valid = 'https://share.example.com/collect/c/qa-private-group';
      expect(collectGroupSlugFromInput(valid), isEmpty);
      expect(
        collectGroupSlugFromInput(valid, trustedPublicOrigin: origin),
        'qa-private-group',
      );
      expect(
        collectGroupSlugFromInput(
          'https://share.example.com/other/c/qa-private-group',
          trustedPublicOrigin: origin,
        ),
        isEmpty,
      );
    },
  );
}
