import { once } from 'node:events';
import { randomUUID } from 'node:crypto';
import { createConnection } from 'node:net';
import { createInterface } from 'node:readline';
import { fixture } from './http_fixture.mjs';
import { AdminHttp } from '../src/http_client.mjs';
import { BrokerServer } from '../src/broker.mjs';
import { ORIGINS } from '../src/contract.mjs';

const stateDir = process.argv[2];
process.chdir(stateDir);
const server = await fixture();
const http = new AdminHttp({ origin: ORIGINS[0], fetchImpl: server.fetch, clock: () => server.now, timeoutMs: 2000 });
const login = () => server.login(http);
await login();
const broker = new BrokerServer({ stateDir, http, clock: () => server.now });
const descriptor = await broker.start();
process.send({ event: 'ready', descriptor, jobs: [server.first.id, server.second.id] });

let release;
let closing;

function closeFixture() {
  closing ??= broker.close().finally(() => server.close());
  return closing;
}

async function simulateUnknownVerification() {
  const original = http.snapshot().emailVerifiedAt;
  server.now += 1000;
  const challenge = await http.requestEmailVerification(await server.emailProof('sensitive'));
  server.authFault = '/api/admin/auth/email/verify';
  let unknown = false;
  try {
    await http.verifyEmail(challenge.challenge_id, server.code);
  } catch (error) {
    unknown = error.outcomeUnknown === true;
  }
  if (!unknown) throw new Error('synthetic_unknown_verification_required');
  server.authTransform = (path, value) => path === '/api/admin/auth/email-verification'
    ? { ...value, emailVerifiedAt: original }
    : value;
}

async function duplicateRead() {
  // The child already runs in the physical socket directory.
  const socket = createConnection(descriptor.socket_relative_name);
  const replies = createInterface({ input: socket });
  try {
    const frames = replies[Symbol.asyncIterator]();
    await once(socket, 'connect');
    const envelope = {
      instance_id: descriptor.instance_id,
      operator_session: descriptor.operator_session,
    };
    socket.write(JSON.stringify({ ...envelope, id: randomUUID(), method: 'hello' }) + '\n');
    if (!JSON.parse((await frames.next()).value).ok) throw new Error('fixture_broker_handshake_failed');
    const frame = JSON.stringify({
      ...envelope,
      id: randomUUID(),
      method: 'call',
      action: 'list_pending',
      arguments: { operator_session: descriptor.operator_session },
    }) + '\n';
    socket.write(frame.repeat(2));
    return [JSON.parse((await frames.next()).value), JSON.parse((await frames.next()).value)];
  } finally {
    replies.close();
    socket.destroy();
  }
}

async function runControl(message) {
  switch (message.command) {
    case 'fault_after':
      server.fault = { action: message.action, after: true };
      break;
    case 'hold':
      server.fault = {
        action: message.action,
        gate: new Promise(resolve => { release = resolve; }),
        entered: () => process.send({ event: 'entered' }),
      };
      break;
    case 'release':
      release?.();
      break;
    case 'login':
      await login();
      break;
    case 'reverify':
      server.now += 1000;
      await server.reverify(http);
      break;
    case 'unknown_verify_old_readback':
      await simulateUnknownVerification();
      break;
    case 'reveal_current_proof':
      server.authTransform = null;
      break;
    case 'advance':
      server.now += message.milliseconds;
      break;
    case 'duplicate_read':
      return { replies: await duplicateRead() };
    case 'stats':
      break;
    default:
      throw new Error('unsupported_fixture_control');
  }
  return { counts: server.counts, effects: server.effectCounts };
}

process.on('message', message => {
  void (async () => {
    try {
      if (message.command === 'close') {
        await closeFixture();
        process.send({ id: message.id, ok: true });
        process.disconnect();
        return;
      }
      const result = await runControl(message);
      process.send({ id: message.id, ok: true, ...result });
    } catch {
      process.send({ id: message.id, ok: false });
    }
  })();
});
process.on('disconnect', () => { void closeFixture(); });
