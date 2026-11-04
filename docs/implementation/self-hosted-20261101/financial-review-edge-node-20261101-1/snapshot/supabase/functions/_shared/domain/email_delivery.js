import {applicationWork,noteUnknownEffect} from '../application-fence.js';
import {ApiError} from './core.js';

// The legacy Admin binding is constrained to the existing Collect sender.
// AUTH_EMAIL is the shared, explicitly configured successor for both apps.
const LEGACY_ADMIN_SENDER = 'info@ikanisa.com';
const unavailable = () => new ApiError(503, 'email_unavailable', 'Email delivery could not be confirmed. Please try again later.');

function configuration(env) {
  // Wrangler's local email simulator prints message content, including OTPs.
  if (env.ENVIRONMENT === 'local' || env.APP_ENVIRONMENT === 'local') throw unavailable();
  const primary = env.AUTH_EMAIL;
  const binding = primary ?? env.EMAIL;
  const from = env.AUTH_EMAIL_FROM ?? (primary ? undefined : LEGACY_ADMIN_SENDER);
  if (typeof binding?.send !== 'function' || typeof from !== 'string' || from.length > 254 ||
      !/^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,63}$/.test(from)) throw unavailable();
  return {binding, from};
}

export function transactionalEmailAvailable(env) {
  try { configuration(env); return true; } catch { return false; }
}

export async function sendTransactionalEmail(env, message) {
  const {binding, from} = configuration(env);
  if (!message || typeof message.to !== 'string' || message.to.length > 254 ||
      !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(message.to) ||
      typeof message.subject !== 'string' || message.subject.length < 1 || message.subject.length > 200 || /[\r\n]/.test(message.subject) ||
      typeof message.text !== 'string' || message.text.length < 1 || message.text.length > 20000 ||
      (message.html !== undefined && (typeof message.html !== 'string' || message.html.length > 100000))) throw unavailable();
  let timeout;
  const work=applicationWork(env);await work.assert();
  try {
    const result = await Promise.race([
      work.waitUntil(binding.send({from: {email: from, name: 'Collect'}, to: message.to, subject: message.subject,
        text: message.text, ...(message.html === undefined ? {} : {html: message.html})})),
      new Promise((_, reject) => { timeout = setTimeout(() => reject(unavailable()), 10000); }),
    ]);
    if (typeof result?.messageId !== 'string' || result.messageId.trim().length < 1 ||
        result.messageId.length > 256 || /[\u0000-\u001f\u007f]/.test(result.messageId)) throw unavailable();
    return {messageId: result.messageId};
  } catch {
    noteUnknownEffect(env,'smtp');
    // Neither provider messages, recipients nor message/code contents enter
    // exception text or logs. The caller retains accepted-vs-unknown state.
    throw unavailable();
  } finally {
    clearTimeout(timeout);
  }
}
