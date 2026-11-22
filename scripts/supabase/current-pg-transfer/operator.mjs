// Read exactly one bounded private input from stdin; never accept credentials
// in argv, filenames or output. See README for trusted-supervisor requirements.
import pg from '../node_modules/pg/lib/index.js';
import {ReconciliationError,reconcileCurrentPg,validateReconciliationInputs,isSyntheticReconciliationSocket} from './reconcile.mjs';
import {isManagedReconciliationTarget,managedReconciliationSsl} from './managed-target.mjs';

const {Client} = pg;
const FORMAT = 'collect.current-pg-operator.v1';
const exact = (o,keys) => o && typeof o === 'object' && !Array.isArray(o) &&
  Object.keys(o).sort().join('\0') === [...keys].sort().join('\0');
const refuse = () => { throw new Error('operator_refused'); };

async function privateInput() {
  return new Promise((resolve,reject) => {
    const chunks = []; let size = 0, done = false;
    const finish = error => {
      if (done) return; done = true; clearTimeout(timer);
      process.stdin.removeListener('data',onData); process.stdin.removeListener('end',onEnd);
      if (error) { for (const b of chunks) b.fill(0); process.stdin.destroy(); reject(error); return; }
      const buffer = Buffer.concat(chunks,size); for (const b of chunks) b.fill(0);
      try { resolve(JSON.parse(buffer.toString('utf8'))); } catch { reject(new Error('operator_refused')); }
      finally { buffer.fill(0); }
    };
    const onData = b => { size += b.length; if (size > 1048576) { b.fill(0); finish(new Error('operator_refused')); } else chunks.push(b); };
    const onEnd = () => finish();
    const timer = setTimeout(() => finish(new Error('operator_refused')),10000);
    process.stdin.on('error',() => finish(new Error('operator_refused')));
    process.stdin.on('data',onData); process.stdin.on('end',onEnd);
  });
}

function connectionSpec(identity,credentials,source) {
  if (!exact(credentials,['user','password']) || typeof credentials.user !== 'string' ||
      !/^[a-z_][a-z0-9_.-]{0,127}$/.test(credentials.user) || typeof credentials.password !== 'string' ||
      Buffer.byteLength(credentials.password,'utf8') > 1024 || credentials.password.includes('\0')) refuse();
  const {host,port,kind} = identity.transport;
  // Source socket admission happens in validateReconciliationInputs before
  // the operator creates either client.
  if (!source && kind === 'managed') {
    if (!isManagedReconciliationTarget({host,port,database:identity.database,user:credentials.user}) || credentials.password.length === 0) refuse();
  } else if (!source && kind === 'synthetic') {
    if (!/^collect_fixture_[a-z0-9_]+$/.test(identity.database) || !isSyntheticReconciliationSocket(host)) refuse();
  } else if (!source) refuse();
  return {host,port,database:identity.database,user:credentials.user,password:credentials.password,
    ssl:!source && kind === 'managed' ? managedReconciliationSsl() : false,
    connectionTimeoutMillis:5000,application_name:'collect_current_pg_reconciliation',options:''};
}

async function main() {
  if (process.argv.length !== 3 || !/^[a-f0-9]{64}$/.test(process.argv[2])) refuse();
  // The driver falls back to environment values for empty options and other
  // startup parameters. Refuse those overrides before reading credentials.
  const forbidden = /^(?:PG[A-Z0-9_]*|NODE_[A-Z0-9_]*|SSL_[A-Z0-9_]*|OPENSSL_[A-Z0-9_]*|LD_[A-Z0-9_]*|DYLD_[A-Z0-9_]*|(?:HTTP|HTTPS|ALL|NO)_PROXY)$/i;
  if (process.execArgv.length || Object.entries(process.env).some(([key,value]) => forbidden.test(key) && value)) refuse();
  const input = await privateInput();
  if (!exact(input,['format','contract','sourceIdentity','targetIdentity','credentials']) || input.format !== FORMAT ||
      !exact(input.credentials,['source','target'])) refuse();
  const pin = process.argv[2];
  validateReconciliationInputs({contract:input.contract,sourceIdentity:input.sourceIdentity,targetIdentity:input.targetIdentity,expectedContractSha256:pin});
  const source = new Client(connectionSpec(input.sourceIdentity,input.credentials.source,true));
  const target = new Client(connectionSpec(input.targetIdentity,input.credentials.target,false));
  // Unexpected idle connection errors must not print driver/server messages.
  source.on('error',() => {}); target.on('error',() => {});
  try {
    try { await source.connect(); await target.connect(); } catch { refuse(); }
    return await reconcileCurrentPg({sourceClient:source,targetClient:target,contract:input.contract,
      sourceIdentity:input.sourceIdentity,targetIdentity:input.targetIdentity,expectedContractSha256:pin});
  } finally {
    for (const client of [source,target]) {
      try { client.connection.stream.destroy(); } catch {}
      try { void client.end().catch(() => {}); } catch {}
    }
    // JS strings cannot be reliably wiped; release references promptly.
    input.credentials.source.password = ''; input.credentials.target.password = '';
  }
}

process.stdout.on('error',() => {});
try {
  const result = await main();
  process.stdout.write(JSON.stringify({format:FORMAT,status:'ok',result})+'\n');
} catch (e) {
  const code = e instanceof ReconciliationError ? e.code : 'operator_refused';
  process.stdout.write(JSON.stringify({format:FORMAT,status:'refused',code})+'\n');
  process.exitCode = 1;
}
