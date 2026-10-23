"""Build the four Collect emails consumed by hosted Supabase Auth."""
from pathlib import Path
import html
import json

ROOT = Path(__file__).resolve().parent


def paragraph(value):
    return '<p class="ink" style="margin:0 0 16px;font-size:16px;line-height:26px;color:#191c1f">' + html.escape(value) + '</p>'


def document(title, preheader, eyebrow, content, note, action=None):
    button = ''
    if action:
        href, label = action
        button = f'''<table role="presentation" cellspacing="0" cellpadding="0" border="0" style="margin:28px 0 0"><tr><td class="button" align="center" bgcolor="#191c1f" style="background:#191c1f;border-radius:9999px;mso-padding-alt:16px 28px"><a class="button" href="{href}" style="display:inline-block;padding:16px 28px;border-radius:9999px;background:#191c1f;color:#ffffff;font-size:16px;line-height:20px;font-weight:700;text-decoration:none;text-align:center">{html.escape(label)}</a></td></tr></table>'''
    return f'''<!doctype html>
<html lang="en">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="color-scheme" content="light dark"><meta name="supported-color-schemes" content="light dark"><title>{html.escape(title)}</title>
<style>
@media only screen and (max-width:600px){{.shell{{padding:24px 12px!important}}.card{{padding:32px 24px!important}}.heading{{font-size:28px!important;line-height:34px!important}}.code{{font-size:28px!important;letter-spacing:3px!important}}}}
@media(prefers-color-scheme:dark){{.background{{background:#000000!important}}.surface{{background:#161618!important}}.ink{{color:#f4f4f4!important}}.muted{{color:#a1a1a3!important}}.button{{background:#f4f4f4!important;color:#191c1f!important}}.code-surface{{background:#000000!important}}}}
</style></head>
<body class="background" style="margin:0;padding:0;background:#f7f7f7;color:#191c1f;font-family:Inter,Arial,Helvetica,sans-serif;-webkit-text-size-adjust:100%">
<div style="display:none;font-size:1px;line-height:1px;max-height:0;max-width:0;opacity:0;overflow:hidden;mso-hide:all">{html.escape(preheader)}</div>
<table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0"><tr><td class="shell" align="center" style="padding:48px 20px">
<table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="max-width:560px"><tr><td class="surface card" style="padding:40px;background:#ffffff;border-radius:24px">
<p class="ink" style="margin:0 0 40px;font-size:28px;line-height:34px;letter-spacing:-1px;font-weight:700;color:#191c1f">Collect</p>
<p class="muted" style="margin:0 0 12px;font-size:12px;line-height:18px;letter-spacing:1px;font-weight:500;color:#717173;text-transform:uppercase">{html.escape(eyebrow)}</p>
<h1 class="ink heading" style="margin:0 0 20px;font-size:32px;line-height:38px;letter-spacing:-0.7px;font-weight:700;color:#191c1f">{html.escape(title)}</h1>
{content}{button}
<p class="muted" style="margin:28px 0 0;font-size:14px;line-height:22px;color:#717173">{html.escape(note)}</p>
<p class="muted" style="margin:40px 0 0;font-size:13px;line-height:20px;color:#717173">Collect<br><a class="muted" href="mailto:info@ikanisa.com" style="color:#717173;text-decoration:underline">info@ikanisa.com</a></p>
</td></tr></table></td></tr></table>
</body></html>
'''


def build():
    profiles = {
        'invite': {
            'subject': 'Your invitation to Collect',
            'html': document('Join Collect', 'You have been invited to Collect.', 'Your invitation',
                paragraph('You have been invited to Collect.') + paragraph('Open Collect and sign in with the email address that received this invitation. We will send you a one-time code.'),
                'This invitation does not sign you in. If you were not expecting it, contact your super admin.',
                ('{{ .SiteURL }}/#/admin/login', 'Open Collect')),
        },
        'magic_link': {
            'subject': 'Your Collect sign-in code',
            'html': document('Your sign-in code', 'Your one-time sign-in code expires in 5 minutes.', 'Account security',
                paragraph('Enter this code in Collect to continue.') + '<table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="margin:24px 0"><tr><td class="code-surface" align="center" style="padding:20px 12px;background:#f7f7f7;border-radius:16px"><p class="ink code" style="margin:0;font-size:32px;line-height:40px;font-weight:700;letter-spacing:4px;font-variant-numeric:tabular-nums;color:#191c1f">{{ .Token }}</p></td></tr></table>' + paragraph('This code expires in 5 minutes and can be used once.'),
                'Never share your code. If you did not request it, you can ignore this email.'),
        },
        'confirmation': {
            'subject': 'Your Collect sign-in code',
            'html': document('Your sign-in code', 'Confirm your email to continue to Collect. Your code expires in 5 minutes.', 'Account security',
                paragraph('Enter this code in Collect to confirm your email and continue.') + '<table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="margin:24px 0"><tr><td class="code-surface" align="center" style="padding:20px 12px;background:#f7f7f7;border-radius:16px"><p class="ink code" style="margin:0;font-size:32px;line-height:40px;font-weight:700;letter-spacing:4px;font-variant-numeric:tabular-nums;color:#191c1f">{{ .Token }}</p></td></tr></table>' + paragraph('This code expires in 5 minutes and can be used once.'),
                'Never share your code. If you did not request it, you can ignore this email.'),
        },
        'recovery': {
            'subject': 'Reset your Collect password',
            'html': document('Reset your password', 'Choose a new password for your Collect account.', 'Account security',
                paragraph('A password reset was requested for your Collect account.') + paragraph('Use the button below to choose a new password.'),
                'If you did not request this, you can ignore this email. Your password will stay the same.',
                ('{{ .SiteURL }}/#/admin/setup?token={{ .TokenHash }}&amp;invite=false', 'Reset password')),
        },
    }
    payload = {}
    for name, profile in profiles.items():
        (ROOT / (name + '.html')).write_text(profile['html'])
        payload['mailer_subjects_' + name] = profile['subject']
        payload['mailer_templates_' + name + '_content'] = profile['html']
    (ROOT / 'auth-template-config.json').write_text(json.dumps(payload, indent=2) + '\n')
    return profiles


if __name__ == '__main__':
    build()
    print('Built invite, magic_link, confirmation and recovery templates; no provider configuration changed.')
