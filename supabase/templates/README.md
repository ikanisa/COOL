# Collect Supabase Auth email templates

These are the native Supabase Auth emails for the coordinated Supabase migration.
They are prepared locally. Their presence does not establish applied provider
settings, delivery, account activation or deployment acceptance.

The preview `SiteURL`, `https://platform-admin.collect.ikanisa.com`, is
**provisional**. Keep these templates and their configuration payload local until
the migration/release owners qualify the retained Cloudflare frontend and its
same-origin Supabase transport. Before provider application or any email send, the Auth
owner must reconcile hosted `site_url`, invitation/recovery destinations and the
application callback with that handoff. The HTML uses `{{ .SiteURL }}`; its value
must come from the final hosted configuration. If routes change, update the
templates and affected checks too. Current previews validate the provisional
fixture only and do not qualify any final hosting address.

| Template | Subject | Account flow |
| --- | --- | --- |
| `invite.html` | Your invitation to Collect | “Open Collect” opens `{{ .SiteURL }}/#/admin/login`. The approved recipient requests a fresh email code. The invitation does not establish a session or require password setup. |
| `magic_link.html` | Your Collect sign-in code | Displays `{{ .Token }}` for code entry. This file intentionally implements the selected OTP flow; it contains no session link. |
| `confirmation.html` | Your Collect sign-in code | Displays `{{ .Token }}` for a new or unconfirmed email identity. The recipient enters the code in Collect to confirm their email and continue; it contains no session link. |
| `recovery.html` | Reset your Collect password | Optional password recovery opens `{{ .SiteURL }}/#/admin/setup?token={{ .TokenHash }}&invite=false`. The Admin server performs the managed token exchange. |

The intended owner and sender are `info@ikanisa.com`; the product name is
**Collect**. The configuration owner must verify the actual sender and SMTP or
Send Email Hook route. The selected code contract is six digits with a
300-second lifetime; text in these templates is not proof of hosted Auth settings.

## Build and check

From the repository root:

```sh
python3 supabase/templates/build_templates.py
python3 supabase/templates/validate_templates.py
```

The builder deterministically writes the four HTML files and
`auth-template-config.json`. That JSON contains exactly four
`mailer_subjects_*` fields and four `mailer_templates_*_content` fields for a
partial Auth Management API update. It contains no SMTP credentials or provider
secrets. The Auth owner merges this payload with the reviewed settings in
`supabase/auth-settings.json`, retains the prior remote values and reads back the
applied result. Do not apply settings from this README independently of that
owner's deployment handoff.

The confirmation subject/content fields are `mailer_subjects_confirmation` and
`mailer_templates_confirmation_content`. They cover the first email-code request
when managed Auth uses its signup/confirmation mailer for an absent or unconfirmed
identity. The confirmation and magic-link templates both display the managed OTP;
neither opens a verification URL or transfers session custody through a link.
Preparing these templates does not enable member registration or grant Admin
access. Managed signup settings and application admission remain with the backend
and Auth owners.

For new Free-plan projects, Supabase's default SMTP does not allow template
customization. Configure the reviewed custom SMTP before applying these fields;
no plan upgrade is required for custom SMTP template customization. See the
[3 June 2026 provider change](https://supabase.com/changelog/46599-changes-to-email-template-customisation-on-free-tier).

The validator verifies the payload/file correspondence, allowed template variables,
button labels, URL contracts, sender/footer and absence of browser session-token
links. It writes escaped, synthetic previews and a timestamped receipt under
`docs/implementation/supabase-uat/previews/`. The leading-zero preview code
`012345` and repeated synthetic hash are fixtures. This uses strict substitution
and Python's HTML parser; it does **not** execute Go templates or prove rendering
in Gmail, Outlook or another email client. Runtime or email-client differences
remain observable UAT results, not presumed passes.

## Visual implementation and evidence

The implementation applies the maintained **Revolut Design from Jean Bosco
Skills** utility patterns to Collect's identity: quiet neutral surfaces, clear
hierarchy, readable text and a single rounded primary action. It includes inline
email styles, table layout, responsive spacing and dark-mode media rules, without
external images, web fonts, scripts or visible long recovery URLs.

The independent browser review and U01–U12 hosted scenarios are in
`docs/implementation/supabase-uat/`. Browser rendering of a synthetic HTML preview
is separate from email-client rendering and actual delivery. Dark-mode rules are
implemented; untested color-scheme or zoom behavior must remain unverified.

## Native provider references

- [Supabase email template variables and custom token links](https://supabase.com/docs/guides/auth/auth-email-templates)
- [Auth Management API configuration fields](https://supabase.com/docs/reference/api/v1-update-auth-service-config)
- [SMTP and production email delivery](https://supabase.com/docs/guides/auth/auth-smtp)
- [Local email template configuration](https://supabase.com/docs/guides/local-development/customizing-email-templates)

Local `supabase/config.toml` settings are not hosted configuration readback. The
template lane owns no provider settings, account grants, schema changes or sends.
