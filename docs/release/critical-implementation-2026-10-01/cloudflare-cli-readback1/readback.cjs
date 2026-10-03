// Read-only Cloudflare identity readback. Never refreshes authentication or publishes.
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { execFileSync } = require('node:child_process');
const ROOT = '/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL';
const OUT = __dirname;
const CANDIDATE = '.cache/public-static-current-20261002-batch4-attempt1';
const AUTH = '/Users/jeanbosco/Library/Preferences/.wrangler/config/default.toml';
const HOST = 'collect.ikanisa.com';
const EXPECTED = 'collect-public';
const start = new Date();
const deadline = Date.now() + 55000;
const sha = b => crypto.createHash('sha256').update(b).digest('hex');
const identity = relative => {
  const p = path.join(ROOT, relative);
  const st = fs.statSync(p);
  return { path: relative, bytes: st.size, sha256: sha(fs.readFileSync(p)), mtime: st.mtime.toISOString(), mode: (st.mode & 0o777).toString(8) };
};
const files = [
  'AGENTS.md', '.github/workflows/public-website.yml', 'deploy/public.wrangler.jsonc',
  'Makefile', 'scripts/public_static_site_build.rb', 'scripts/public_website_ci_gate.sh',
  ...['version.json','manifest.json','index.html','privacy/index.html','terms/index.html',
    'security/index.html','trust/index.html','account-deletion/index.html','data-deletion/index.html']
    .map(p => `${CANDIDATE}/${p}`)
];
const before = files.map(identity);
const authText = fs.readFileSync(AUTH, 'utf8');
const token = (authText.match(/^\s*oauth_token\s*=\s*"([^"\n]+)"/m) || [])[1];
const expiry = (authText.match(/^\s*expiration_time\s*=\s*"([^"\n]+)"/m) || [])[1];
const clean = s => String(s).replaceAll(token || '__NO_TOKEN__', '[REDACTED]').replace(/[\w.+-]+@[\w.-]+\.[a-z]{2,}/gi, '[EMAIL REDACTED]').slice(0,400);
const report = {
  schema: 'collect-cloudflare-readonly-identity-v1', startedAt: start.toISOString(),
  target: { hostname: HOST, expectedWorker: EXPECTED, sourceAccountDeclared: false, sourceRoutesDeclared: false, sourceAssetsDirectory: '../build/public_web', configuredCandidateDirectory: false },
  criteriaRetained: ['Provider account, exact custom-domain service mapping and active deployment identity must be read back independently.', 'Current batch4 artifact deployment equality is not established by deployment metadata or HTTP headers.', 'Production readiness, original Revolut comparison, browser interactions, native evidence and release acceptance remain separate required criteria.'],
  workflow: { path: '.github/workflows/public-website.yml', staticGates: true, liveGates: true, publishingStep: false },
  candidate: JSON.parse(fs.readFileSync(path.join(ROOT,CANDIDATE,'version.json'),'utf8')),
  sourceInputsBefore: before,
  head: execFileSync('/usr/bin/git',['rev-parse','HEAD'],{cwd:ROOT,env:{PATH:'/usr/bin:/bin'},encoding:'utf8'}).trim(),
  runtime: { path: process.execPath, version: process.version, sha256: sha(fs.readFileSync(process.execPath)), scriptSha256: sha(fs.readFileSync(__filename)) },
  connection: { kind: 'existing-local-Wrangler-OAuth via direct HTTPS GET', credentialPath: AUTH, oauthFieldPresent: Boolean(token), expiration: expiry || null, unexpiredAtStart: Boolean(expiry && Date.parse(expiry)>start.getTime()), credentialValuesCaptured: false, credentialsRefreshed: false, wranglerExecuted: false, cliAvailability: 'No executable on PATH or Wrangler package in bounded existing npx root inventory.', inheritedEnvironment: 'env -i; PATH=/usr/bin:/bin only' },
  bounds: { method: 'GET only', perRequestMilliseconds: 10000, totalDeadlineMilliseconds: 55000, maximumResponseBytes: 524288, maximumAccounts: 3, automaticRedirects: false, automaticRetries: false, maximumDeploymentsRetained: 5 },
  providerReads: [], matches: [], status: 'pending', limitations: []
};
async function get(endpoint, filter) {
  const receipt = { method:'GET', endpoint, startedAt:new Date().toISOString() };
  report.providerReads.push(receipt);
  try {
    const remaining = deadline-Date.now();
    if(remaining<=0) throw new Error('total_readback_deadline_reached');
    const response = await fetch(`https://api.cloudflare.com/client/v4${endpoint}`, {
      method:'GET', redirect:'error', signal:AbortSignal.timeout(Math.min(10000,remaining)),
      headers:{Authorization:`Bearer ${token}`, Accept:'application/json'}
    });
    receipt.httpStatus=response.status;
    const chunks=[]; let size=0;
    for await (const chunk of response.body) {
      size+=chunk.length;
      if(size>524288) throw new Error('response_byte_bound_exceeded');
      chunks.push(chunk);
    }
    const bytes=Buffer.concat(chunks);
    receipt.responseBytes=bytes.length;
    receipt.responseSha256=sha(bytes);
    const parsed=JSON.parse(bytes.toString('utf8'));
    receipt.providerSuccess=parsed.success===true;
    receipt.errors=(parsed.errors||[]).slice(0,5).map(e=>({code:e.code,message:clean(e.message)}));
    receipt.resultInfo=parsed.result_info ? Object.fromEntries(Object.entries(parsed.result_info).filter(([k])=>['count','page','per_page','total_count','total_pages'].includes(k))) : null;
    if(response.ok && parsed.success===true) receipt.facts=filter(parsed.result);
  } catch(e) {receipt.error={name:clean(e.name),message:clean(e.message)};}
  receipt.finishedAt=new Date().toISOString();
  return receipt;
}
async function run() {
  if(!token || !report.connection.unexpiredAtStart) {
    report.status='blocked_authentication';
    report.limitations.push('No current usable OAuth credential. Authentication was not refreshed.');
    return;
  }
  const accounts=await get('/accounts?per_page=50',r=>({accountIds:Array.isArray(r)?r.map(x=>x.id).filter(x=>/^[a-f0-9]{32}$/.test(x)):[]}));
  if(!accounts.facts) {
    report.status='blocked_account_readback';
    report.limitations.push('Existing credential did not establish a successful account list. No login, refresh, retry or provider change was performed.');
    return;
  }
  const ids=accounts.facts.accountIds;
  if(ids.length>3 || (accounts.resultInfo?.total_pages||0)>1) report.limitations.push('Account discovery was bounded to the first page and first three returned account IDs.');
  for(const accountId of ids.slice(0,3)) {
    const domains=await get(`/accounts/${accountId}/workers/domains?hostname=${HOST}`,r=>({matches:(Array.isArray(r)?r:[]).filter(d=>d.hostname===HOST).map(d=>({id:d.id,hostname:d.hostname,service:d.service,environment:d.environment,zoneId:d.zone_id,zoneName:d.zone_name}))}));
    for(const mapping of domains.facts?.matches||[]) {
      const match={accountId,mapping,sourceWorkerMatches:mapping.service===EXPECTED};
      report.matches.push(match);
      if(!/^[A-Za-z0-9_-]{1,63}$/.test(mapping.service)) {report.limitations.push('Provider service name did not pass the bounded endpoint identifier guard.');continue;}
      const deployments=await get(`/accounts/${accountId}/workers/scripts/${encodeURIComponent(mapping.service)}/deployments?per_page=5`,r=>({deployments:(Array.isArray(r?.deployments)?r.deployments:[]).slice(0,5).map(d=>({id:d.id,createdOn:d.created_on,source:d.source,strategy:d.strategy,versions:(d.versions||[]).map(v=>({versionId:v.version_id,percentage:v.percentage}))}))}));
      match.activeDeployment=deployments.facts?.deployments?.[0]||null;
    }
    if(report.matches.length) break;
  }
  report.status=report.matches.some(x=>x.sourceWorkerMatches && x.activeDeployment)?'provider_identity_read_back':'provider_identity_incomplete';
  if(!report.matches.length) report.limitations.push('The exact hostname was not confirmed by a successful Workers custom-domain response in the bounded accounts. This does not prove the public hostname is absent; another routing product or inaccessible account remains possible.');
  report.limitations.push('Readback contains deployment IDs and traffic versions only. It contains no content hash linking the deployed Worker assets to the current local batch4 artifact.');
}
run().catch(e=>{report.status='readback_error';report.limitations.push(clean(e.message));}).finally(()=>{
  report.finishedAt=new Date().toISOString();
  report.durationMilliseconds=Date.now()-start.getTime();
  report.sourceInputsAfter=files.map(identity);
  report.selectedInputsByteStable=JSON.stringify(before.map(x=>[x.path,x.bytes,x.sha256]))===JSON.stringify(report.sourceInputsAfter.map(x=>[x.path,x.bytes,x.sha256]));
  report.providerStateMutated=false;
  fs.writeFileSync(path.join(OUT,'readback.json'),JSON.stringify(report,null,2)+'\n',{flag:'wx'});
  console.log(JSON.stringify({status:report.status,providerReadCount:report.providerReads.length,matches:report.matches,selectedInputsByteStable:report.selectedInputsByteStable,durationMilliseconds:report.durationMilliseconds},null,2));
});
