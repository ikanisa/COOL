import assert from 'node:assert/strict';
import {
  canonicalProfile,
  legacyDeploymentProfile,
  MANAGED_SUPABASE_ORIGIN,
} from '../../../supabase/functions/_shared/deployment-profile.js';
import { createSmsGatewayHandler } from '../src/edge.ts';
import {
  gatewayConnection,
  gatewayDatabaseReadiness,
  managedGatewayDatabaseUrl,
} from '../src/gateway-connection.ts';
import type { GatewayDatabase } from '../src/postgres.ts';
import { sha256 } from '../src/util.ts';

const publicOrigin = MANAGED_SUPABASE_ORIGIN;
const profile = canonicalProfile(legacyDeploymentProfile());
const source = await sha256('synthetic core source');
const release = await sha256('synthetic gateway source');
const approval = await sha256('synthetic gateway approval');
const rootToken = await sha256('SMS route fixture root admin');
const otpKey = await sha256('SMS route fixture OTP');
const maintenanceToken = await sha256('SMS route fixture maintenance');
const applicationToken = 'synthetic-application-token';
const deviceToken = 'synthetic-device-token';
const appDigest = await sha256(applicationToken);
const deviceDigest = await sha256(deviceToken);
const gatewayLogin = 'collect_sms_edge_login.rrlduytparvsjfmegalh';

function fixtureDatabaseUrl(host: string, username: string, sslMode?: string) {
  const url = new URL(`postgresql://${host}:5432/postgres`);
  url.username = username;
  url.password = 'synthetic';
  if (sslMode) url.searchParams.set('sslmode', sslMode);
  return url.href;
}

const databaseUrl = fixtureDatabaseUrl('aws-0-eu-north-1.pooler.supabase.com', gatewayLogin, 'verify-full');
const settings: Record<string, string | undefined> = {
  APP_ENVIRONMENT: 'production',
  SUPABASE_URL: publicOrigin,
  COLLECT_SMS_ENABLED: 'true',
  BUILD_SOURCE_ID: source,
  COLLECT_SMS_CORE_SOURCE_SHA256: source,
  COLLECT_SMS_RELEASE_SHA256: release,
  COLLECT_SMS_APPROVAL_SHA256: approval,
  COLLECT_DEPLOYMENT_PROFILE: profile,
  COLLECT_DEPLOYMENT_PROFILE_SHA256: await sha256(profile),
  COLLECT_SMS_DATABASE_URL: databaseUrl,
  COLLECT_SMS_ROOT_ADMIN_TOKEN: rootToken,
  COLLECT_SMS_OTP_HMAC_KEY: otpKey,
};

type WorkRow = {
  contractVersion: number;
  admissionId: string;
  sourceSha256: string;
  kind: string;
  epoch: number;
  state: string;
  mode: string;
};
function admissionDouble(options: { reject?: boolean; loseClose?: boolean } = {}) {
  const rows = new Map<string, WorkRow>();
  return {
    rows,
    async register(id: string, sourceSha256: string, kind: string) {
      if (options.reject) throw Error('deployment_identity_mismatch');
      const row = { contractVersion: 1, admissionId: id, sourceSha256, kind, epoch: 1, state: 'active', mode: 'open' };
      rows.set(id, row);
      return row;
    },
    async lease(id: string) {
      const row = rows.get(id)!;
      return { row, assert: async () => row, release: async () => {} };
    },
    async close(id: string, _epoch: number, _source: string, state: string, reason: string,
      externalDispatches: number, uncertainDispatches: number) {
      if (options.loseClose) throw Error('uncertain close');
      return { ...rows.get(id), state, reason, externalDispatches, uncertainDispatches };
    },
    async status(id: string) {
      return { ...rows.get(id), found: rows.has(id) };
    },
  };
}

function databaseDouble(options: { ready?: boolean; readError?: boolean } = {}) {
  const calls: { sql: string; parameters: unknown[] }[] = [];
  const database = {
    withApplicationWork() { return this; },
    prepare(sql: string) {
      let parameters: unknown[] = [];
      return {
        bind(...values: unknown[]) { parameters = values; return this; },
        async first() {
          calls.push({ sql, parameters });
          if (sql === 'SELECT 1 AS ok') return { ok: 1 };
          if (sql === gatewayDatabaseReadiness) {
            if (options.readError) throw Error('gateway catalog unavailable');
            return { ready: options.ready ?? true };
          }
          if (sql.startsWith('SELECT application_id,allowed_kinds,scopes FROM applications')) {
            return parameters[0] === appDigest
              ? { application_id: 'synthetic-app', allowed_kinds: '["receipt"]', scopes: '["messages:read"]' }
              : null;
          }
          if (sql.startsWith('SELECT installation_id,allowed_kinds FROM devices')) {
            return parameters[0] === deviceDigest
              ? { installation_id: 'synthetic-device', allowed_kinds: '["receipt"]' }
              : null;
          }
          if (sql.startsWith('SELECT * FROM devices WHERE installation_id=')) return { ready: 1 };
          if (sql.includes('FROM messages m WHERE m.message_id=')) return null;
          assert.fail('Unexpected query in synthetic ingress test');
        },
      };
    },
    async batch() { assert.fail('Unexpected database batch in synthetic ingress test'); },
  } as unknown as GatewayDatabase;
  return { database, calls };
}

