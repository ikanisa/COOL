# Supabase functions and runtime

The current source groups its business and Admin operations under `supabase/functions/collect-api/` and `supabase/functions/admin-api/`, with shared handlers in `supabase/functions/_shared/`. The repository also contains `collect-jobs`, `collect-email-jobs`, `collect-sms`, and `send-sms-hook` entry points. Their presence in source does not establish that any function is deployed or authorized for production. Use the current deployment profile and its documented checks before deploying or enabling a job.

Older standalone names such as `parse-payment-sms`, `dispatch-notifications`, and `auth-send-whatsapp-otp` describe historical source; they are not an inventory of the current entry points. Current receipt capture retains evidence and queues processing under guarded runtime controls. The shared scheduled receipt processor is disabled pending separate qualification, and the MoMo model is unconfigured by default. Receipt acknowledgement does not itself establish payment finality.

Current notification delivery admission and sender code target Android FCM. Registration of an APNs token does not establish iOS push delivery. The signed OpenSMS hook is SMS-only; the self-hosted phone proxy also supports separately configured native Twilio modes. Historical direct-Meta WhatsApp delivery is not the current signed-hook implementation. Device, provider and hosted delivery require their own evidence.

## Financial and privacy boundaries

MoMo authorization occurs in the mobile-network USSD prompt. An incomplete or ambiguous receipt is not proof of payment; posting and reconciliation require the current authorization, evidence and transaction controls. Member SMS capture and the internal receiver have different custody and completeness contracts. In particular, internal receiver handling of incomplete or sensitive source messages remains an open privacy review item.

The retired bearer `GET /v1/receipts/{id}` route returns 410. The separate Admin capture-content workflow is designed to require scoped authority, a reason and an audit record; local source and fixture tests do not establish its deployed behavior. Service-role, messaging and push credentials remain server-side and must not be included in Flutter configuration or source control.
