import {createTransport} from 'npm:nodemailer@10.1.7';
import {guardedFetch} from './application-fence.js';
import {ApiError} from './domain/core.js';
import {registerBuiltinEmailBinding} from './email-binding-registry.js';
import {createWorkspaceSmtpEmail, WORKSPACE_SMTP_SENDER} from './workspace-smtp-email.js';

const unavailable = () => new ApiError(503, 'email_unavailable', 'The configured service is unavailable.');

function transactionalHttpEmail(env) {
  return registerBuiltinEmailBinding({async send(message, reservation) {
    const target = new URL(env.TRANSACTIONAL_EMAIL_URL);
    if (target.protocol !== 'https:' || target.username || target.password) throw unavailable();
    const reply = await guardedFetch(env, 'smtp', target, {
      method: 'POST',
      headers: {'Content-Type': 'application/json', Authorization: `Bearer ${env.TRANSACTIONAL_EMAIL_TOKEN}`},
      body: JSON.stringify(message),
      redirect: 'error',
      signal: AbortSignal.timeout(10_000),
    }, reservation);
    if (!reply.ok) throw unavailable();
    const data = await reply.json();
    return {messageId: data.messageId ?? data.id};
  }});
}

export function emailAdapters(env) {
  const password = env.COLLECT_NOTICE_SMTP_PASSWORD;
  if (password !== undefined && password !== null && password !== '') {
    try {
      return {AUTH_EMAIL: createWorkspaceSmtpEmail(env, {createTransport}), AUTH_EMAIL_FROM: WORKSPACE_SMTP_SENDER};
    } catch {
      return {AUTH_EMAIL: Object.freeze({provider: 'workspace_smtp_v1', unavailable: true})};
    }
  }
  if (env.TRANSACTIONAL_EMAIL_URL && env.TRANSACTIONAL_EMAIL_TOKEN) {
    return {AUTH_EMAIL: transactionalHttpEmail(env)};
  }
  return {};
}