function gateway(values: typeof settings = {}, backend = admissionDouble(), fixture = databaseDouble()) {
  const handler = createSmsGatewayHandler({ ...settings, ...values }, { database: fixture.database, fenceBackend: backend });
  return {
    calls: fixture.calls,
    admissions: backend.rows,
    fetch: (path: string, init?: RequestInit) => handler(new Request(publicOrigin + '/functions/v1/collect-sms' + path, init)),
    fetchUrl: (url: string, init?: RequestInit) => handler(new Request(url, init)),
  };
}

function bearer(token: string) {
  return { Authorization: 'Bearer ' + token };
}

Deno.test('gateway preserves both hosted function paths and confines HTTP normalization to its project', async () => {
  const { fetchUrl, admissions } = gateway();
  for (const origin of [publicOrigin, publicOrigin.replace('https:', 'http:')]) {
    for (const prefix of ['/functions/v1/collect-sms', '/collect-sms']) {
      const response = await fetchUrl(origin + prefix + '/health?probe=one');
      assert.equal(response.status, 200, origin + prefix);
      assert.deepEqual(await response.json(), { status: 'ok', service: 'collect-sms', version: '0.3.0' });
    }
  }
  for (const row of admissions.values()) {
    assert.equal(row.sourceSha256, source);
    assert.equal(row.kind, 'http_collect');
  }
});

Deno.test('gateway rejects unapproved authorities and exact-path mismatches before admitting work', async () => {
  const { fetchUrl, admissions } = gateway();
  for (const origin of ['https://example.invalid', 'http://api-gw:8000', 'http://127.0.0.1:9000',
    publicOrigin.replace('https:', 'http:') + ':9000']) {
    assert.equal((await fetchUrl(origin + '/collect-sms/health', {
      headers: { 'X-Forwarded-Proto': 'https', 'X-Forwarded-Host': new URL(publicOrigin).hostname },
    })).status, 403, origin);
  }
  for (const path of ['/health', '/v1/messages', '/collect-sms-other/health',
    '/functions/v1/collect-sms-other/health', '/collect-sms//health']) {
    assert.equal((await fetchUrl(publicOrigin + path, { headers: { 'X-Collect-Original-Path': '/health' } })).status, 404, path);
  }
  assert.equal(admissions.size, 0);
});

Deno.test('gateway verifies the explicit managed profile, source, approval and restricted TLS login', async () => {
  const denied: (typeof settings)[] = [
    { COLLECT_SMS_ENABLED: undefined },
    { COLLECT_SMS_ENABLED: 'false' },
    { COLLECT_DEPLOYMENT_PROFILE: undefined },
    { COLLECT_DEPLOYMENT_PROFILE_SHA256: approval },
    { APP_ENVIRONMENT: 'qualification' },
    { SUPABASE_URL: 'https://example.invalid' },
    { COLLECT_SMS_CORE_SOURCE_SHA256: release },
    { COLLECT_SMS_RELEASE_SHA256: undefined },
    { COLLECT_SMS_APPROVAL_SHA256: undefined },
    { COLLECT_SMS_APPROVAL_SHA256: release },
    { COLLECT_SMS_ROOT_ADMIN_TOKEN: undefined, ROOT_ADMIN_TOKEN: rootToken },
    { COLLECT_SMS_OTP_HMAC_KEY: rootToken },
    { COLLECT_SMS_DISPATCH_PAUSED: 'fales' },
    { COLLECT_SMS_DATABASE_URL: undefined, SUPABASE_DB_URL: databaseUrl },
    { COLLECT_SMS_DATABASE_URL: databaseUrl.replace(gatewayLogin, 'postgres.rrlduytparvsjfmegalh') },
    { COLLECT_SMS_DATABASE_URL: databaseUrl.replace(gatewayLogin, 'collect_sms_edge_login.unrelated') },
    { COLLECT_SMS_DATABASE_URL: databaseUrl.replace('aws-0-eu-north-1.pooler.supabase.com', 'other.pooler.supabase.com') },
    { COLLECT_SMS_DATABASE_URL: databaseUrl.replace('aws-0-eu-north-1.pooler.supabase.com', '127.0.0.1') },
    { COLLECT_SMS_DATABASE_URL: databaseUrl.replace(':5432/', ':6543/') },
    { COLLECT_SMS_DATABASE_URL: databaseUrl.replace('verify-full', 'require') },
    { COLLECT_SMS_DATABASE_URL: databaseUrl + '&host=example.invalid' },
  ];
  for (const values of denied) {
    const { fetch, admissions } = gateway(values);
    assert.equal((await fetch('/health')).status, 503, Object.keys(values).join(', '));
    assert.equal(admissions.size, 0);
  }
  const direct = fixtureDatabaseUrl('db.rrlduytparvsjfmegalh.supabase.co', 'collect_sms_edge_login');
  assert.equal((await gateway({ COLLECT_SMS_DATABASE_URL: direct }).fetch('/health')).status, 200);
  const unbound = gateway({}, admissionDouble({ reject: true }));
  assert.equal((await unbound.fetch('/health')).status, 503);
  assert.equal(unbound.calls.length, 0);
});

