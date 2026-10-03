// Generated from content/product/collect_capabilities.json.
// Registry SHA-256: a6c4c0c824ccc5c69874520b1722a66d92d21bccc45022c6f89c4a126eda9599
// Source observations only; no publication or provider approval.
part of 'public_content.dart';

const collectPublicCapabilityRegistrySha256 =
    'a6c4c0c824ccc5c69874520b1722a66d92d21bccc45022c6f89c4a126eda9599';
const collectPublicHomeCopy = <String, String>{
  'title': 'Rwanda MoMo contributions, clearly recorded.',
  'intro':
      'Rwanda groups record whole-RWF MoMo contributions. Group creation, the app’s USSD handoff and receipt SMS require eligible Android devices.',
  'request_body':
      'Create a whole-RWF request for the approved Rwanda MoMo receiver.',
  'approve_body':
      'Eligible Android members approve payment in the provider’s USSD prompt.',
  'posting_body':
      'Pending receipt evidence requires governed reconciliation before confirmation.',
};

const collectPublicCapabilities = <String, CollectPublicCapabilityData>{
  'group_records': CollectPublicCapabilityData(
    label: 'Group records',
    summary:
        'Collect helps Rwanda groups organize members and review whole-RWF MoMo contribution records. It is a technology and record-keeping service.',
    region: 'RW',
    ownerApproved: false,
    availability: {
      'android': 'supported',
      'ios': 'supported',
      'web': 'supported',
      'basic_phone': 'unavailable',
    },
    actionLabel: 'Get the App',
    actionHref: 'https://play.google.com/store/apps/details?id=app.cool.mobile',
    fallbackLabel: 'Ask about Collect',
    fallbackHref: 'mailto:info@ikanisa.com',
  ),
  'private_group_creation': CollectPublicCapabilityData(
    label: 'Private-group creation',
    summary:
        'Private-group creation is available only on eligible Android builds, after SMS consent and device verification. iOS and web do not create private groups.',
    region: 'RW',
    ownerApproved: false,
    availability: {
      'android': 'supported',
      'ios': 'unavailable',
      'web': 'unavailable',
      'basic_phone': 'unavailable',
    },
    actionLabel: 'Create a group on Android',
    actionHref: 'https://play.google.com/store/apps/details?id=app.cool.mobile',
    fallbackLabel: 'Ask about Collect',
    fallbackHref: 'mailto:info@ikanisa.com',
  ),
  'momo_ussd': CollectPublicCapabilityData(
    label: 'MoMo USSD handoff',
    summary:
        'Eligible Android members check the exact MTN MoMo or Airtel Money receiver and whole-RWF amount, then approve payment in the mobile network’s USSD prompt.',
    region: 'RW',
    ownerApproved: false,
    availability: {
      'android': 'supported',
      'ios': 'unavailable',
      'web': 'unavailable',
      'basic_phone': 'unavailable',
    },
    actionLabel: 'Use the Android app',
    actionHref: 'https://play.google.com/store/apps/details?id=app.cool.mobile',
    fallbackLabel: 'Ask about Collect',
    fallbackHref: 'mailto:info@ikanisa.com',
  ),
  'receipt_sms': CollectPublicCapabilityData(
    label: 'Consented receipt SMS',
    summary:
        'Eligible Android receiver devices may submit newly arriving MoMo receipt SMS as candidate evidence. Consent can be withdrawn; SMS history and Call Logs are not read.',
    region: 'RW',
    ownerApproved: false,
    availability: {
      'android': 'supported',
      'ios': 'unavailable',
      'web': 'unavailable',
      'basic_phone': 'unavailable',
    },
    actionLabel: 'Read about Android receipt consent',
    actionHref: 'https://play.google.com/store/apps/details?id=app.cool.mobile',
    fallbackLabel: 'Ask about Collect',
    fallbackHref: 'mailto:info@ikanisa.com',
  ),
  'support': CollectPublicCapabilityData(
    label: 'Support and deletion requests',
    summary:
        'For a Collect question, email info@ikanisa.com. In the app, use Settings → Security → Delete data to request eligible data deletion.',
    region: 'RW',
    ownerApproved: false,
    availability: {
      'android': 'assisted',
      'ios': 'assisted',
      'web': 'assisted',
      'basic_phone': 'unavailable',
    },
    actionLabel: 'Email Collect support',
    actionHref: 'mailto:info@ikanisa.com',
    fallbackLabel: 'Ask about Collect',
    fallbackHref: 'mailto:info@ikanisa.com',
  ),
  'basic_phone': CollectPublicCapabilityData(
    label: 'Basic-phone access',
    summary:
        'A standalone basic-phone Collect journey is planned and is not currently available. The app’s Android USSD handoff is not a basic-phone Collect service.',
    region: 'RW',
    ownerApproved: false,
    availability: {
      'android': 'planned',
      'ios': 'planned',
      'web': 'planned',
      'basic_phone': 'planned',
    },
    actionLabel: 'Ask about basic-phone plans',
    actionHref: 'mailto:info@ikanisa.com',
    fallbackLabel: 'Ask about basic-phone plans',
    fallbackHref: 'mailto:info@ikanisa.com',
  ),
  'credit_readiness': CollectPublicCapabilityData(
    label: 'Credit readiness',
    summary:
        'Credit Readiness-as-a-Service is a planned service direction. No active Collect intake or coordinated preparation service is offered here. Contact IKANISA to ask about the plans.',
    region: 'RW',
    ownerApproved: false,
    availability: {
      'android': 'planned',
      'ios': 'planned',
      'web': 'planned',
      'basic_phone': 'planned',
    },
    actionLabel: 'Ask about credit-readiness plans',
    actionHref: 'mailto:info@ikanisa.com',
    fallbackLabel: 'Ask about credit-readiness plans',
    fallbackHref: 'mailto:info@ikanisa.com',
  ),
  'loans': CollectPublicCapabilityData(
    label: 'Bank and credit directions',
    summary:
        'Loans, bank deposits, collateral arrangements and loan repayments are provider-dependent directions, not services available through the current Collect app. No lender arrangement, eligibility or approval is promised.',
    region: 'RW',
    ownerApproved: false,
    availability: {
      'android': 'provider_dependent',
      'ios': 'provider_dependent',
      'web': 'provider_dependent',
      'basic_phone': 'provider_dependent',
    },
    actionLabel: 'Ask about provider plans',
    actionHref: 'mailto:info@ikanisa.com',
    fallbackLabel: 'Ask about provider plans',
    fallbackHref: 'mailto:info@ikanisa.com',
  ),
  'insurance': CollectPublicCapabilityData(
    label: 'Insurance direction',
    summary:
        'Insurance and claims support are planned, provider-dependent directions. No insurer, policy enrollment, premium collection, proof of cover or claims journey is available through Collect here.',
    region: 'RW',
    ownerApproved: false,
    availability: {
      'android': 'provider_dependent',
      'ios': 'provider_dependent',
      'web': 'provider_dependent',
      'basic_phone': 'provider_dependent',
    },
    actionLabel: 'Ask about insurance plans',
    actionHref: 'mailto:info@ikanisa.com',
    fallbackLabel: 'Ask about insurance plans',
    fallbackHref: 'mailto:info@ikanisa.com',
  ),
};
