// Generated from content/product/collect_capabilities.json.
// Registry SHA-256: 3e3831fd74a2c31495b18d3e155fc23febd3a98da0928df9563f893ddd97c89e
// Source observations only; no publication or provider approval.
part of 'public_content.dart';

const collectPublicCapabilityRegistrySha256 =
    '3e3831fd74a2c31495b18d3e155fc23febd3a98da0928df9563f893ddd97c89e';
const collectPublicHomeCopy = <String, String>{
  'title': 'Rwanda MoMo contributions, clearly recorded.',
  'intro':
      'Sign in to create a private group and invite members. Rwanda MoMo payments and consented receipt SMS have separate eligibility checks; USSD and SMS capture require Android.',
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
        'Any signed-in Collect user can create a private group and invite members without registering a MoMo number, provider or recipient. Group setup does not request SMS access or authorize payments.',
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
  'momo_ussd': CollectPublicCapabilityData(
    label: 'MoMo USSD handoff',
    summary:
        'Eligible Android members check the exact MTN MoMo or Airtel Money receiver and whole-RWF amount, then approve payment in the mobile network’s USSD prompt. Check the Android release currently available on Google Play before relying on this feature.',
    region: 'RW',
    ownerApproved: false,
    availability: {
      'android': 'supported',
      'ios': 'unavailable',
      'web': 'unavailable',
      'basic_phone': 'unavailable',
    },
    actionLabel: 'View Android release',
    actionHref: 'https://play.google.com/store/apps/details?id=app.cool.mobile',
    fallbackLabel: 'Ask about Collect',
    fallbackHref: 'mailto:info@ikanisa.com',
  ),
  'receipt_sms': CollectPublicCapabilityData(
    label: 'Consented receipt SMS',
    summary:
        'Signed-in Android users can opt in to submit newly arriving MoMo SMS as candidate evidence. Consent can be withdrawn; SMS history and Call Logs are not read.',
    region: 'RW',
    ownerApproved: false,
    availability: {
      'android': 'supported',
      'ios': 'unavailable',
      'web': 'unavailable',
      'basic_phone': 'unavailable',
    },
    actionLabel: 'View Android release',
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
