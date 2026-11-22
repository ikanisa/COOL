import 'package:flutter/foundation.dart' show immutable;

import 'collect_model_json_helpers.dart';

const collectDefaultCollectionTypeCatalog = CollectionTypeCatalogConfig(
  countryCode: 'RW',
  locale: 'en',
  types: [
    CollectionTypeCatalogItem(
      type: CollectionType.ikimina,
      label: 'Ikimina',
      shortPurpose: 'Group savings',
      iconKey: 'savings',
      defaultCategorySubtype: 'group_savings',
      defaultPurposeTemplateKey: 'group_savings',
      subtypes: [
        CollectionCatalogOption(key: 'group_savings', label: 'Group savings'),
        CollectionCatalogOption(
          key: 'family_friends',
          label: 'Family or friends',
        ),
        CollectionCatalogOption(
          key: 'community_event',
          label: 'Community event',
        ),
      ],
      purposeTemplates: [
        CollectionCatalogOption(key: 'group_savings', label: 'Group savings'),
        CollectionCatalogOption(key: 'member_support', label: 'Member support'),
      ],
    ),
    CollectionTypeCatalogItem(
      type: CollectionType.sport,
      label: 'Sport',
      shortPurpose: 'Fan club support',
      iconKey: 'sport',
      defaultCategorySubtype: 'fan_club',
      defaultPurposeTemplateKey: 'fan_club_support',
      subtypes: [
        CollectionCatalogOption(key: 'fan_club', label: 'Fan club'),
        CollectionCatalogOption(key: 'team_support', label: 'Team support'),
        CollectionCatalogOption(key: 'away_travel', label: 'Away travel'),
      ],
      purposeTemplates: [
        CollectionCatalogOption(
          key: 'fan_club_support',
          label: 'Fan club support',
        ),
        CollectionCatalogOption(key: 'away_travel', label: 'Away travel'),
      ],
    ),
    CollectionTypeCatalogItem(
      type: CollectionType.church,
      label: 'Church',
      shortPurpose: 'Offering and donations',
      iconKey: 'church',
      defaultCategorySubtype: 'offering',
      defaultPurposeTemplateKey: 'offering_and_donations',
      subtypes: [
        CollectionCatalogOption(key: 'offering', label: 'Offering'),
        CollectionCatalogOption(key: 'tithe', label: 'Tithe'),
        CollectionCatalogOption(
          key: 'project_support',
          label: 'Project support',
        ),
      ],
      purposeTemplates: [
        CollectionCatalogOption(
          key: 'offering_and_donations',
          label: 'Offering and donations',
        ),
        CollectionCatalogOption(key: 'church_project', label: 'Church project'),
      ],
    ),
    CollectionTypeCatalogItem(
      type: CollectionType.wedding,
      label: 'Wedding',
      shortPurpose: 'Wedding contributions',
      iconKey: 'wedding',
      defaultCategorySubtype: 'committee',
      defaultPurposeTemplateKey: 'wedding_contributions',
      subtypes: [
        CollectionCatalogOption(key: 'committee', label: 'Committee'),
        CollectionCatalogOption(key: 'gift', label: 'Gift'),
        CollectionCatalogOption(
          key: 'ceremony_support',
          label: 'Ceremony support',
        ),
      ],
      purposeTemplates: [
        CollectionCatalogOption(
          key: 'wedding_contributions',
          label: 'Wedding contributions',
        ),
        CollectionCatalogOption(key: 'wedding_gifts', label: 'Wedding gifts'),
      ],
    ),
    CollectionTypeCatalogItem(
      type: CollectionType.other,
      label: 'Other',
      shortPurpose: 'Custom collection',
      iconKey: 'collections',
      defaultCategorySubtype: 'custom',
      defaultPurposeTemplateKey: 'custom_collection',
      subtypes: [CollectionCatalogOption(key: 'custom', label: 'Custom')],
      purposeTemplates: [
        CollectionCatalogOption(
          key: 'custom_collection',
          label: 'Custom collection',
        ),
      ],
    ),
  ],
);

enum CollectionType {
  ikimina,
  sport,
  church,
  wedding,
  other;

  static CollectionType fromJson(Object? value) {
    final normalized = value?.toString().trim().toLowerCase();
    return switch (normalized) {
      'ikimina' ||
      'ibimina' ||
      'group_savings' ||
      'group savings' => CollectionType.ikimina,
      'sport' ||
      'sports' ||
      'fan_club' ||
      'fan club' ||
      'sports team' => CollectionType.sport,
      'church' || 'offering' || 'tithe' => CollectionType.church,
      'wedding' || 'wedding_contribution' => CollectionType.wedding,
      _ => CollectionType.other,
    };
  }