Deno.test('gateway pins its TLS name and scopes the trusted CA setting to SMS', async () => {
  const ca = '-----BEGIN CERTIFICATE-----\nsynthetic-sms-ca';
  const target = managedGatewayDatabaseUrl(settings);
  assert.equal(new URL(target).search, '');
  const sql = gatewayConnection(target, {
    COLLECT_SMS_DATABASE_CA_PEM: ca,
    COLLECT_DB_CA_PEM: 'ignored shared CA',
  });
  try {
    assert.deepEqual(sql.options.ssl, {
      rejectUnauthorized: true,
      servername: 'aws-0-eu-north-1.pooler.supabase.com',
      ca,
    });
  } finally {
    await sql.end({ timeout: 0 });
  }
});

Deno.test('readiness returns only bootstrapped source and capability proof with safe transport defaults', async () => {
  const fixture = gateway({
    DISPATCH_PAUSED: 'false',
    FCM_ENABLED: 'true',
    RETENTION_AUTO_PURGE: 'true',
    COLLECT_SMS_MAINTENANCE_TOKEN: maintenanceToken,
  });
  for (const token of [null, 'wrong-root', applicationToken, deviceToken, maintenanceToken]) {
    const response = await fixture.fetch('/internal/readiness', token ? { headers: bearer(token) } : {});
    assert.equal(response.status, 404);
  }
  assert.equal((await fixture.fetch('/internal/readiness', { method: 'POST', headers: bearer(rootToken) })).status, 404);
  assert.equal((await fixture.fetch('/internal/readiness', {
    headers: { ...bearer(rootToken), Origin: 'https://example.invalid' },
  })).status, 404);
  assert.equal((await fixture.fetch('/internal/maintenance', { method: 'POST', headers: bearer(rootToken) })).status, 404);
  assert.equal(fixture.admissions.size, 0);
  const response = await fixture.fetch('/internal/readiness', { headers: bearer(rootToken) });
  assert.equal(response.status, 200);
  assert.equal(response.headers.get('cache-control'), 'no-store');
  assert.deepEqual(await response.json(), {
    status: 'ready',
    service: 'collect-sms',
    core_source_sha256: source,
    release_sha256: release,
    profile_sha256: settings.COLLECT_DEPLOYMENT_PROFILE_SHA256,
    dispatch_paused: true,
    fcm_enabled: false,
    retention_auto_purge: false,
    capabilities: { application_messages: true, device_dispatch: true },
  });
  assert.deepEqual(fixture.calls, [{ sql: gatewayDatabaseReadiness, parameters: [] }]);
});

Deno.test('readiness fails closed when the role or original work completion cannot be proved', async () => {
  for (const fixture of [
    gateway({}, admissionDouble(), databaseDouble({ ready: false })),
    gateway({}, admissionDouble(), databaseDouble({ readError: true })),
    gateway({}, admissionDouble({ loseClose: true })),
  ]) {
    assert.equal((await fixture.fetch('/internal/readiness', { headers: bearer(rootToken) })).status, 503);
  }
});

Deno.test('gateway retains browser origin checks and application and device authentication and scope', async () => {
  const fixture = gateway({ DISPATCH_PAUSED: 'false' });
  const direct = publicOrigin.replace('https:', 'http:') + '/collect-sms';
  assert.equal((await fixture.fetchUrl(direct + '/health', {
    headers: { Origin: 'https://example.invalid' },
  })).status, 403);
  assert.equal((await fixture.fetch('/v1/device/jobs')).status, 401);
  assert.equal((await fixture.fetch('/v1/device/jobs', { headers: bearer(applicationToken) })).status, 403);
  assert.equal((await fixture.fetch('/v1/messages/synthetic-message', { headers: bearer(deviceToken) })).status, 403);
  const scoped = await fixture.fetch('/v1/messages/synthetic-message', { headers: bearer(applicationToken) });
  assert.equal(scoped.status, 404);
  const lookup = fixture.calls.find((call) => call.sql.includes('FROM messages m WHERE m.message_id='));
  assert.match(lookup?.sql ?? '', /AND m\.application_id=\?/);
  assert.deepEqual(lookup?.parameters, ['synthetic-message', 'synthetic-app']);
  const deniedWrite = await fixture.fetchUrl(direct + '/v1/messages', {
    method: 'POST', headers: { ...bearer(applicationToken), 'Content-Type': 'application/json' },
    body: JSON.stringify({ kind: 'receipt' }),
  });
  assert.equal(deniedWrite.status, 403);
  const paused = await fixture.fetch('/v1/device/jobs?limit=2', { headers: bearer(deviceToken) });
  assert.equal(paused.status, 200);
  const body = await paused.json();
  assert.deepEqual(body.jobs, []);
  assert.equal(body.dispatch_permit_until, body.server_time);
});
