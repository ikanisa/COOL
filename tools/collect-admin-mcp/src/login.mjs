#!/usr/bin/env node
import { createInterface } from 'node:readline/promises';
import { pathToFileURL } from 'node:url';
import { resolve } from 'node:path';
import { configuration, SafeError, saveCredential } from './config.mjs';
import { parseSession, requestJson } from './api.mjs';
import { captchaFields, requestEmailCode, verifyEmailCode } from './login_otp.mjs';
import { acquireHumanChallenge } from './human_challenge.mjs';

/** Separate human-only setup; never registered as an MCP tool. */
export async function loginWithCredentials(config, email, password, options = {}) {
  if (typeof email !== 'string' || email.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) ||
      typeof password !== 'string' || password.length < 1 || password.length > 512) {
    throw new SafeError('invalid_login', 'Enter the existing Admin account email and password.');
  }
  const captcha = captchaFields(options);
  // A login is a single attempt. An uncertain response is never retried.
  const reply = await requestJson(config, '/api/admin/auth/login', { method: 'POST', body: { email, password, ...captcha } });
  const cookies = reply.headers.getSetCookie?.() ?? [];
  const matches = cookies.filter(cookie => /^__Host-collect_admin=[a-f0-9]{64};/.test(cookie));
  if (matches.length !== 1 || !/(?:^|;)\s*Secure(?:;|$)/i.test(matches[0]) ||
      !/(?:^|;)\s*HttpOnly(?:;|$)/i.test(matches[0]) || !/(?:^|;)\s*SameSite=Strict(?:;|$)/i.test(matches[0]) ||
      !/(?:^|;)\s*Path=\/(?:;|$)/i.test(matches[0]) || /(?:^|;)\s*Domain=/i.test(matches[0])) {
    throw new SafeError('invalid_login_response', 'The Admin session could not be verified. No local credential was saved.');
  }
  const cookie = matches[0].split(';')[0];
  const initial = parseSession(reply.value);
  const verified = parseSession((await requestJson(config, '/api/admin/auth/session', { cookie })).value);
  if (JSON.stringify(initial) !== JSON.stringify(verified)) throw new SafeError('session_changed', 'The Admin account changed during sign-in. No local credential was saved.');
  await saveCredential(config, { version: 1, origin: config.origin, cookie, accountId: verified.id,
    principalId: verified.principalId, sessionId: verified.sessionId, expiresAt: verified.expiresAt });
  return { role: verified.role, expiresAt: verified.expiresAt };
}
export async function secretPrompt(label = 'Password (hidden): ', maximum = 512) {
  return new Promise((resolve, reject) => {
    let value = '';
    process.stderr.write(label); process.stdin.setRawMode(true); process.stdin.resume();
    function done(error) {
      process.stdin.off('data', onData); process.stdin.setRawMode(false); process.stdin.pause(); process.stderr.write('\n');
      if (error) reject(error); else resolve(value);
    }
    function onData(data) {
      for (const char of data.toString('utf8')) {
        if (char === '\u0003' || char === '\u0004') return done(new SafeError('cancelled', 'Local sign-in cancelled.'));
        if (char === '\r' || char === '\n') return done();
        if (char === '\u007f' || char === '\b') value = Array.from(value).slice(0, -1).join('');
        else if (char >= ' ' && value.length < maximum) value += char;
      }
    }
    process.stdin.on('data', onData);
  });
}
async function main() {
  if (!process.stdin.isTTY || !process.stderr.isTTY || process.argv.length !== 2) {
    throw new SafeError('interactive_login_required', 'Run the login command directly in a terminal. Passwords and email codes in arguments, environment variables, pipes or MCP calls are not accepted.');
  }
  const config = configuration();
  process.stderr.write(`Sign in to ${config.origin} with an existing Admin or Staff account.\nThis creates an independent local session for the read-only MCP adapter; browser cookies are not imported.\n`);
  const prompt = createInterface({ input: process.stdin, output: process.stderr });
  const method = (await prompt.question('Sign-in method [email code/password] (email code): ')).trim().toLowerCase();
  if (!['', 'email code', 'email', 'password'].includes(method)) {
    prompt.close(); throw new SafeError('invalid_login', 'Choose email code or an existing-account password.');
  }
  const email = (await prompt.question('Admin email: ')).trim().toLowerCase(); prompt.close();
  if (email.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    throw new SafeError('invalid_login', 'Enter the approved Admin account email.');
  }
  const challengeFor = operation => acquireHumanChallenge(config, {
    operation,
    onPairing: ({ descriptor, parentUrl }) => {
      process.stderr.write(`Open ${parentUrl} in your normal browser.\nPaste this public pairing descriptor there, then choose Connect:\n${JSON.stringify(descriptor)}\n`);
      process.stderr.write('The page returns only a human-verification token. Browser sessions are not imported.\n');
    },
  });
  let secret = '';
  let captchaToken = '';
  try {
    let result;
    if (method === 'password') {
      secret = await secretPrompt();
      if (!secret) throw new SafeError('invalid_login', 'Enter the existing Admin account password.');
      captchaToken = await challengeFor('admin.password.sign_in');
      result = await loginWithCredentials(config, email, secret, { captchaToken });
      captchaToken = '';
    } else {
      captchaToken = await challengeFor('admin.email_otp.send');
      const challenge = await requestEmailCode(config, email, { captchaToken });
      captchaToken = '';
      process.stderr.write(challenge.delivery === 'unknown'
        ? 'Delivery is unconfirmed. If the original code arrives, enter it; no replacement code was requested.\n'
        : 'The code request was accepted. Enter the code from your approved account email.\n');
      process.stderr.write(`Original sign-in reference: ${challenge.challengeId}\n`);
      process.stderr.write(`This attempt expires at ${challenge.expiresAt}. Do not request another code within ${challenge.retryAfter} seconds.\n`);
      secret = await secretPrompt('Email code (hidden): ');
      // Managed verification's CAPTCHA enforcement is a separate provider
      // contract. Do not reuse the token already spent on sending the code.
      result = await verifyEmailCode(config, challenge, secret);
    }
    process.stderr.write(`Local ${result.role} access saved until ${result.expiresAt}. No MCP write tools are enabled.\n`);
  } finally { secret = ''; captchaToken = ''; }

}
if (process.argv[1] && pathToFileURL(resolve(process.argv[1])).href === import.meta.url) {
  main().catch(error => {
    process.stderr.write(`${error instanceof SafeError ? error.message : 'Local sign-in failed. No credentials were printed.'}\n`);
    process.exitCode = 1;
  });
}
