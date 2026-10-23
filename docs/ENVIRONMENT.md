# Environment

Collect uses the independent Cloudflare Workers, D1 and private R2 backend.

## SDK and execution

The selected mobile toolchain is Flutter `3.44.4` with its bundled Dart `3.12.2`; `.fvmrc` pins Flutter. Use a qualified installation of those versions; generated `android/local.properties` and Apple build settings must point to that installation. The native checks record the actual SDK, dependency and artifact hashes. A configured path alone does not establish a working Apple toolchain.

## Public Flutter configuration

`.env.example` contains public client settings only:

- `COLLECT_API_URL=https://api.collect.ikanisa.com`
- `APP_PUBLIC_URL=https://collect.ikanisa.com`
- `ADMIN_APP_URL=https://platform-admin.collect.ikanisa.com`
- `APP_ENVIRONMENT`, `ENABLE_ADMIN_PANEL`, `ENABLE_ADMIN_DEV_TOOLS`
- `ENABLE_SMS_READER`, `ENABLE_ANDROID_SMS_ACCESS`
- `AUTH_CAPTCHA_ENABLED`, `AUTH_CAPTCHA_PROVIDER=turnstile`
- `AUTH_CAPTCHA_SITE_KEY` is public. The fresh challenge page obtains its configured site key from the backend.
- `PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER` is the public Google Cloud project number linked to Collect in Play Console. Do not assume it equals a Firebase project number.
- `APNS_ENVIRONMENT` selects the client notification environment; it does not configure or authorize push delivery.

No service credential or encryption key belongs in Flutter defines, web assets or a committed environment file. The separate blank App Store Connect identifiers/path in the example are local automation inputs; the actual signing material remains outside the checkout.

## Cloudflare service configuration

`deploy/platform-api/wrangler.jsonc` names `collect-platform-api`, D1 `collect-platform` and private R2 `collect-platform-private`. Its reviewed public variables bind origins, issuer/audience, environment and build identity. The current Admin is `collect-platform-admin` at `https://platform-admin.collect.ikanisa.com`; its service binding preserves the original Admin origin and HttpOnly cookie. It does not initialize a member bearer client.

The server-only core secrets are `AUTH_JWT_SECRET`, `AUTH_TOKEN_HASH_SECRET` and `DATA_ENCRYPTION_KEY`. `DATA_KEY_ID` identifies the encryption key without publishing it. Create and rotate actual values through the approved secret/key custody process; never paste them into reports or browser recovery storage.

Real member authentication additionally needs `TURNSTILE_SECRET`, the public `TURNSTILE_SITE_KEY`, the expected `TURNSTILE_HOSTNAME`/action and an authenticated OTP relay through `OTP_DELIVERY_URL` and `OTP_DELIVERY_TOKEN`. The selected delivery provider/business account is still required. An unconfigured relay or CAPTCHA refuses sign-in; test acknowledgements are not delivery evidence. Owner authenticator enrollment must be completed by the owner.

Native server admission uses `PLAY_INTEGRITY_SERVICE_ACCOUNT_JSON`, `PLAY_INTEGRITY_POLICY_JSON` and its exact `PLAY_INTEGRITY_POLICY_SHA256`, as enforced by `src/native_integrity.js`. The approved policy, actual Google project, quotas, budget and outage/alert handling must be established before enabling native privileges.

AI roster extraction additionally requires the approved `ROSTER_AI_APPROVAL_JSON`/`ROSTER_AI_APPROVAL_SHA256`, the selected OpenAI project/organization/model, API secret and the `ROSTER_DECODER` binding with its approved build identity. No processor, region, retention, spending or accuracy approval is supplied by a local fixture.

`FCM_SERVICE_ACCOUNT_JSON` and `APNS_PRIVATE_KEY_BASE64` are server-only provider inputs from the retained notification design. The fresh backend records preferences/devices/events; automatic push delivery and its actual provider configuration remain incomplete. Adding those names to a client file would neither enable delivery nor satisfy its acceptance.

See [the current platform API](../deploy/platform-api/README.md) and [authenticated recovery](../scripts/cloudflare/README.md) for the maintained runtime and recovery paths.

## Native build channels

The current unsigned local QA build uses Cloudflare endpoints, true CAPTCHA and both SMS switches disabled. It is not a store artifact or proof of real integrity/provider admission.

Android production builds set both SMS switches to `true` only through the guarded production wrapper, which requires the linked Play project. Receipt access still requires an authenticated eligible Rwanda member, explicit consent, valid server policy and actual Play admission. The public production permission contract has no `READ_SMS`, `SEND_SMS`, or Call Log permission; `RECEIVE_SMS` and `CALL_PHONE` remain subject to the actual declaration/device/release checks. The internal receiver channel is distinct from the public member build.

MoMo instructions open a pre-filled MTN request or Airtel merchant menu through USSD. Users enter a PIN only in the provider interface. Recorded evidence, reconciliation or an internal ledger entry does not establish provider settlement. Apple signing, provisioning and store publication require the separately verified Apple toolchain and approved signing path.
