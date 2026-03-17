import 'package:cool_app/features/partners/models/partner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PartnerCategory', () {
    test('fromString maps known values', () {
      expect(PartnerCategory.fromString('football'), PartnerCategory.football);
      expect(PartnerCategory.fromString('bank'), PartnerCategory.bank);
      expect(
        PartnerCategory.fromString('organization'),
        PartnerCategory.organization,
      );
    });

    test('fromString handles null and unknown gracefully', () {
      expect(PartnerCategory.fromString(null), PartnerCategory.organization);
      expect(
        PartnerCategory.fromString('unknown'),
        PartnerCategory.organization,
      );
    });

    test('fromString is case-insensitive', () {
      expect(PartnerCategory.fromString('FOOTBALL'), PartnerCategory.football);
      expect(PartnerCategory.fromString('Bank'), PartnerCategory.bank);
    });
  });

  group('Partner', () {
    const sampleJson = <String, dynamic>{
      'id': '550e8400-e29b-41d4-a716-446655440000',
      'name': 'APR FC',
      'slug': 'apr-fc',
      'category': 'football',
      'country': 'RW',
      'emoji': '⚽',
      'subtitle': 'Rwanda Premier League',
      'description': 'Fan hub for APR FC.',
      'whatsapp_number': '250788000001',
      'logo_url': null,
      'fan_count': 12480,
      'club_count': 34,
      'game_count': 5,
      'is_active': true,
      'sort_order': 0,
      'created_at': '2026-03-01T00:00:00Z',
      'updated_at': '2026-03-10T12:00:00Z',
    };

    test('fromJson parses correctly', () {
      final partner = Partner.fromJson(sampleJson);

      expect(partner.id, '550e8400-e29b-41d4-a716-446655440000');
      expect(partner.name, 'APR FC');
      expect(partner.slug, 'apr-fc');
      expect(partner.category, PartnerCategory.football);
      expect(partner.country, 'RW');
      expect(partner.emoji, '⚽');
      expect(partner.subtitle, 'Rwanda Premier League');
      expect(partner.description, 'Fan hub for APR FC.');
      expect(partner.whatsappNumber, '250788000001');
      expect(partner.logoUrl, isNull);
      expect(partner.fanCount, 12480);
      expect(partner.clubCount, 34);
      expect(partner.gameCount, 5);
      expect(partner.isActive, isTrue);
      expect(partner.sortOrder, 0);
      expect(partner.createdAt, isNotNull);
      expect(partner.updatedAt, isNotNull);
    });

    test('toJson produces expected output', () {
      final partner = Partner.fromJson(sampleJson);
      final json = partner.toJson();

      expect(json['id'], partner.id);
      expect(json['name'], 'APR FC');
      expect(json['slug'], 'apr-fc');
      expect(json['category'], 'football');
      expect(json['country'], 'RW');
      expect(json['emoji'], '⚽');
      expect(json['whatsapp_number'], '250788000001');
      expect(json['fan_count'], 12480);
      expect(json['is_active'], true);
      expect(json['sort_order'], 0);
    });

    test('fromJson / toJson round-trip preserves data', () {
      final original = Partner.fromJson(sampleJson);
      final roundTripped = Partner.fromJson(original.toJson());

      expect(roundTripped.id, original.id);
      expect(roundTripped.name, original.name);
      expect(roundTripped.slug, original.slug);
      expect(roundTripped.category, original.category);
      expect(roundTripped.country, original.country);
      expect(roundTripped.emoji, original.emoji);
      expect(roundTripped.subtitle, original.subtitle);
      expect(roundTripped.description, original.description);
      expect(roundTripped.whatsappNumber, original.whatsappNumber);
      expect(roundTripped.fanCount, original.fanCount);
      expect(roundTripped.clubCount, original.clubCount);
      expect(roundTripped.gameCount, original.gameCount);
      expect(roundTripped.isActive, original.isActive);
      expect(roundTripped.sortOrder, original.sortOrder);
    });

    test('fromJson handles missing optional fields', () {
      final minimal = <String, dynamic>{
        'id': 'abc-123',
        'name': 'Test Partner',
      };

      final partner = Partner.fromJson(minimal);

      expect(partner.slug, '');
      expect(partner.category, PartnerCategory.organization);
      expect(partner.country, 'RW');
      expect(partner.emoji, '🤝');
      expect(partner.subtitle, isNull);
      expect(partner.description, isNull);
      expect(partner.whatsappNumber, isNull);
      expect(partner.logoUrl, isNull);
      expect(partner.fanCount, 0);
      expect(partner.clubCount, 0);
      expect(partner.gameCount, 0);
      expect(partner.isActive, isTrue);
      expect(partner.sortOrder, 0);
      expect(partner.createdAt, isNull);
      expect(partner.updatedAt, isNull);
    });

    test('equality is based on id', () {
      final a = Partner.fromJson(sampleJson);
      // ignore: prefer_const_literals_to_create_immutables
      final b = Partner.fromJson(<String, dynamic>{...sampleJson, 'name': 'Different Name'});
      // ignore: prefer_const_literals_to_create_immutables
      final c = Partner.fromJson(<String, dynamic>{...sampleJson, 'id': 'different-id'});

      expect(a, equals(b));
      expect(a, isNot(equals(c)));
      expect(a.hashCode, b.hashCode);
    });

    test('toString includes key fields', () {
      final partner = Partner.fromJson(sampleJson);
      final str = partner.toString();

      expect(str, contains('apr-fc'));
      expect(str, contains('APR FC'));
      expect(str, contains('football'));
      expect(str, contains('RW'));
    });
  });
}
