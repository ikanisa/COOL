#!/usr/bin/env node
import { createInterface } from 'node:readline/promises';
import { configuration, SafeError } from './config.mjs';
import { requestJson } from './api.mjs';
import { normalizeLoginEmail, verifyAndSaveLogin } from './login_session.mjs';
import { runTerminalCommand, secretPrompt } from './operator_terminal.mjs';
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
  return verifyAndSaveLogin(config, reply, email, 'The Admin session could not be verified. No local credential was saved.');
}
export { secretPrompt } from './operator_terminal.mjs';

async function main() {
  if (!process.stdin.isTTY || !process.stderr.isTTY || process.argv.length !== 2) {
    throw new SafeError('interactive_login_required', 'Run the login command directly in a terminal. Passwords and email codes in arguments, environment variables, pipes or MCP calls are not accepted.');
  }
  const config = configuration();
  process.stderr.write(`Sign in to ${config.origin} with an existing Admin or Staff account.\nThis creates an independent local session for the read-only MCP adapter; browser cookies are not imported.\n`);
  const prompt = createInterface({ input: process.stdin, output: process.stderr });
  let method, email;
  try {
    method = (await prompt.question('Sign-in method [email code/password] (email code): ')).trim().toLowerCase();
    if (!['', 'email code', 'email', 'password'].includes(method)) {
      throw new SafeError('invalid_login', 'Choose email code or an existing-account password.');
    }
    email = normalizeLoginEmail((await prompt.question('Admin email: ')).trim());
  } finally {
    prompt.close();
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
runTerminalCommand(import.meta.url, main, 'Local sign-in failed. No credentials were printed.');
