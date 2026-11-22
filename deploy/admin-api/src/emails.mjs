// Collect transactional email adapter. Tables and inline styles keep the primary
// action usable in Gmail, Apple Mail and Outlook without images or web fonts.
const escapeHtml = value => String(value).replace(/[&<>"']/g, char => ({
  '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
})[char]);

function document({ title, preheader, eyebrow, content, action, note }) {
  return `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="color-scheme" content="light dark"><meta name="supported-color-schemes" content="light dark"><title>${escapeHtml(title)}</title>
<style>
@media only screen and (max-width:620px){.collect-card{padding:32px 24px!important}.collect-title{font-size:30px!important;line-height:36px!important}.collect-shell{padding:24px 12px!important}}
@media(prefers-color-scheme:dark){.collect-bg{background-color:#111317!important}.collect-surface{background-color:#1c1f24!important}.collect-ink{color:#f5f6f7!important}.collect-muted{color:#b5bac3!important}.collect-rule{border-color:#383d46!important}.collect-button{background-color:#f5f6f7!important;color:#111317!important}}
</style></head>
<body class="collect-bg" style="margin:0;padding:0;background-color:#f4f5f7;color:#111317;font-family:Arial,Helvetica,sans-serif;-webkit-text-size-adjust:100%">
<div style="display:none;font-size:1px;line-height:1px;max-height:0;max-width:0;opacity:0;overflow:hidden;mso-hide:all">${escapeHtml(preheader)}</div>
<table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0"><tr><td class="collect-shell" align="center" style="padding:48px 20px">
<table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="max-width:600px"><tr><td class="collect-surface collect-card" style="padding:44px;background-color:#ffffff;border-radius:24px">
<p class="collect-ink" style="margin:0 0 48px;font-size:28px;line-height:32px;letter-spacing:-1px;font-weight:700;color:#111317">Collect<span style="color:#68707d;font-weight:400">.</span></p>
<p class="collect-muted" style="margin:0 0 16px;font-size:12px;line-height:18px;letter-spacing:1.5px;color:#596170;text-transform:uppercase">${escapeHtml(eyebrow)}</p>
<h1 class="collect-ink collect-title" style="margin:0 0 20px;font-size:36px;line-height:42px;letter-spacing:-1.1px;font-weight:700;color:#111317">${escapeHtml(title)}</h1>
${content}
${action ? `<table role="presentation" cellspacing="0" cellpadding="0" border="0" style="margin:32px 0"><tr><td class="collect-button" align="center" bgcolor="#111317" style="background-color:#111317;border-radius:100px;mso-padding-alt:16px 28px"><a class="collect-button" href="${escapeHtml(action.href)}" style="display:inline-block;padding:16px 28px;background-color:#111317;color:#ffffff;border-radius:100px;font-size:16px;line-height:20px;font-weight:700;text-decoration:none;text-align:center">${escapeHtml(action.label)}</a></td></tr></table>` : ''}
${note ? `<p class="collect-muted" style="margin:24px 0 0;font-size:14px;line-height:22px;color:#596170">${escapeHtml(note)}</p>` : ''}
<table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="margin-top:40px"><tr><td class="collect-rule" style="border-top:1px solid #e6e8ed;padding-top:24px"><p class="collect-muted" style="margin:0;font-size:13px;line-height:20px;color:#596170">Sent by Collect<br><a class="collect-muted" href="mailto:info@ikanisa.com" style="color:#596170;text-decoration:none">info@ikanisa.com</a></p></td></tr></table>
</td></tr></table>
</td></tr></table></body></html>`;
}

const paragraph = text => `<p class="collect-ink" style="margin:0 0 16px;font-size:16px;line-height:26px;color:#303641">${escapeHtml(text)}</p>`;

export function buildAccountEmail({ kind, link }) {
  if (!['invite', 'reset'].includes(kind)) throw new TypeError('Unsupported account email.');
  const url = new URL(link);
  const query = new URLSearchParams(url.hash.split('?')[1]);
  if (url.protocol !== 'https:' || url.username || url.password ||
      !(url.hostname === 'collect.ikanisa.com' || url.hostname.endsWith('.collect.ikanisa.com')) ||
      url.pathname !== '/' || !url.hash.startsWith('#/admin/setup?') ||
      !/^[a-f0-9]{64}$/.test(query.get('token') || '') ||
      query.get('invite') !== String(kind === 'invite')) throw new TypeError('Invalid account action link.');
  const invite = kind === 'invite';
  const subject = invite ? 'Your invitation to Collect' : 'Reset your Collect password';
  const introduction = invite ? 'You have been invited to Collect.' : 'A password reset was requested for your Collect account.';
  const detail = invite ? 'Set your password to activate your account and get started.' : 'Choose a new password to regain access to your account.';
  const expiry = `This single-use link expires in ${invite ? '24 hours' : '30 minutes'}.`;
  const safety = invite ? 'If you weren’t expecting this invitation, you can safely ignore this email.' : 'If you didn’t request a password reset, you can safely ignore this email. Your password will stay the same.';
  return {
    subject,
    text: `${introduction}\n\n${detail}\n\n${invite ? 'Set your password' : 'Reset your password'}: ${link}\n\n${expiry}\n${safety}\n\nCollect\ninfo@ikanisa.com`,
    html: document({ title: invite ? 'Welcome to Collect' : 'Reset your password', preheader: `${introduction} ${expiry}`, eyebrow: invite ? 'Your invitation' : 'Account security',
      content: paragraph(introduction) + paragraph(detail), action: { href: link, label: invite ? 'Set your password' : 'Reset your password' }, note: `${expiry} ${safety}` }),
  };
}

export function buildTransactionalEmail({ subject, text }) {
  if (typeof subject !== 'string' || !subject.trim() || subject.length > 200 || /[\r\n]/.test(subject) ||
      typeof text !== 'string' || !text.trim() || text.length > 16000) throw new TypeError('Invalid transactional email.');
  // The login code is emphasized only for the exact authentication template.
  // Never turn arbitrary receipt amounts or customer text into an action/code.
  const code = subject === 'Your Collect sign-in code' ? text.match(/\b(\d{6})\b/)?.[1] : null;
  const paragraphs = text.split(/\n\s*\n/).map(value => paragraph(value)).join('');
  return { text, html: document({ title: subject.replace(/^Your Collect /, 'Your ').replace(/^Collect: /, ''), preheader: text.slice(0, 150), eyebrow: code ? 'Account security' : 'Your account',
    content: code ? `<p class="collect-ink" style="margin:0 0 16px;font-size:16px;line-height:26px;color:#303641">Use this code to sign in to Collect:</p><p class="collect-ink" style="margin:24px 0;font-size:36px;line-height:44px;letter-spacing:8px;font-weight:700;color:#111317">${code}</p>${paragraphs}` : paragraphs,
    note: code ? 'Never share your sign-in code. Collect will never ask you to send it to anyone.' : null }) };
}
