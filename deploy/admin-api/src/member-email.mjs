import { buildTransactionalEmail } from './emails.mjs';
// Cloudflare Email Service only. No development delivery simulator or test code.
export async function sendMemberEmail(env, { to, subject, text }) {
  if (env.ENVIRONMENT === 'local' || !env.EMAIL?.send) throw new Error('email_unavailable');
  const result = await env.EMAIL.send({ from: { email: 'info@ikanisa.com', name: 'Collect' }, to, subject, ...buildTransactionalEmail({subject,text}) });
  if (!result || typeof result.messageId !== 'string' || !result.messageId) throw new Error('email_unavailable');
  return result.messageId.slice(0, 256);
}