  String get storageValue => switch (this) {
    CollectionType.ikimina => 'ikimina',
    CollectionType.sport => 'sport',
    CollectionType.church => 'church',
    CollectionType.wedding => 'wedding',
    CollectionType.other => 'other',
  };

  String get label => switch (this) {
    CollectionType.ikimina => 'Ikimina',
    CollectionType.sport => 'Sport',
    CollectionType.church => 'Church',
    CollectionType.wedding => 'Wedding',
    CollectionType.other => 'Other',
  };

  String get shortPurpose => switch (this) {
    CollectionType.ikimina => 'Group savings',
    CollectionType.sport => 'Fan club support',
    CollectionType.church => 'Offering and donations',
    CollectionType.wedding => 'Wedding contributions',
    CollectionType.other => 'Custom collection',
  };
}

@immutable
class CollectionTypeCatalogConfig {
  const CollectionTypeCatalogConfig({
    required this.countryCode,
    required this.locale,
    required this.types,
  });

  final String countryCode;
  final String locale;
  final List<CollectionTypeCatalogItem> types;

  static const defaults = collectDefaultCollectionTypeCatalog;

  factory CollectionTypeCatalogConfig.fromJson(Map<String, dynamic> json) {
    const fallback = CollectionTypeCatalogConfig.defaults;
    final types = [
      for (final item in modelJsonMaps(json['types']))
        CollectionTypeCatalogItem.fromJson(item),
    ];
    return CollectionTypeCatalogConfig(
      countryCode: nonEmptyModelText(
        json['country_code'],
        fallback.countryCode,
      ),
      locale: nonEmptyModelText(json['locale'], fallback.locale),
      types: types.isEmpty ? fallback.types : types,
    );
  }

  CollectionTypeCatalogItem optionFor(CollectionType type) {
    return types.firstWhere(
      (item) => item.type == type,
      orElse: () => CollectionTypeCatalogConfig.defaults.types.firstWhere(
        (item) => item.type == type,
      ),
    );
  }
}

@immutable
class CollectionTypeCatalogItem {
  const CollectionTypeCatalogItem({
    required this.type,
    required this.label,
    required this.shortPurpose,
    required this.iconKey,
    required this.defaultCategorySubtype,
    required this.defaultPurposeTemplateKey,
    required this.subtypes,
    required this.purposeTemplates,
  });

  final CollectionType type;
  final String label;
  final String shortPurpose;
  final String iconKey;
  final String defaultCategorySubtype;
  final String defaultPurposeTemplateKey;
  final List<CollectionCatalogOption> subtypes;
  final List<CollectionCatalogOption> purposeTemplates;

  factory CollectionTypeCatalogItem.fromJson(Map<String, dynamic> json) {
    final type = CollectionType.fromJson(json['key']);
    final fallback = CollectionTypeCatalogConfig.defaults.optionFor(type);
    final subtypes = [
      for (final item in modelJsonMaps(json['subtypes']))
        CollectionCatalogOption.fromJson(item),
    ];
    final purposeTemplates = [
      for (final item in modelJsonMaps(json['purpose_templates']))
        CollectionCatalogOption.fromJson(item),
    ];
    return CollectionTypeCatalogItem(
      type: type,
      label: nonEmptyModelText(json['label'], fallback.label),
      shortPurpose: nonEmptyModelText(
        json['short_purpose'],
        fallback.shortPurpose,
      ),
      iconKey: nonEmptyModelText(json['icon_key'], fallback.iconKey),
      defaultCategorySubtype: nonEmptyModelText(
        json['default_category_subtype'],
        fallback.defaultCategorySubtype,
      ),
      defaultPurposeTemplateKey: nonEmptyModelText(
        json['default_purpose_template_key'],
        fallback.defaultPurposeTemplateKey,
      ),
      subtypes: subtypes.isEmpty ? fallback.subtypes : subtypes,
      purposeTemplates: purposeTemplates.isEmpty
          ? fallback.purposeTemplates
          : purposeTemplates,
    );
  }

  String get defaultPurposeLabel {
    return purposeTemplates
        .firstWhere(
          (item) => item.key == defaultPurposeTemplateKey,
          orElse: () => CollectionCatalogOption(
            key: defaultPurposeTemplateKey,
            label: shortPurpose,
          ),
        )
        .label;
  }
}

@immutable
class CollectionCatalogOption {
  const CollectionCatalogOption({required this.key, required this.label});

  final String key;
  final String label;

  factory CollectionCatalogOption.fromJson(Map<String, dynamic> json) {
    return CollectionCatalogOption(
      key: nonEmptyModelText(json['key'], ''),
      label: nonEmptyModelText(json['label'], 'Option'),
    );
  }
}
