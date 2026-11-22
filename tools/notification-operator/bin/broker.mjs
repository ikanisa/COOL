import { acquireEmailProof } from '../src/human_login.mjs';
import { AdminHttp } from '../src/http_client.mjs';
import { BrokerServer, readConfig } from '../src/broker.mjs';
import { openOperatorTerminal } from '../src/broker-terminal.mjs';
import { privateDirectory } from '../src/private_state.mjs';

function parseBrokerArguments(args) {
  if (args.length !== 6 || args[0] !== '--config' || args[2] !== '--config-sha256' || args[4] !== '--state-dir') {
    throw new Error('exact_arguments_required');
  }
  if (process.env.NODE_TLS_REJECT_UNAUTHORIZED === '0') throw new Error('normal_tls_verification_required');
  return { configPath: args[1], configSha: args[3], stateDir: args[5] };
}

function sessionPrompts(tty, http, origin, signal) {
  async function requestCode(purpose, email) {
    const proof = await acquireEmailProof({ origin, purpose }, {
      signal,
      onPairing: ({ parentUrl, descriptor }) => {
        tty.write('Open ' + parentUrl + ' in your browser, paste this public pairing descriptor, and complete the security challenge yourself. No credential is copied from the browser.\n');
        tty.write(JSON.stringify(descriptor) + '\n');
      },
    });
    return purpose === 'sign_in'
      ? http.requestEmailSignIn(email, proof, { signal })
      : http.requestEmailVerification(proof, { signal });
  }

  async function enterCode(challenge, purpose) {
    tty.write(challenge.delivery_status === 'unknown'
      ? 'The email request is unconfirmed. If a code arrives, enter it below; no email is resent automatically.\n'
      : 'Check your email for the code.\n');
    for (let attempt = 0; attempt < 5; attempt++) {
      let code = await tty.prompt('Six-digit email code: ', { secret: true });
      try {
        return await (purpose === 'sign_in'
          ? http.verifyEmailSignIn(challenge.challenge_id, code, { signal })
          : http.verifyEmail(challenge.challenge_id, code, { signal }));
      } catch (error) {
        if (error.code !== 'invalid_credentials' || error.outcomeUnknown || attempt === 4) throw error;
        tty.write('That code was not accepted. Enter the code again; no new email was requested.\n');
      } finally {
        code = '';
      }
    }
  }

  return async (purpose, email) => enterCode(await requestCode(purpose, email), purpose);
}

async function runCommands(tty, http, verify) {
  for (;;) {
    const command = await tty.prompt('status / verify / quit: ');
    if (command === 'quit') return;
    if (command === 'status') {
      await http.refresh();
      tty.write(JSON.stringify(http.metadata()) + '\n');
    } else if (command === 'verify') {
      try {
        await verify('sensitive');
        tty.write('Email verified for this session. Previous claims and content remain fenced; resolve original operations before proceeding.\n');
      } catch {
        tty.write('Email verification could not be confirmed. No automatic resend or verification retry occurred. Use status to recheck the original session.\n');
      }
    } else {
      tty.write('Use status, verify or quit.\n');
    }
  }
}

let http, broker, tty;
const lifetime = new AbortController();
const cancel = () => lifetime.abort();
process.once('SIGINT', cancel);
process.once('SIGTERM', cancel);
try {
  const { configPath, configSha, stateDir } = parseBrokerArguments(process.argv.slice(2));
  const config = await readConfig(configPath, configSha);
  await privateDirectory(stateDir);
  process.chdir(stateDir);

  tty = await openOperatorTerminal(lifetime.signal);
  http = new AdminHttp({ origin: config.origin });
  tty.write('Collect Supabase operator. Sign in with an email code. Codes stay in this terminal; no Messages action occurs here.\n');
  const email = await tty.prompt('Email: ');
  const verify = sessionPrompts(tty, http, config.origin, lifetime.signal);
  await verify('sign_in', email);
  broker = new BrokerServer({ stateDir, http });
  tty.write(JSON.stringify(await broker.start()) + '\n');
  await runCommands(tty, http, verify);
} catch {
  if (tty) tty.write('Operator authentication or broker admission failed; no credential creation or automatic retry occurred.\n');
  else process.stderr.write('Collect operator requires the reviewed config, private state directory and an interactive terminal.\n');
  process.exitCode = 1;
} finally {
  process.off('SIGINT', cancel);
  process.off('SIGTERM', cancel);
  lifetime.abort();
  if (http?.snapshot()) await http.logout().catch(() => http.clear());
  await broker?.close().catch(() => {});
  http?.clear();
  await tty?.close().catch(() => {});
}
