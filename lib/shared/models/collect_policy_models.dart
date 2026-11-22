import 'package:flutter/foundation.dart' show immutable;

import 'collect_model_json_helpers.dart';

const collectDefaultPrivacyPolicySections = [
  CollectPolicySection(
    title: 'Data we collect',
    body:
        'Collect stores your numeric Collect ID, Rwanda profile, the phone number or email used to sign in, and MoMo provider and number, group memberships, contribution requests, ledger records, and permission status. The member app does not request or display personal names. Names contained in consented MoMo receipts remain in access-controlled Admin reconciliation records.',
  ),
  CollectPolicySection(
    title: 'Signing in',
    body:
        'Depending on what is enabled, you can sign in using an SMS code, an email code or Google. If you choose Google, Collect receives and stores your Google account identifier and verified email to create or link your member account and authenticate you. Google sign-in requests OpenID identity, email and basic profile access. Collect keeps verification, session and security records; a sign-in code expiring does not delete those records.',
  ),
  CollectPolicySection(
    title: 'Automatic SMS detection',
    body:
        'On Android, if you enable SMS access, Collect automatically checks new messages for possible MoMo receipts. The filter may select unrelated messages containing sensitive information. Collect may automatically send their full text and sender, and receipt time when available, linked to your account. You can turn access off in App permissions, but this cannot recall sent messages and may not stop uploads already in progress.',
  ),
  CollectPolicySection(
    title: 'How we use data',
    body:
        'We use this data to create and join groups, review contribution evidence, keep ledgers accurate, show notifications, prevent misuse, provide support, and maintain reconciliation audit records.',
  ),
  CollectPolicySection(
    title: 'What stays private',
    body:
        'Sign-in phones, MoMo numbers, payer details, raw receipt text, and support evidence are not shown on public group cards or public share links. Member-facing screens use Collect IDs and safe contribution status.',
  ),
  CollectPolicySection(
    title: 'Sharing',
    body:
        'Supabase provides Collect authentication, database and private evidence storage. Cloudflare provides web hosting, API forwarding and security challenges. Records and recovery copies from the earlier Cloudflare backend may remain in retained systems or archives; changing providers does not erase them. Google provides identity verification when you choose Google where enabled. Other enabled service providers receive only what is needed for authentication, messaging, support, analytics or contribution verification. We do not sell personal data.',
  ),
  CollectPolicySection(
    title: 'Android camera code scanning',
    body:
        'Where available, Collect Android camera code scanning uses Google ML Kit. ML Kit processes scanning input on your device and does not send input images or decoded code values to Google. The SDK may connect to Google for updates or compatibility checks and may send device and app information, per-install identifiers, and performance, configuration, event and error diagnostics to Google. With automatic zoom, these diagnostics may also include a per-scan identifier, zoom changes and candidate code bounding-box coordinates. Read the Google ML Kit terms at https://developers.google.com/ml-kit/terms and Android SDK data disclosure at https://developers.google.com/ml-kit/android-data-disclosure.',
  ),
  CollectPolicySection(
    title: 'Choices and retention',
    body:
        'Open Settings > Security > Delete data to verify your identity and submit an account deletion request for review. Submitting a request does not delete your account or records. A confirmed receipt records your request for review; check or refresh request status in the app. Check request status or contact support for the outcome and any records that need to be retained. You can leave groups where supported and contact info@ikanisa.com for help or correction requests.',
  ),
];

const collectDefaultTermsSections = [
  CollectPolicySection(
    title: 'Using Collect',
    body:
        'Collect helps groups organize contributions, open Rwanda MoMo USSD, share group QR codes, and maintain a contribution ledger. A recorded contribution or receipt alone does not verify provider settlement. You must use accurate group, receiver, beneficiary, and transfer information.',
  ),
  CollectPolicySection(
    title: 'Contribution rails',
    body:
        'Members approve MoMo payments in USSD. Collect never asks for a MoMo PIN, card details or payment provider OTPs. Your Collect sign-in code is only for signing in to Collect.',
  ),
  CollectPolicySection(
    title: 'Group ownership',
    body:
        'Every member-created group is private. Creating group metadata does not enable payments or SMS access. Group owners manage profile details and membership. Public groups are platform-sponsored and approved by Collect.',
  ),
  CollectPolicySection(
    title: 'Disputes and corrections',
    body:
        'If a contribution is missing, duplicated, returned, incorrect, or needs review, contact support. Collect may use request status, MoMo receipt facts, and audit logs to investigate.',
  ),
  CollectPolicySection(
    title: 'Acceptable use',
    body:
        'Do not create misleading groups, impersonate another person, abuse QR links, submit false contribution claims, or use Collect to request illegal or unauthorized transfers.',
  ),
];

const collectDefaultAccountDeletionReasons = [
  AccountRequestReasonOption(
    key: 'no_longer_use_collect',
    label: 'I no longer use Collect',
  ),
  AccountRequestReasonOption(
    key: 'joined_by_mistake',
    label: 'I joined by mistake',
  ),
  AccountRequestReasonOption(
    key: 'prefer_not_to_keep_data',
    label: 'I prefer not to keep my data',
  ),
];

@immutable
class CollectPolicyDocument {
  const CollectPolicyDocument({
    required this.kind,
    required this.title,
    required this.version,
    required this.locale,
    required this.sections,
  });

  final String kind;
  final String title;
  final String version;
  final String locale;
  final List<CollectPolicySection> sections;

  factory CollectPolicyDocument.defaults(String kind) {
    final normalized = kind.trim().toLowerCase();
    final isPrivacy = normalized == 'privacy';
    return CollectPolicyDocument(
      kind: isPrivacy ? 'privacy' : 'terms',
      title: isPrivacy ? 'Privacy Policy' : 'Terms & Conditions',
      version: 'local-fallback',
      locale: 'en',
      sections: isPrivacy
          ? collectDefaultPrivacyPolicySections
          : collectDefaultTermsSections,
    );
  }

  factory CollectPolicyDocument.fromJson(
    Map<String, dynamic> json, {
    required String fallbackKind,
  }) {
    final fallback = CollectPolicyDocument.defaults(fallbackKind);
    final sections = [
      for (final item in modelJsonMaps(json['sections']))
        CollectPolicySection.fromJson(item),
    ];
    return CollectPolicyDocument(
      kind: nonEmptyModelText(json['kind'], fallback.kind),
      title: nonEmptyModelText(json['title'], fallback.title),
      version: nonEmptyModelText(json['version'], fallback.version),
      locale: nonEmptyModelText(json['locale'], fallback.locale),
      sections: sections.isEmpty ? fallback.sections : sections,
    );
  }
}

@immutable
class CollectPolicySection {
  const CollectPolicySection({required this.title, required this.body});

  final String title;
  final String body;

  factory CollectPolicySection.fromJson(Map<String, dynamic> json) {
    return CollectPolicySection(
      title: nonEmptyModelText(json['title'], 'Policy'),
      body: nonEmptyModelText(json['body'], ''),
    );
  }
}

@immutable
class AccountRequestReasonOption {
  const AccountRequestReasonOption({required this.key, required this.label});

  final String key;
  final String label;

  factory AccountRequestReasonOption.fromJson(Map<String, dynamic> json) {
    return AccountRequestReasonOption(
      key: nonEmptyModelText(json['key'], ''),
      label: nonEmptyModelText(json['label'], 'Other'),
    );
  }
}
