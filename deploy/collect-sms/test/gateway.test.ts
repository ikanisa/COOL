import assert from "node:assert/strict";
import { after, before, beforeEach, test } from "node:test";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { createHash, generateKeyPairSync } from "node:crypto";
import postgres from "npm:postgres@3.4.7";
import {GatewayDatabase} from "../src/postgres.ts";
import {smsFenceBackend} from '../src/fence.ts';
import {openApplicationWork} from '../../../supabase/functions/_shared/application-fence.js';
import { flushWakeups } from "../src/fcm.ts";
import { payloadDigest } from "../src/util.ts";
import { app as directApp } from "../src/index.ts";
import {enqueueSchedules} from '../src/schedules.ts';
import {purgeRetention} from '../src/retention.ts';
import {CURRENT_NATIVE_PROFILE,CURRENT_MIGRATION_COUNT,installCurrentFixtureAdditions,validateCurrentFixtureDescriptor} from '../../../scripts/supabase/testing/self-hosted-current-schema.mjs';
const ADMIN = "test-admin-token-000000000000000000000000000000000000";
let mf:any;
let owner:ReturnType<typeof postgres>;
let control:ReturnType<typeof postgres>,fixtureWork:any;
let db: any;
const future = (ms = 3_600_000) => new Date(Date.now() + ms).toISOString();
const now = () => new Date().toISOString();
const fixturePath=Deno.env.get('COLLECT_SMS_FIXTURE_FILE');
assert.equal(Deno.env.get('COLLECT_CI_SYNTHETIC'),'true');
assert(fixturePath?.endsWith('/collect-gateway-fixture.private.json'));
const fixture=JSON.parse(readFileSync(fixturePath!,'utf8'));
const current=Deno.env.get('COLLECT_SELFHOST_NATIVE_PROFILE')===CURRENT_NATIVE_PROFILE;
assert(current,'The maintained gateway test requires the complete reviewed current chain');
validateCurrentFixtureDescriptor(fixture,{purpose:'gateway'});
const target=new URL(fixture.url);
assert.equal(target.hostname,'127.0.0.1');assert.equal(target.username,'postgres');
assert.match(target.pathname,/^\/collect_[a-z0-9_]+_test$/);
const environment={ROOT_ADMIN_TOKEN:ADMIN,OTP_HMAC_KEY:'fixture-hmac-key-0000000000000000000000000000000000000000',ENVIRONMENT:'development',ALLOW_INSECURE_LOCALHOST:'true',FCM_ENABLED:'false',ADMIN_ORIGIN:'http://localhost:5173'};
const originalFetch=globalThis.fetch;
before(async()=>{
 globalThis.fetch=()=>{throw Error('External gateway requests forbidden in native qualification');};
 owner=postgres(fixture.url,{max:1,prepare:false,ssl:false,onnotice:()=>{},types:{bigint:{to:20,from:[20],serialize:String,parse:Number}}});
 assert.equal((await owner`SELECT current_database() AS name`)[0].name,target.pathname.slice(1));
  const schema=await installCurrentFixtureAdditions(owner);
  assert.equal(schema.migration_count,CURRENT_MIGRATION_COUNT);
  assert.equal((await owner`SELECT private.collect_fence_owner_status() AS value`)[0].value.sourceSha256,fixture.source_sha256);
 const profile={format:'collect.deployment.v1',id:'gateway-protocol-fixture',mode:'self_hosted',environment:'qualification',supabase_origin:'https://supabase.gateway.example.invalid',member_api_origin:'https://api.gateway.example.invalid',admin_origin:'https://admin.gateway.example.invalid',public_origin:'https://www.gateway.example.invalid',google_callback_origin:'https://admin.gateway.example.invalid'};
 const raw=JSON.stringify(Object.fromEntries(Object.keys(profile).sort().map(k=>[k,(profile as any)[k]]))),digest=createHash('sha256').update(raw).digest('hex'),operation=crypto.randomUUID();
 // The supplied original16 fixture is OPEN. Reach actual FENCED before binding
 // its first identity, then release normally; never replace the assertion.
 await owner`SELECT private.collect_fence_begin_quiesce(${operation}::uuid,1,${fixture.source_sha256})`;
 assert.equal((await owner`SELECT private.collect_fence_drain_v3(${operation}::uuid,1,${fixture.source_sha256})AS value`)[0].value.mode,'fenced');
 await owner`SELECT private.collect_bind_deployment(${crypto.randomUUID()}::uuid,${raw},${digest})`;
 await owner`SELECT private.collect_fence_release_v3(${crypto.randomUUID()}::uuid,1,${fixture.source_sha256})`;
 // Only this explicitly owned disposable fixture cluster's normal owner gains
 // SET authority; no runtime login receives ownership or bypass privileges.
 await owner.unsafe('GRANT collect_sms_runtime TO postgres WITH SET TRUE');
 control=postgres(fixture.url,{max:1,prepare:false,ssl:false,onnotice:()=>{}});
 fixtureWork=await (openApplicationWork as any)({backend:smsFenceBackend(owner,control,digest),sourceSha256:fixture.source_sha256,kind:'jobs'});
 db=new GatewayDatabase(owner).withApplicationWork(fixtureWork);
 mf={dispatchFetch:(url:string,init?:RequestInit)=>directApp.fetch(new Request(url,init),{...environment,DB:db},{props:{},waitUntil(){},passThroughOnException(){}})};
});
beforeEach(async()=>{
 const tables=JSON.parse(readFileSync(new URL('./reset-order.json',import.meta.url),'utf8'));
 for(const table of tables){assert.match(table,/^[a-z_]+$/);await db.prepare(`DELETE FROM ${table}`).run();}
});
after(async()=>{globalThis.fetch=originalFetch;try{await fixtureWork?.finish();}finally{await control?.end({timeout:2});await owner?.end({timeout:2});}});
test('private schema and evidence view deny REST roles',async()=>{
 for(const role of ['anon','authenticated','service_role','collect_runtime'])
  assert.equal((await owner`SELECT has_schema_privilege(${role},'collect_sms','USAGE') AS allowed`)[0].allowed,false);
 assert.equal((await owner`SELECT reloptions FROM pg_class WHERE oid='collect_sms.attempt_evidence'::regclass`)[0].reloptions.includes('security_invoker=true'),true);
});
test('published template versions are immutable and schedules need fresh eligibility',async()=>{
 const a=await appCredential(),d=await deviceCredential(),body={template_key:'reminder',version:1,locale:'en',kind:'operation',body:'Record {{amount}}.',variables:{amount:'rwf'}};
 assert.equal((await request('POST','/v1/templates',a.token,body)).status,201);
 assert.equal((await request('POST','/v1/templates/reminder/1/en/publish',a.token,{confirm:'publish_reviewed_template'})).status,200);
 assert.equal((await request('POST','/v1/templates',a.token,{...body,body:'Changed {{amount}}.'})).status,409);
 await assert.rejects(db.prepare("UPDATE sms_templates SET body='changed' WHERE application_id=?").bind(a.id).run(),/template_immutable/);
 const schedule=await request('POST','/v1/schedules',a.token,{name:'Synthetic',to:'+250788000001',template_key:'reminder',template_version:1,locale:'en',variables:{amount:100},interval_seconds:60,ttl_seconds:300,starts_at:new Date(Date.now()-1000).toISOString(),ends_at:future()},'schedule-one');
 assert.equal(schedule.status,201,JSON.stringify(schedule.body));assert.equal(schedule.body.active,false);
 assert.equal((await enqueueSchedules({...environment,DB:db})).enqueued,0);
 assert.equal((await request('POST','/v1/schedules/'+schedule.body.schedule_id+'/start',a.token,{})).status,200);
 await Promise.all([1,2].map(()=>enqueueSchedules({...environment,DB:db})));
 assert.equal((await db.prepare('SELECT count(*) AS n FROM schedule_occurrences').first()).n,1);
 const queued=await db.prepare('SELECT * FROM messages').first();assert.equal(queued.requires_fresh_decision,1);assert.equal(queued.eligibility_until,null);
 const pulled=await request('GET','/v1/device/jobs',d.token);assert.equal(pulled.body.jobs.length,0);
});
test('staff sessions preserve role scopes and rotation revokes old authority',async()=>{
 const created=await request('POST','/v1/admin/staff',ADMIN,{name:'Synthetic viewer',role:'viewer'});assert.equal(created.status,201);
 const issued=await request('POST','/v1/staff/sessions',created.body.access_key,{});assert.equal(issued.status,201);
 assert.equal((await request('GET','/v1/admin/overview',issued.body.session_token)).status,200);
 assert.equal((await request('GET','/v1/admin/staff',issued.body.session_token)).status,403);
 assert.equal((await request('POST','/v1/admin/staff/'+created.body.staff_id+'/rotate',ADMIN,{})).status,200);
 assert.equal((await request('GET','/v1/admin/overview',issued.body.session_token)).status,401);
 assert.equal((await request('POST','/v1/staff/sessions',created.body.access_key,{})).status,401);
});
test('retention redacts old terminal payloads without erasing unknowns or replay identity',async()=>{
 const a=await appCredential(),done=await send(a.token),unknown=await send(a.token,{},'unknown');
 const old=new Date(Date.now()-3*86400000).toISOString();
 await db.prepare("UPDATE messages SET state='sent',not_after=?,updated_at=? WHERE message_id=?").bind(old,old,done.body.message_id).run();
 await db.prepare("UPDATE messages SET state='outcome_unknown',not_after=?,updated_at=? WHERE message_id=?").bind(old,old,unknown.body.message_id).run();
 const result=await purgeRetention({...environment,DB:db,MESSAGE_RETENTION_DAYS:'1'},{type:'system',id:'synthetic'});assert.equal(result.redacted_messages,1);
 const row=await db.prepare('SELECT * FROM messages WHERE message_id=?').bind(done.body.message_id).first();assert.equal(row.text,'');assert(row.payload_digest);assert(row.content_redacted_at);
 await assert.rejects(db.prepare("UPDATE messages SET text='rehydrate' WHERE message_id=?").bind(done.body.message_id).run(),/event_content_redacted/);
 assert.equal((await db.prepare('SELECT content_redacted_at FROM messages WHERE message_id=?').bind(unknown.body.message_id).first()).content_redacted_at,null);
});
test('ledger snapshot replay cannot rewrite facts or add a recipient after redaction',async()=>{
 const a=await appCredential(),body={event_id:'ledger-one',recipient:'+250788000001',collection_id:'group',collection_name:'Synthetic group',member_id:'member',currency:'RWF',entry:{type:'contribution',amount_rwf:100},snapshot:{basis:'cumulative_contributions',scope:'all_time',member_total_rwf:100,group_total_rwf:100,posted_at:now(),ledger_version:'one'}};
 assert.equal((await request('POST','/v1/events/ledger-snapshot',a.token,body)).status,202);
 assert.equal((await request('POST','/v1/events/ledger-snapshot',a.token,{...body,entry:{type:'contribution',amount_rwf:101}})).status,409);
 await db.prepare("UPDATE ledger_notification_events SET facts_json='{}',redacted_at=? WHERE event_id='ledger-one'").bind(now()).run();
 assert.equal((await request('POST','/v1/events/ledger-snapshot',a.token,body)).status,202);
 assert.equal((await request('POST','/v1/events/ledger-snapshot',a.token,{...body,recipient:'+250788000002'})).status,409);
});
test('callback outbox records message transitions and generation cancels old obligations',async()=>{
 const a=await appCredential();
 const localRequest=async(path:string,body:unknown)=>directApp.fetch(new Request('http://localhost'+path,{method:'POST',headers:{Authorization:'Bearer '+ADMIN,'Content-Type':'application/json'},body:JSON.stringify(body)}),{...environment,DB:db,CALLBACK_ALLOWED_HOSTS:'hooks.example.invalid',CALLBACK_ENCRYPTION_KEY:'a'.repeat(64)},{props:{},waitUntil(){},passThroughOnException(){}});
 const response=await localRequest('/v1/admin/callbacks',{application_id:a.id,url:'https://hooks.example.invalid/events'});assert.equal(response.status,201);const configured=await response.json();
 const job=await send(a.token);await db.prepare("UPDATE messages SET state='cancelled' WHERE message_id=?").bind(job.body.message_id).run();
 assert.equal((await db.prepare('SELECT count(*) AS n FROM webhook_deliveries').first()).n,2);
 const rotated=await localRequest('/v1/admin/callbacks',{application_id:a.id,url:'https://hooks.example.invalid/events'});assert.equal(rotated.status,201);
 assert.equal((await db.prepare("SELECT count(*) AS n FROM webhook_deliveries WHERE state='cancelled'").first()).n,2);
 assert.equal((await db.prepare('SELECT generation FROM webhook_endpoints WHERE endpoint_id=?').bind(configured.endpoint_id).first()).generation,2);
});
async function request(
  method: string,
  path: string,
  token?: string,
  body?: unknown,
  key?: string,
) {
  const headers: Record<string, string> = {};
  if (token) headers.Authorization = `Bearer ${token}`;
  if (body !== undefined) headers["Content-Type"] = "application/json";
  if (key) headers["Idempotency-Key"] = key;
  const response = await mf.dispatchFetch(`http://localhost${path}`, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  return { status: response.status, body: (await response.json()) as any };
}
async function appCredential(
  allowed = ["otp", "receipt", "operation", "campaign"],
  scopes?: string[],
) {
  const result = await request("POST", "/v1/admin/applications", ADMIN, {
    name: "Test application",
    allowed_kinds: allowed,
    ...(scopes ? { scopes } : {}),
  });
  assert.equal(result.status, 201, JSON.stringify(result.body));
  return {
    id: result.body.application_id as string,
    token: result.body.application_token as string,
  };
}
async function deviceCredential(
  allowed = ["otp", "receipt", "operation", "campaign"],
) {
  const result = await request("POST", "/v1/admin/devices", ADMIN, {
    name: "Test phone",
    allowed_kinds: allowed,
    sim_slot: 0,
  });
  assert.equal(result.status, 201, JSON.stringify(result.body));
  const token = result.body.device_token as string;
  assert.equal(
    (
      await request("POST", "/v1/device/registration", token, {
        ready: true,
        sim_slot: 0,
        app_version: "test",
        os_version: "test",
      })
    ).status,
    200,
  );
  return { id: result.body.installation_id as string, token };
}
async function send(
  token: string,
  extra: Record<string, unknown> = {},
  key: string = crypto.randomUUID(),
) {
  return request(
    "POST",
    "/v1/messages",
    token,
    {
      kind: "receipt",
      to: "+250788000001",
      text: "Collect test receipt",
      not_after: future(),
      ...extra,
    },
    key,
  );
}
async function pull(token: string) {
  const result = await request("GET", "/v1/device/jobs?limit=10", token);
  assert.equal(result.status, 200, JSON.stringify(result.body));
  return result.body;
}
async function event(
  token: string,
  job: any,
  type: string,
  extra: Record<string, unknown> = {},
) {
  const payload = {
    event_id: crypto.randomUUID(),
    message_id: job.message_id,
    assignment_version: job.assignment_version,
    type,
    at: now(),
    ...extra,
  };
  const result = await request("POST", "/v1/device/events", token, {
    events: [payload],
  });
  return { ...result, event: payload };
}
async function state(id: string) {
  return (
    await db
      .prepare("SELECT state FROM messages WHERE message_id=?")
      .bind(id)
      .first()
  ).state;
}
async function otp(token: string, phone = "+250788000001", purpose = "login") {
  const result = await request("POST", "/v1/otp/challenges", token, {
    phone,
    purpose,
  });
  assert.equal(result.status, 201, JSON.stringify(result.body));
  const stored = await db
    .prepare("SELECT text FROM messages WHERE otp_challenge_id=?")
    .bind(result.body.challenge_id)
    .first();
  const code = stored.text.match(/\b(\d{6})\b/)[1] as string;
  assert.ok(
    !JSON.stringify(result.body).includes(code),
    "creation must not expose the code",
  );
  return { ...result.body, code };
}

test("auth scopes, application isolation and production HTTPS boundary", async () => {
  assert.equal((await request("GET", "/v1/admin/overview")).status, 401);
  assert.deepEqual(
    (await request("GET", "/v1/admin/overview", ADMIN)).body.devices,
    { total: 0, ready: 0, revoked: 0 },
  );
  const a = await appCredential(
      ["receipt"],
      ["messages:write", "messages:read"],
    ),
    b = await appCredential(),
    d = await deviceCredential(["receipt"]);
  assert.equal(
    (await request("GET", "/v1/admin/overview", a.token)).status,
    403,
  );
  assert.equal(
    (
      await request("POST", "/v1/otp/challenges", a.token, {
        phone: "+250788000001",
        purpose: "login",
      })
    ).status,
    403,
  );
  assert.equal(
    (await request("POST", "/v1/events/contribution-posted", d.token, {}))
      .status,
    403,
  );
  const message = await send(a.token);
  assert.equal(message.status, 202);
  assert.equal(
    (await request("GET", `/v1/messages/${message.body.message_id}`, b.token))
      .status,
    404,
  );
  assert.equal(
    (
      await request("POST", "/v1/device/registration", d.token, {
        ready: true,
        allowed_kinds: ["otp"],
      })
    ).status,
    403,
  );
  assert.equal(
    (
      await request("POST", "/v1/device/registration", d.token, {
        ready: true,
        sim_slot: 1,
      })
    ).status,
    409,
  );
  assert.equal(
    (await mf.dispatchFetch("http://untrusted.example/health")).status,
    403,
  );
  assert.equal(
    (
      await mf.dispatchFetch("https://worker.example/health", {
        headers: { Origin: "https://untrusted.example" },
      })
    ).status,
    403,
  );
});
test("concurrent immutable message requests create one durable job", async () => {
  const a = await appCredential(),
    body = {
      kind: "receipt",
      to: "+250788000001",
      text: "RWF 5,000 received",
      not_after: future(),
    };
  const replies = await Promise.all(
    Array.from({ length: 12 }, () =>
      request("POST", "/v1/messages", a.token, body, "one-event"),
    ),
  );
  replies.forEach((r) => assert.equal(r.status, 202, JSON.stringify(r.body)));
  assert.equal(new Set(replies.map((r) => r.body.message_id)).size, 1);
  assert.equal(
    (await db.prepare("SELECT COUNT(*) AS n FROM messages").first()).n,
    1,
  );
  assert.equal(
    (
      await request(
        "POST",
        "/v1/messages",
        a.token,
        { ...body, text: "Changed amount" },
        "one-event",
      )
    ).status,
    409,
  );
});
test("contribution facts remain frozen across duplicate delivery and recipients", async () => {
  const a = await appCredential(),
    facts = {
      event_id: "payment-42",
      recipient: "+250788000001",
      group_id: "group-one",
      group_name: "Umucyo",
      amount_rwf: 5000,
      member_total_rwf: 35000,
      group_total_rwf: 240000,
      scope: "current cycle",
      ledger_version: 1842,
      recorded_at: now(),
      locale: "en",
    };
  const replies = await Promise.all(
    Array.from({ length: 8 }, () =>
      request("POST", "/v1/events/contribution-posted", a.token, facts),
    ),
  );
  replies.forEach((r) => assert.equal(r.status, 202, JSON.stringify(r.body)));
  const id = replies[0]!.body.message_id;
  assert.equal(
    (await db.prepare("SELECT COUNT(*) AS n FROM messages").first()).n,
    1,
  );
  assert.equal(
    (
      await request("POST", "/v1/events/contribution-posted", a.token, {
        ...facts,
        group_total_rwf: 999999,
      })
    ).status,
    409,
  );
  assert.equal(
    (
      await request("POST", "/v1/events/contribution-posted", a.token, {
        ...facts,
        recipient: "+250788000002",
        group_total_rwf: 999999,
      })
    ).status,
    409,
  );
  assert.equal(
    (
      await request("POST", "/v1/events/contribution-posted", a.token, {
        ...facts,
        recipient: "+250788000002",
      })
    ).status,
    202,
  );
  const row = await db
    .prepare("SELECT text,metadata_json FROM messages WHERE message_id=?")
    .bind(id)
    .first();
  assert.match(row.text, /240,000/);
  assert.equal(JSON.parse(row.metadata_json).ledger_version, 1842);
  assert.equal(
    (await db.prepare("SELECT COUNT(*) AS n FROM contribution_events").first())
      .n,
    1,
  );
});
test("challenge, current generation and OTP outbox roll back together on enqueue failure", async () => {
  const a = await appCredential();
  await owner.unsafe("CREATE OR REPLACE FUNCTION collect_sms.test_reject_otp() RETURNS trigger LANGUAGE plpgsql AS $$BEGIN IF NEW.kind='otp' THEN RAISE EXCEPTION 'injected_enqueue_failure'; END IF; RETURN NEW; END$$");
  await owner.unsafe('CREATE TRIGGER test_reject_otp BEFORE INSERT ON collect_sms.messages FOR EACH ROW EXECUTE FUNCTION collect_sms.test_reject_otp()');
  try {
    assert.equal(
      (
        await request("POST", "/v1/otp/challenges", a.token, {
          phone: "+250788000001",
          purpose: "login",
        })
      ).status,
      500,
    );
    for (const table of ["otp_slots", "otp_challenges", "messages"])
      assert.equal(
        (await db.prepare(`SELECT COUNT(*) AS n FROM ${table}`).first()).n,
        0,
      );
  } finally {
    await owner.unsafe('DROP TRIGGER test_reject_otp ON collect_sms.messages');
  }
  assert.ok((await otp(a.token)).challenge_id);
});
test("concurrent challenge requests obey cooldown without orphan messages", async () => {
  const a = await appCredential();
  const replies = await Promise.all(
    Array.from({ length: 10 }, () =>
      request("POST", "/v1/otp/challenges", a.token, {
        phone: "+250788000001",
        purpose: "login",
      }),
    ),
  );
  assert.equal(replies.filter((r) => r.status === 201).length, 1);
  assert.equal(replies.filter((r) => r.status === 429).length, 9);
  for (const table of ["otp_slots", "otp_challenges", "messages"])
    assert.equal(
      (await db.prepare(`SELECT COUNT(*) AS n FROM ${table}`).first()).n,
      1,
    );
});
test("current OTP is consumed exactly once by concurrent correct verification", async () => {
  const a = await appCredential(),
    challenge = await otp(a.token);
  const replies = await Promise.all(
    Array.from({ length: 10 }, () =>
      request("POST", "/v1/otp/verify", a.token, {
        challenge_id: challenge.challenge_id,
        code: challenge.code,
      }),
    ),
  );
  assert.equal(replies.filter((r) => r.status === 200).length, 1);
  assert.equal(replies.filter((r) => r.status === 400).length, 9);
  const success = replies.find((r) => r.status === 200)!.body;
  assert.equal(success.verified, true);
  assert.equal(success.phone, "+250788000001");
  assert.equal(success.purpose, "login");
  assert.equal(success.session, undefined);
  assert.equal(success.code, undefined);
  const record = await db
    .prepare(
      "SELECT verifier,consumed_at FROM otp_challenges WHERE challenge_id=?",
    )
    .bind(challenge.challenge_id)
    .first();
  assert.match(record.verifier, /^[a-f0-9]{64}$/);
  assert.ok(record.consumed_at);
});
test("wrong-code concurrency cannot exceed the attempt budget; expired codes fail", async () => {
  const a = await appCredential(),
    challenge = await otp(a.token),
    wrong = challenge.code === "000000" ? "000001" : "000000";
  const attempts = await Promise.all(
    Array.from({ length: 10 }, () =>
      request("POST", "/v1/otp/verify", a.token, {
        challenge_id: challenge.challenge_id,
        code: wrong,
      }),
    ),
  );
  attempts.forEach((r) => assert.equal(r.status, 400));
  assert.equal(
    (
      await db
        .prepare(
          "SELECT remaining_attempts FROM otp_challenges WHERE challenge_id=?",
        )
        .bind(challenge.challenge_id)
        .first()
    ).remaining_attempts,
    0,
  );
  assert.equal(
    (
      await request("POST", "/v1/otp/verify", a.token, {
        challenge_id: challenge.challenge_id,
        code: challenge.code,
      })
    ).status,
    400,
  );
  const other = await otp(a.token, "+250788000002");
  await db
    .prepare("UPDATE otp_challenges SET expires_at=? WHERE challenge_id=?")
    .bind("2020-01-01T00:00:00.000Z", other.challenge_id)
    .run();
  assert.equal(
    (
      await request("POST", "/v1/otp/verify", a.token, {
        challenge_id: other.challenge_id,
        code: other.code,
      })
    ).status,
    400,
  );
});
test("resend invalidates an in-flight generation without pretending to recall its SMS", async () => {
  const a = await appCredential(),
    d = await deviceCredential(["otp"]),
    old = await otp(a.token),
    job = (await pull(d.token)).jobs[0];
  assert.equal(
    (
      await event(d.token, job, "handoff_started", {
        attempt_id: "old-attempt",
        parts_total: 1,
      })
    ).status,
    200,
  );
  await db
    .prepare("UPDATE otp_slots SET resend_after=?")
    .bind("2020-01-01T00:00:00.000Z")
    .run();
  const fresh = await otp(a.token);
  assert.equal(await state(job.message_id), "handoff_started");
  assert.equal(
    (
      await db
        .prepare("SELECT cancel_requested FROM messages WHERE message_id=?")
        .bind(job.message_id)
        .first()
    ).cancel_requested,
    1,
  );
  assert.equal(
    (
      await request("POST", "/v1/otp/verify", a.token, {
        challenge_id: old.challenge_id,
        code: old.code,
      })
    ).status,
    400,
  );
  assert.equal(
    (
      await event(d.token, job, "part_sent", {
        attempt_id: "old-attempt",
        part_index: 0,
        parts_total: 1,
      })
    ).status,
    200,
  );
  assert.equal(await state(job.message_id), "sent");
  assert.equal(
    (
      await request("POST", "/v1/otp/verify", a.token, {
        challenge_id: fresh.challenge_id,
        code: fresh.code,
      })
    ).status,
    200,
  );
});
test("changing purpose cannot bypass the per-phone issuance budget", async () => {
  const a = await appCredential();
  for (let i = 0; i < 6; i++)
    assert.equal(
      (
        await request("POST", "/v1/otp/challenges", a.token, {
          phone: "+250788000001",
          purpose: `purpose-${i}`,
        })
      ).status,
      201,
    );
  assert.equal(
    (
      await request("POST", "/v1/otp/challenges", a.token, {
        phone: "+250788000001",
        purpose: "purpose-7",
      })
    ).status,
    429,
  );
  for (const table of ["otp_challenges", "messages"])
    assert.equal(
      (await db.prepare(`SELECT COUNT(*) AS n FROM ${table}`).first()).n,
      6,
    );
});
test("lost acceptance reoffers the same owner; another phone cannot steal or acknowledge", async () => {
  const a = await appCredential(),
    d1 = await deviceCredential(["receipt"]),
    d2 = await deviceCredential(["receipt"]);
  assert.equal((await send(a.token)).status, 202);
  const [one, two] = await Promise.all([pull(d1.token), pull(d2.token)]);
  assert.equal(one.jobs.length + two.jobs.length, 1);
  const owner = one.jobs.length ? d1 : d2,
    other = one.jobs.length ? d2 : d1,
    job = one.jobs[0] ?? two.jobs[0];
  assert.equal(job.payload_digest, await payloadDigest(job));
  assert.equal((await pull(owner.token)).jobs[0].message_id, job.message_id);
  assert.equal((await pull(other.token)).jobs.length, 0);
  const acceptance = {
    message_id: job.message_id,
    payload_digest: job.payload_digest,
    assignment_version: job.assignment_version,
    accepted_at: now(),
  };
  assert.equal(
    (
      await request("POST", "/v1/device/acceptances", other.token, {
        acceptances: [acceptance],
      })
    ).status,
    403,
  );
  assert.equal(
    (
      await request("POST", "/v1/device/acceptances", owner.token, {
        acceptances: [{ ...acceptance, payload_digest: "0".repeat(64) }],
      })
    ).status,
    403,
  );
  for (let i = 0; i < 2; i++)
    assert.equal(
      (
        await request("POST", "/v1/device/acceptances", owner.token, {
          acceptances: [acceptance],
        })
      ).status,
      200,
    );
  assert.equal(
    (await db.prepare("SELECT COUNT(*) AS n FROM acceptances").first()).n,
    1,
  );
  await db
    .prepare("UPDATE devices SET last_seen_at=? WHERE installation_id=?")
    .bind("2020-01-01T00:00:00.000Z", owner.id)
    .run();
  assert.equal((await pull(other.token)).jobs.length, 0);
});
test("wrong-owner or conflicting event batches roll back all effects", async () => {
  const a = await appCredential(),
    d = await deviceCredential(["receipt"]),
    other = await deviceCredential(["receipt"]);
  await send(a.token);
  const job = (await pull(d.token)).jobs[0];
  assert.equal(
    (
      await event(other.token, job, "handoff_started", {
        attempt_id: "attempt",
        parts_total: 2,
      })
    ).status,
    403,
  );
  const valid = {
      event_id: "one",
      message_id: job.message_id,
      assignment_version: 1,
      type: "handoff_started",
      at: now(),
      attempt_id: "attempt",
      parts_total: 2,
    },
    invalid = { ...valid, event_id: "two", parts_total: 3 };
  assert.equal(
    (
      await request("POST", "/v1/device/events", d.token, {
        events: [valid, invalid],
      })
    ).status,
    409,
  );
  for (const table of ["device_events", "attempts"])
    assert.equal(
      (await db.prepare(`SELECT COUNT(*) AS n FROM ${table}`).first()).n,
      0,
    );
});
test("multipart callbacks are replay safe and one delivered part is not a delivered message", async () => {
  const a = await appCredential(),
    d = await deviceCredential(["receipt"]);
  await send(a.token);
  const job = (await pull(d.token)).jobs[0];
  const first = await event(d.token, job, "part_delivered", {
    attempt_id: "attempt",
    part_index: 1,
    parts_total: 2,
    detail: { phase: "delivery" },
  });
  assert.equal(first.status, 200);
  assert.equal(await state(job.message_id), "partial");
  assert.equal(
    (
      await event(d.token, job, "handoff_started", {
        attempt_id: "attempt",
        parts_total: 2,
      })
    ).status,
    200,
  );
  assert.equal(
    (
      await event(d.token, job, "part_sent", {
        attempt_id: "attempt",
        part_index: 0,
        parts_total: 2,
      })
    ).status,
    200,
  );
  assert.equal(await state(job.message_id), "sent");
  assert.equal(
    (await event(d.token, job, "outcome_unknown", { attempt_id: "attempt" }))
      .status,
    200,
  );
  assert.equal(await state(job.message_id), "sent");
  assert.equal(
    (
      await request("POST", "/v1/device/events", d.token, {
        events: [first.event],
      })
    ).status,
    200,
  );
  assert.equal(
    (
      await request("POST", "/v1/device/events", d.token, {
        events: [{ ...first.event, part_index: 0 }],
      })
    ).status,
    409,
  );
  assert.equal(
    (
      await event(d.token, job, "part_delivered", {
        attempt_id: "attempt",
        part_index: 0,
        parts_total: 2,
      })
    ).status,
    200,
  );
  assert.equal(await state(job.message_id), "delivered");
  assert.equal(
    (
      await event(d.token, job, "part_sent", {
        attempt_id: "attempt",
        part_index: 2,
      })
    ).status,
    409,
  );
});
test("delivery failure and unknown evidence are distinct from Android submission success", async () => {
  const a = await appCredential(),
    d = await deviceCredential(["receipt"]);
  await send(a.token);
  const job = (await pull(d.token)).jobs[0];
  await event(d.token, job, "handoff_started", {
    attempt_id: "attempt",
    parts_total: 2,
  });
  for (let i = 0; i < 2; i++)
    await event(d.token, job, "part_sent", {
      attempt_id: "attempt",
      part_index: i,
    });
  await event(d.token, job, "outcome_unknown", {
    attempt_id: "attempt",
    part_index: 0,
    detail: { phase: "delivery" },
    error_code: "DELIVERY_PDU_MISSING_OR_INVALID",
  });
  assert.equal(await state(job.message_id), "delivery_unconfirmed");
  await event(d.token, job, "part_failed", {
    attempt_id: "attempt",
    part_index: 0,
    detail: { phase: "delivery" },
    error_code: "DELIVERY_STATUS_64",
  });
  assert.equal(await state(job.message_id), "partial");
  await event(d.token, job, "part_failed", {
    attempt_id: "attempt",
    part_index: 1,
    detail: { phase: "delivery" },
    error_code: "DELIVERY_STATUS_64",
  });
  assert.equal(await state(job.message_id), "failed");
  for (let i = 0; i < 2; i++)
    await event(d.token, job, "part_delivered", {
      attempt_id: "attempt",
      part_index: i,
    });
  assert.equal(await state(job.message_id), "delivered");
});
test("cancel and handoff transitions cannot both certify success", async () => {
  const a = await appCredential(),
    d = await deviceCredential(["receipt"]);
  await send(a.token);
  const job = (await pull(d.token)).jobs[0],
    cancel = await request(
      "POST",
      `/v1/messages/${job.message_id}/cancel`,
      a.token,
    );
  assert.equal(cancel.body.cancellation, "cancel_requested");
  const replies = await Promise.all([
    event(d.token, job, "cancelled"),
    event(d.token, job, "handoff_started", {
      attempt_id: "attempt",
      parts_total: 1,
    }),
  ]);
  assert.deepEqual(replies.map((r) => r.status).sort(), [200, 409]);
  if ((await state(job.message_id)) === "handoff_started")
    assert.equal((await event(d.token, job, "expired")).status, 409);
  else assert.equal(await state(job.message_id), "cancelled");
});
test("documented pre-call abort resolves a marker but cannot erase unknown evidence", async () => {
  const a = await appCredential(),
    d = await deviceCredential(["receipt"]);
  await send(a.token);
  const job = (await pull(d.token)).jobs[0];
  await event(d.token, job, "handoff_started", {
    attempt_id: "attempt",
    parts_total: 1,
  });
  assert.equal(
    (await event(d.token, job, "expired", { attempt_id: "attempt" })).status,
    409,
  );
  assert.equal(
    (
      await event(d.token, job, "expired", {
        attempt_id: "attempt",
        error_code: "DEADLINE_BEFORE_CALL",
      })
    ).status,
    200,
  );
  assert.equal(await state(job.message_id), "expired");
  assert.equal(
    (
      await event(d.token, job, "handoff_started", {
        attempt_id: "another",
        parts_total: 1,
      })
    ).status,
    409,
  );
  await send(a.token);
  const next = (await pull(d.token)).jobs[0];
  await event(d.token, next, "handoff_started", {
    attempt_id: "other",
    parts_total: 1,
  });
  await event(d.token, next, "outcome_unknown", { attempt_id: "other" });
  assert.equal(
    (
      await event(d.token, next, "failed", {
        attempt_id: "other",
        error_code: "ABORTED_BEFORE_CALL",
      })
    ).status,
    409,
  );
  assert.equal(await state(next.message_id), "outcome_unknown");
});
test("campaign drafts do not send; permits share an atomic segment budget and pause immediately", async () => {
  const a = await appCredential(),
    d = await deviceCredential(["campaign"]);
  const draft = await request(
    "POST",
    "/v1/campaigns",
    a.token,
    {
      name: "Campaign",
      text: "Collect update",
      recipients: ["+250788000001", "+250788000002", "+250788000001"],
      not_after: future(),
      segments_per_minute: 1,
    },
    "draft-key",
  );
  assert.equal(draft.status, 201);
  assert.equal(draft.body.recipient_count, 2);
  assert.equal((await pull(d.token)).jobs.length, 0);
  const id = draft.body.campaign_id;
  assert.equal(
    (await request("POST", `/v1/campaigns/${id}/start`, a.token)).status,
    200,
  );
  const jobs = (await pull(d.token)).jobs;
  assert.equal(jobs.length, 2);
  const permits = await Promise.all(
    jobs.map((j: any) =>
      request("GET", `/v1/device/messages/${j.message_id}/permit`, d.token),
    ),
  );
  assert.equal(permits.filter((p) => p.body.allowed).length, 1);
  const allowedJob = jobs[permits.findIndex((p) => p.body.allowed)];
  assert.equal(
    (
      await request(
        "GET",
        `/v1/device/messages/${allowedJob.message_id}/permit`,
        d.token,
      )
    ).body.allowed,
    true,
  );
  assert.equal(
    (
      await db
        .prepare(
          "SELECT used_segments FROM campaign_budget WHERE campaign_id=?",
        )
        .bind(id)
        .first()
    ).used_segments,
    1,
  );
  await request("POST", `/v1/campaigns/${id}/pause`, a.token);
  assert.equal(
    (
      await request(
        "GET",
        `/v1/device/messages/${allowedJob.message_id}/permit`,
        d.token,
      )
    ).body.allowed,
    false,
  );
  await request("POST", `/v1/campaigns/${id}/resume`, a.token);
  assert.equal(
    (
      await request(
        "GET",
        `/v1/device/messages/${allowedJob.message_id}/permit`,
        d.token,
      )
    ).body.allowed,
    true,
  );
  await request("POST", `/v1/campaigns/${id}/cancel`, a.token);
  assert.equal((await pull(d.token)).jobs.length, 0);
  assert.equal(
    (
      await request(
        "GET",
        `/v1/device/messages/${allowedJob.message_id}/permit`,
        d.token,
      )
    ).body.allowed,
    false,
  );
});
test("dynamic operations fail closed without a fresh business eligibility decision", async () => {
  const a = await appCredential(),
    d = await deviceCredential(["operation"]),
    created = await send(a.token, {
      kind: "operation",
      text: "Payment is due.",
    });
  assert.equal(created.status, 202);
  const id = created.body.message_id;
  assert.equal((await pull(d.token)).jobs.length, 0);
  assert.equal(
    (
      await request("POST", `/v1/messages/${id}/eligibility`, a.token, {
        eligible: true,
        valid_until: future(30_000),
      })
    ).status,
    200,
  );
  assert.equal((await pull(d.token)).jobs.length, 1);
  assert.equal(
    (await request("GET", `/v1/device/messages/${id}/permit`, d.token)).body
      .allowed,
    true,
  );
  assert.equal(
    (
      await request("POST", `/v1/messages/${id}/eligibility`, a.token, {
        eligible: false,
      })
    ).status,
    200,
  );
  assert.equal(
    (await request("GET", `/v1/device/messages/${id}/permit`, d.token)).body
      .allowed,
    false,
  );
});
test("paused owned jobs retain ownership without blocking other eligible work", async () => {
  const a = await appCredential(),
    d = await deviceCredential(["receipt", "campaign"]),
    created = await request("POST", "/v1/campaigns", a.token, {
      name: "Paused work",
      text: "Campaign",
      recipients: ["+250788000001"],
      not_after: future(),
    }),
    id = created.body.campaign_id;
  await request("POST", `/v1/campaigns/${id}/start`, a.token);
  const first = await request("GET", "/v1/device/jobs?limit=1", d.token);
  assert.equal(first.body.jobs.length, 1);
  const held = first.body.jobs[0];
  await request("POST", `/v1/campaigns/${id}/pause`, a.token);
  const receipt = await send(a.token),
    next = await request("GET", "/v1/device/jobs?limit=1", d.token);
  assert.equal(next.body.jobs.length, 1);
  assert.equal(next.body.jobs[0].message_id, receipt.body.message_id);
  assert.equal(
    (
      await db
        .prepare(
          "SELECT owner_installation_id FROM messages WHERE message_id=?",
        )
        .bind(held.message_id)
        .first()
    ).owner_installation_id,
    d.id,
  );
});
test("token refresh is separate from identity; rotation and revocation preserve ownership history", async () => {
  const a = await appCredential(),
    d = await deviceCredential(["receipt"]);
  await send(a.token);
  const job = (await pull(d.token)).jobs[0];
  await request("POST", "/v1/device/registration", d.token, {
    ready: true,
    fcm_token: "first-push-registration",
  });
  await db
    .prepare(
      "UPDATE devices SET fcm_last_error='UNREGISTERED' WHERE installation_id=?",
    )
    .bind(d.id)
    .run();
  await request("POST", "/v1/device/registration", d.token, {
    ready: true,
    fcm_token: "new-push-registration",
  });
  const row = await db
    .prepare("SELECT * FROM devices WHERE installation_id=?")
    .bind(d.id)
    .first();
  assert.equal(row.fcm_last_error, null);
  assert.equal(row.fcm_token, "new-push-registration");
  const listed = (await request("GET", "/v1/admin/devices", ADMIN)).body
    .devices[0];
  assert.equal(listed.token_hash, undefined);
  assert.equal(listed.fcm_token, undefined);
  const rotated = await request(
    "POST",
    `/v1/admin/devices/${d.id}/rotate`,
    ADMIN,
  );
  assert.equal(rotated.status, 200);
  assert.equal((await request("GET", "/v1/device/jobs", d.token)).status, 401);
  assert.equal(
    (await request("GET", "/v1/device/jobs", rotated.body.device_token)).status,
    200,
  );
  assert.equal(
    (await request("POST", `/v1/admin/devices/${d.id}/revoke`, ADMIN)).status,
    200,
  );
  assert.equal(
    (await request("GET", "/v1/device/jobs", rotated.body.device_token)).status,
    401,
  );
  assert.equal(
    (
      await db
        .prepare(
          "SELECT owner_installation_id FROM messages WHERE message_id=?",
        )
        .bind(job.message_id)
        .first()
    ).owner_installation_id,
    d.id,
  );
});
test("campaign expansion resumes atomically with deterministic IDs and revocation stops work", async () => {
  const a = await appCredential(),
    recipients = Array.from(
      { length: 45 },
      (_, index) => `+25078800${String(index).padStart(4, "0")}`,
    ),
    created = await request(
      "POST",
      "/v1/campaigns",
      a.token,
      {
        name: "Frozen audience",
        text: "A contribution reminder.",
        recipients,
        not_after: future(),
      },
      "campaign-draft",
    );
  assert.equal(created.status, 201);
  const id = created.body.campaign_id;
  assert.equal(
    (await request("POST", `/v1/campaigns/${id}/start`, a.token)).status,
    200,
  );
  assert.equal(
    (
      await db
        .prepare("SELECT COUNT(*) AS n FROM messages WHERE campaign_id=?")
        .bind(id)
        .first()
    ).n,
    20,
  );
  const resumed = await Promise.all(
    Array.from({ length: 5 }, () =>
      request("POST", `/v1/campaigns/${id}/start`, a.token),
    ),
  );
  resumed.forEach((r) => assert.equal(r.status, 200));
  const count = (
      await db
        .prepare("SELECT COUNT(*) AS n FROM messages WHERE campaign_id=?")
        .bind(id)
        .first()
    ).n,
    cursor = (
      await db
        .prepare("SELECT expansion_cursor FROM campaigns WHERE campaign_id=?")
        .bind(id)
        .first()
    ).expansion_cursor;
  assert.equal(count, cursor);
  assert.ok(count >= 40 && count <= 45);
  assert.equal(
    (
      await db
        .prepare(
          "SELECT COUNT(DISTINCT to_number) AS n FROM messages WHERE campaign_id=?",
        )
        .bind(id)
        .first()
    ).n,
    count,
  );
  assert.equal(
    (await request("POST", `/v1/admin/applications/${a.id}/revoke`, ADMIN))
      .status,
    200,
  );
  assert.equal(
    (
      await db
        .prepare("SELECT status FROM campaigns WHERE campaign_id=?")
        .bind(id)
        .first()
    ).status,
    "cancelled",
  );
  assert.equal(
    (
      await db
        .prepare(
          "SELECT COUNT(*) AS n FROM messages WHERE campaign_id=? AND state<>'cancelled'",
        )
        .bind(id)
        .first()
    ).n,
    0,
  );
  assert.equal(
    (await request("POST", `/v1/admin/campaigns/${id}/start`, ADMIN)).status,
    409,
  );
});
test("an older FCM response cannot clear or back off a newer durable wake revision", async () => {
  const d = await deviceCredential(["receipt"]);
  await request("POST", "/v1/device/registration", d.token, {
    ready: true,
    fcm_token: "registration",
  });
  const key = generateKeyPairSync("rsa", { modulusLength: 2048 })
      .privateKey.export({ format: "pem", type: "pkcs8" })
      .toString(),
    env = {
      DB: db,
      ROOT_ADMIN_TOKEN: ADMIN,
      OTP_HMAC_KEY: "unused-in-test",
      FCM_ENABLED: "true",
      FCM_PROJECT_ID: `test-${crypto.randomUUID()}`,
      FCM_CLIENT_EMAIL: "wake@test.iam.gserviceaccount.com",
      FCM_PRIVATE_KEY: key,
    };
  let phase = 0;
  const fetcher = async (input: RequestInfo | URL) => {
    if (String(input).includes("oauth2.googleapis.com"))
      return Response.json({ access_token: "test-token", expires_in: 3600 });
    phase++;
    if (phase <= 2)
      await db
        .prepare(
          "UPDATE devices SET wake_revision=wake_revision+1,fcm_pending=1,fcm_next_at=? WHERE installation_id=?",
        )
        .bind(now(), d.id)
        .run();
    return phase === 1
      ? Response.json({ error: { status: "UNAVAILABLE" } }, { status: 503 })
      : Response.json({ name: "test-message" });
  };
  await flushWakeups(env, fetcher);
  let row = await db
    .prepare(
      "SELECT fcm_pending,fcm_attempts,fcm_last_error FROM devices WHERE installation_id=?",
    )
    .bind(d.id)
    .first();
  assert.deepEqual(row, {
    fcm_pending: 1,
    fcm_attempts: 0,
    fcm_last_error: null,
  });
  await flushWakeups(env, fetcher);
  row = await db
    .prepare("SELECT fcm_pending FROM devices WHERE installation_id=?")
    .bind(d.id)
    .first();
  assert.equal(row.fcm_pending, 1);
  await flushWakeups(env, fetcher);
  assert.equal(
    (
      await db
        .prepare("SELECT fcm_pending FROM devices WHERE installation_id=?")
        .bind(d.id)
        .first()
    ).fcm_pending,
    0,
  );
});
test("one part cannot count twice toward complete multipart failure", async () => {
  const a = await appCredential(),
    d = await deviceCredential(["receipt"]);
  await send(a.token);
  const job = (await pull(d.token)).jobs[0];
  await event(d.token, job, "handoff_started", {
    attempt_id: "attempt",
    parts_total: 2,
  });
  await event(d.token, job, "part_failed", {
    attempt_id: "attempt",
    part_index: 0,
    detail: { phase: "sent" },
  });
  await event(d.token, job, "part_failed", {
    attempt_id: "attempt",
    part_index: 0,
    detail: { phase: "delivery" },
  });
  assert.notEqual(await state(job.message_id), "failed");
  assert.equal(
    (
      await db
        .prepare(
          "SELECT failure_count FROM attempt_evidence WHERE message_id=?",
        )
        .bind(job.message_id)
        .first()
    ).failure_count,
    1,
  );
});
test("pre-call abort codes must match the declared terminal event", async () => {
  const a = await appCredential(),
    d = await deviceCredential(["receipt"]);
  await send(a.token);
  const job = (await pull(d.token)).jobs[0];
  assert.equal(
    (
      await event(d.token, job, "handoff_started", {
        attempt_id: "attempt",
        parts_total: 1,
        error_code: "ABORTED_BEFORE_CALL",
      })
    ).status,
    400,
  );
  assert.equal(
    (await db.prepare("SELECT COUNT(*) AS n FROM device_events").first()).n,
    0,
  );
});

test("chunked request bodies are bounded and cancelled without buffering the entire input", async () => {
  const a = await appCredential();
  let pulls = 0,
    cancelled = false;
  const stream = new ReadableStream<Uint8Array>({
    pull(controller) {
      pulls++;
      if (pulls <= 20) controller.enqueue(new Uint8Array(65536));
      else controller.close();
    },
    cancel() {
      cancelled = true;
    },
  });
  const req = new Request("https://worker.example/v1/messages", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${a.token}`,
      "Content-Type": "application/json",
      "Idempotency-Key": "oversized-stream",
    },
    body: stream,
    duplex: "half",
  } as RequestInit & { duplex: string });
  const response = await directApp.fetch(req, {
    DB: db,
    ROOT_ADMIN_TOKEN: ADMIN,
    OTP_HMAC_KEY: "unused-in-test",
    FCM_ENABLED: "false",
  });
  assert.equal(response.status, 413);
  assert.equal(((await response.json()) as any).error.code, "too_large");
  assert.equal(cancelled, true);
  assert.ok(pulls <= 7, `consumed ${pulls} chunks`);
  assert.equal(
    (await db.prepare("SELECT COUNT(*) AS n FROM messages").first()).n,
    0,
  );
});

test("production OTP admission rejects unavailable phones without creating a challenge or outbox", async () => {
  const a = await appCredential();
  const create = async () => {
    const response = await directApp.fetch(
      new Request("https://worker.example/v1/otp/challenges", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${a.token}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ phone: "+250788000001", purpose: "login" }),
      }),
      {
        DB: db,
        ROOT_ADMIN_TOKEN: ADMIN,
        OTP_HMAC_KEY: "test-hmac-key-0000000000000000000000000000000000000000",
        ENVIRONMENT: "production",
        FCM_ENABLED: "false",
      },
    );
    return { status: response.status, body: (await response.json()) as any };
  };
  const unavailable = async () => {
    const result = await create();
    assert.equal(result.status, 503, JSON.stringify(result.body));
    assert.equal(result.body.error.code, "otp_gateway_unavailable");
    for (const table of ["otp_challenges", "otp_slots", "messages"])
      assert.equal(
        (await db.prepare(`SELECT COUNT(*) AS n FROM ${table}`).first()).n,
        0,
      );
  };
  await unavailable();
  const d = await deviceCredential(["receipt"]);
  await unavailable(); // Fresh, but provisioned for another workload.
  await db
    .prepare(
      "UPDATE devices SET allowed_kinds='[\"otp\"]',ready=0 WHERE installation_id=?",
    )
    .bind(d.id)
    .run();
  await unavailable();
  await db
    .prepare(
      "UPDATE devices SET ready=1,last_seen_at=NULL WHERE installation_id=?",
    )
    .bind(d.id)
    .run();
  await unavailable();
  await db
    .prepare("UPDATE devices SET last_seen_at=? WHERE installation_id=?")
    .bind(future(-90_000), d.id)
    .run();
  await unavailable();
  await db
    .prepare(
      "UPDATE devices SET last_seen_at=?,revoked_at=? WHERE installation_id=?",
    )
    .bind(now(), now(), d.id)
    .run();
  await unavailable();
  await db
    .prepare(
      "UPDATE devices SET revoked_at=NULL,last_seen_at=? WHERE installation_id=?",
    )
    .bind(now(), d.id)
    .run();
  assert.equal((await create()).status, 201);
  for (const table of ["otp_challenges", "otp_slots", "messages"])
    assert.equal(
      (await db.prepare(`SELECT COUNT(*) AS n FROM ${table}`).first()).n,
      1,
    );
});

test("OTP availability defaults fail closed and can be explicitly configured for local tests", async () => {
  const a = await appCredential();
  const create = async (extra: Record<string, string>, p: string) => {
    const response = await directApp.fetch(
      new Request("https://worker.example/v1/otp/challenges", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${a.token}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ phone: p, purpose: "login" }),
      }),
      {
        DB: db,
        ROOT_ADMIN_TOKEN: ADMIN,
        OTP_HMAC_KEY: "test-hmac-key-0000000000000000000000000000000000000000",
        FCM_ENABLED: "false",
        ...extra,
      },
    );
    return response.status;
  };
  assert.equal(await create({}, "+250788000001"), 503);
  assert.equal(
    await create(
      { ENVIRONMENT: "development", OTP_REQUIRE_READY_GATEWAY: "true" },
      "+250788000001",
    ),
    503,
  );
  assert.equal(
    await create({ ENVIRONMENT: "development" }, "+250788000001"),
    201,
  );
  assert.equal(
    await create(
      { ENVIRONMENT: "production", OTP_REQUIRE_READY_GATEWAY: "false" },
      "+250788000002",
    ),
    201,
  );
});

test("ordinary registration heartbeats preserve push state and concurrent token registration rearms once", async () => {
  const d = await deviceCredential(["receipt"]);
  const snapshot = () =>
    db
      .prepare(
        "SELECT fcm_token,fcm_pending,fcm_attempts,fcm_next_at,fcm_last_error,wake_revision FROM devices WHERE installation_id=?",
      )
      .bind(d.id)
      .first();
  const register = (fcm?: string | null) =>
    request("POST", "/v1/device/registration", d.token, {
      ready: true,
      ...(fcm === undefined ? {} : { fcm_token: fcm }),
    });
  const initial = await snapshot();
  assert.equal(initial.fcm_pending, 0);
  assert.equal(initial.wake_revision, 0);
  await register();
  assert.deepEqual(await snapshot(), initial);
  const both = await Promise.all([
    register("push-token"),
    register("push-token"),
  ]);
  both.forEach((r) => assert.equal(r.status, 200, JSON.stringify(r.body)));
  const registered = await snapshot();
  assert.equal(registered.fcm_token, "push-token");
  assert.equal(registered.fcm_pending, 1);
  assert.equal(registered.wake_revision, 1);
  await db
    .prepare(
      "UPDATE devices SET fcm_pending=0,fcm_next_at=NULL WHERE installation_id=?",
    )
    .bind(d.id)
    .run();
  const idle = await snapshot();
  await register("push-token");
  await register();
  assert.deepEqual(await snapshot(), idle);
  await db
    .prepare(
      "UPDATE devices SET fcm_pending=1,fcm_attempts=3,fcm_next_at=?,fcm_last_error='FCM_HTTP_503' WHERE installation_id=?",
    )
    .bind(future(60_000), d.id)
    .run();
  const backoff = await snapshot();
  await register("push-token");
  await register();
  assert.deepEqual(await snapshot(), backoff);
  await register(null);
  const cleared = await snapshot();
  assert.equal(cleared.fcm_token, null);
  assert.equal(cleared.fcm_pending, 0);
  assert.equal(cleared.fcm_next_at, null);
  assert.equal(cleared.fcm_attempts, 0);
  assert.equal(cleared.fcm_last_error, null);
  assert.equal(cleared.wake_revision, 2);
  // A new message may mark a no-token device pending; an explicit clear still clears it.
  await db
    .prepare("UPDATE devices SET fcm_pending=1 WHERE installation_id=?")
    .bind(d.id)
    .run();
  await register(null);
  assert.equal((await snapshot()).fcm_pending, 0);
});

test("a retired FCM token stays rejected across heartbeats and a different token recovers", async () => {
  const d = await deviceCredential(["receipt"]);
  const register = (fcm?: string | null) =>
    request("POST", "/v1/device/registration", d.token, {
      ready: true,
      ...(fcm === undefined ? {} : { fcm_token: fcm }),
    });
  const snapshot = () =>
    db
      .prepare(
        "SELECT fcm_token,fcm_rejected_token_hash,fcm_pending,fcm_next_at,fcm_attempts,fcm_last_error,wake_revision FROM devices WHERE installation_id=?",
      )
      .bind(d.id)
      .first();
  await register("retired-token");
  const pem = generateKeyPairSync("rsa", { modulusLength: 2048 })
    .privateKey.export({ format: "pem", type: "pkcs8" })
    .toString();
  await flushWakeups(
    {
      DB: db,
      ROOT_ADMIN_TOKEN: ADMIN,
      OTP_HMAC_KEY: "unused-in-test",
      FCM_ENABLED: "true",
      FCM_PROJECT_ID: `test-${crypto.randomUUID()}`,
      FCM_CLIENT_EMAIL: "wake@test.iam.gserviceaccount.com",
      FCM_PRIVATE_KEY: pem,
    },
    async (input) =>
      String(input).includes("oauth2.googleapis.com")
        ? Response.json({ access_token: "test-token", expires_in: 3600 })
        : Response.json(
            { error: { details: [{ errorCode: "UNREGISTERED" }] } },
            { status: 404 },
          ),
  );
  const rejected = await snapshot();
  assert.equal(rejected.fcm_token, null);
  assert.equal(
    rejected.fcm_rejected_token_hash,
    createHash("sha256").update("retired-token").digest("hex"),
  );
  assert.equal(rejected.fcm_pending, 0);
  assert.equal(rejected.fcm_next_at, null);
  assert.equal(rejected.fcm_last_error, "UNREGISTERED");
  assert.equal((await register("retired-token")).body.fcm_token_rejected, true);
  assert.equal((await register("retired-token")).body.fcm_token_rejected, true);
  await register();
  await register(null);
  assert.deepEqual(await snapshot(), rejected);
  const recovered = await register("fresh-token");
  assert.equal(recovered.body.fcm_token_rejected, false);
  const fresh = await snapshot();
  assert.equal(fresh.fcm_token, "fresh-token");
  assert.equal(fresh.fcm_rejected_token_hash, null);
  assert.equal(fresh.fcm_pending, 1);
  assert.equal(fresh.fcm_attempts, 0);
  assert.equal(fresh.fcm_last_error, null);
  assert.equal(fresh.wake_revision, rejected.wake_revision + 1);
});
