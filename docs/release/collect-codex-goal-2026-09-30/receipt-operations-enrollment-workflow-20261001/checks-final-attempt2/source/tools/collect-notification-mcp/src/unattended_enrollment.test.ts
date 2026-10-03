import test from "node:test";
import assert from "node:assert/strict";
import {generateKeyPairSync, sign} from "node:crypto";
import {spawnSync} from "node:child_process";
import {mkdtemp, realpath, writeFile, chmod, readFile, readdir, symlink, link} from "node:fs/promises";
import {tmpdir} from "node:os";
import {join} from "node:path";
import {EnrollmentJournal} from "./unattended_enrollment_journal.ts";
import {EnrollmentPreparation} from "./unattended_enrollment.ts";
import {enrollmentCliOptions} from "./unattended_enroll_cli.ts";
import {enrollmentOwner, enrollmentOwnerRpc} from "./unattended_enrollment_owner.ts";
import {publicKeyMetadata, sha256, validReceipt, validLookup, validIdentityObservation, validDirectory, sameInstant, enrollmentOrigin} from "./unattended_enrollment_contract.ts";
import type {EnrollmentIntent, EnrollmentReceipt, PublicKeyMetadata} from "./unattended_enrollment_contract.ts";
import type {OwnerRpc} from "./unattended_enrollment_owner.ts";
import {verifyHelper, publishEnrollmentProfile, validateInstalledEnrollmentProfile, createEnrollmentKey, readEnrollmentKey} from "./unattended_profile_preparation.ts";
import {loadUnattendedProfile} from "./unattended_profile.ts";
import type {UnattendedProfile} from "./unattended_profile.ts";
import {unattendedScope} from "./unattended_contract.ts";
import {createSupervisorHandler} from "../../../supabase/functions/collect-receipt-supervisor/handler.ts";
import {revokePreparedIdentity, localEnrollmentStatus} from "./unattended_revocation.ts";
import {unattendedKeychainSigner} from "./unattended_client.ts";

const id = (n: number) => `99810000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const at = Date.parse("2026-10-01T13:00:00Z"), now = () => at;
const iso = (ms: number) => new Date(ms).toISOString();
const key = generateKeyPairSync("ec", {namedCurve: "prime256v1"}).publicKey.export({type: "spki", format: "der"});
const metadata: PublicKeyMetadata = {contract_version: 2, scope: unattendedScope, public_key_spki_base64: key.toString("base64"), key_sha256: sha256(key)};
const expiry = iso(at + 86_400_000);
const intent = (request = id(1), action: "enroll" | "activate" = "enroll"): EnrollmentIntent => ({action, request_id: request, key_sha256: metadata.key_sha256,
  request_expires_at: iso(at + 90_000), public_key_spki_base64: action === "enroll" ? metadata.public_key_spki_base64 : null, principal_id: action === "activate" ? id(9) : null, identity_expires_at: expiry});
const receipt = (input = intent()): EnrollmentReceipt => ({contract_version: 3, action: input.action, request_id: input.request_id, principal_id: id(9),
  state_at_action: input.action === "enroll" ? "pending" : "active", scope: unattendedScope, key_sha256: metadata.key_sha256,
  identity_expires_at: expiry.replace(".000Z", ".000000Z"), recorded_at: iso(at), request_expires_at: input.request_expires_at.replace(".000Z", ".000000Z")});
const observation = (state: "pending" | "active" | "revoked" = "active", ms = at) => ({contract_version: 3, checked_at: iso(ms), sample_valid_until: iso(ms + 60_000), found: true,
  identity: {principal_id: id(9), key_sha256: metadata.key_sha256, state, scope: unattendedScope, created_at: iso(at - 1000), expires_at: expiry.replace(".000Z", ".000000Z"),
    activated_at: state === "pending" ? null : iso(at), revoked_at: state === "revoked" ? iso(at) : null}});
const lookup = (status: "recorded" | "not_recorded" | "in_progress", ms = at, input = intent()) => ({contract_version: 3, request_id: input.request_id,
  action: status === "recorded" ? input.action : null, status, checked_at: iso(ms), sample_valid_until: iso(ms + 60_000),
  request_expires_at: status === "recorded" ? receipt(input).request_expires_at : null, receipt: status === "recorded" ? receipt(input) : null});
async function directory() {const path = await realpath(await mkdtemp(join(tmpdir(), "collect-enrollment-"))); await chmod(path, 0o700); return path;}
async function setup() {
  const path = await directory(), helper = join(path, "helper"); await writeFile(helper, "reviewed synthetic helper\n", {mode: 0o700});
  const binding = {helper_path: helper, helper_sha256: sha256(await readFile(helper))};
  const profile: UnattendedProfile = {contract_version: 2, scope: unattendedScope, identity: {principalId: id(9), keySha256: metadata.key_sha256, expiresAt: expiry.replace(".000Z", ".000000Z")},
    helper_path: helper, helper_sha256: binding.helper_sha256, journal_directory: path};
  return {path, binding, profile, reader: async () => metadata};
}
test("strict P-256 SPKI/hash and exact closed receipt schema", () => {
  assert.equal(publicKeyMetadata(metadata), true);
  assert.equal(publicKeyMetadata({...metadata, key_sha256: "a".repeat(64)}), false);
  assert.equal(publicKeyMetadata({...metadata, token: "private"}), false);
  const rsa = generateKeyPairSync("rsa", {modulusLength: 1024}).publicKey.export({format: "der", type: "spki"});
  assert.equal(publicKeyMetadata({...metadata, public_key_spki_base64: rsa.toString("base64"), key_sha256: sha256(rsa)}), false);
  assert.equal(validReceipt(receipt(), intent()), true);
  assert.equal(validReceipt({...receipt(), request_id: id(2)}, intent()), false);
  assert.equal(validReceipt({...receipt(), phone: "+250000000000"}, intent()), false);
});
test("six-digit server timestamps preserve exact instant binding, including microseconds", () => {
  assert.equal(sameInstant("2026-10-01T13:00:00Z", "2026-10-01T13:00:00.000000Z"), true);
  assert.equal(sameInstant("2026-10-01T13:00:00.001Z", "2026-10-01T13:00:00.001001Z"), false);
  assert.equal(validReceipt({...receipt(), recorded_at: receipt().request_expires_at}, intent()), false);
});
test("fresh current identity rejects expired samples, inconsistent state and unknown extras", () => {
  assert.equal(validIdentityObservation(observation(), id(9), at), true);
  assert.equal(validIdentityObservation(observation(), id(9), at + 60_000), false);
  assert.equal(validIdentityObservation({...observation(), identity: {...observation().identity, state: "pending"}}, id(9), at), false);
  assert.equal(validIdentityObservation({...observation(), raw_key: metadata.public_key_spki_base64}, id(9), at), false);
  assert.equal(validLookup({...lookup("not_recorded"), request_expires_at: iso(at)}, intent(), at), false);
  assert.equal(validIdentityObservation({...observation(), identity: {...observation().identity, activated_at: iso(at + 1)}}, id(9), at), false);
});
test("journal reads back input binding before first owner RPC and never repeats after restart", async () => {
  const path = await directory(), journal = new EnrollmentJournal(path, id(20), id(21)); let calls = 0;
  const rpc: OwnerRpc = async (name, input) => {
    calls++; assert.equal(name, "admin_enroll_receipt_operations_identity_v3"); assert.equal(input.p_request_id, id(1));
    const armed = JSON.parse(await readFile(join(path, `${id(1)}.armed.json`), "utf8"));
    assert.equal(armed.input_sha256.length, 64); assert.equal((await journal.intent(id(1)))?.request_id, id(1)); return receipt();
  };
  assert.equal((await journal.once(intent(), rpc, now)).outcome, "recorded");
  assert.equal((await new EnrollmentJournal(path, id(20), id(22)).readOriginal(id(1))).outcome, "recorded");
  await assert.rejects(() => journal.once(intent(), rpc, now)); assert.equal(calls, 1);
});
test("overlapping owner operations produce exactly one first HTTP call", async () => {
  const path = await directory(); let calls = 0;
  const rpc: OwnerRpc = async () => {calls++; return receipt();};
  const result = await Promise.allSettled([new EnrollmentJournal(path, id(20), id(21)).once(intent(), rpc, now), new EnrollmentJournal(path, id(20), id(21)).once(intent(), rpc, now)]);
  assert.equal(result.filter(item => item.status === "fulfilled").length, 1); assert.equal(calls, 1);
});
test("malformed lifecycle success retains unknown original and cannot create a second request", async () => {
  const path = await directory(), journal = new EnrollmentJournal(path, id(20), id(21)); let calls = 0;
  const rpc: OwnerRpc = async () => {calls++; return {...receipt(), key_sha256: "a".repeat(64)};};
  assert.equal((await journal.once(intent(), rpc, now)).outcome, "unknown");
  assert.equal((await new EnrollmentJournal(path, id(20), id(21)).readOriginal(id(1))).request_id, id(1));
  await assert.rejects(() => journal.once(intent(), rpc, now)); assert.equal(calls, 1);
});
for (const status of ["not_recorded", "in_progress"] as const) test(`manual ${status} before original deadline remains unknown`, async () => {
  const path = await directory(), journal = new EnrollmentJournal(path, id(20), id(21));
  await journal.once(intent(), async () => {throw Error("secret backend detail");}, now);
  const result = await journal.reconcile(id(1), id(2), async () => lookup(status, at + 10_000), () => at + 10_000);
  assert.equal(result.outcome, "unknown"); assert.equal(result.request_id, id(1));
  assert.equal((await journal.readOriginal(id(1))).outcome, "unknown");
});
test("fresh absent observation after fenced original deadline closes evidence without replay", async () => {
  const path = await directory(), journal = new EnrollmentJournal(path, id(20), id(21));
  await journal.once(intent(), async () => {throw Error();}, now);
  assert.equal((await journal.reconcile(id(1), id(2), async () => lookup("not_recorded", at + 90_000), () => at + 90_000)).outcome, "not_recorded");
  assert.equal((await new EnrollmentJournal(path, id(20), id(22)).readOriginal(id(1))).outcome, "not_recorded");
  await assert.rejects(() => journal.once(intent(), async () => receipt(), now));
});
test("original recorded lookup after reauthentication retains actor and exact input bindings", async () => {
  const path = await directory(), first = new EnrollmentJournal(path, id(20), id(21)); await first.once(intent(), async () => {throw Error();}, now);
  const fresh = new EnrollmentJournal(path, id(20), id(22));
  assert.equal((await fresh.reconcile(id(1), id(2), async () => lookup("recorded", at + 120_000), () => at + 120_000)).outcome, "recorded");
  await assert.rejects(() => new EnrollmentJournal(path, id(23), id(22)).readOriginal(id(1)));
  await assert.rejects(() => fresh.reconcile(id(1), id(1), async () => lookup("recorded"), now));
});
test("stale/wrong lookup cannot clear unknown and corrupted immutable records refuse", async () => {
  const path = await directory(), journal = new EnrollmentJournal(path, id(20), id(21)); await journal.once(intent(), async () => {throw Error();}, now);
  assert.equal((await journal.reconcile(id(1), id(2), async () => lookup("recorded"), () => at + 70_000)).outcome, "unknown");
  await writeFile(join(path, `${id(1)}.armed.json`), JSON.stringify({contract_version: 3, request_id: id(1), input_sha256: "0".repeat(64), request_expires_at: intent().request_expires_at}) + "\n");
  assert.equal((await journal.reconcile(id(1), id(3), async () => lookup("recorded", at + 120_000), () => at + 120_000)).outcome, "unknown");
});
test("lookup alias cannot contradict an independent recorded receipt or precede original intent", async () => {
  const path = await directory(), journal = new EnrollmentJournal(path, id(20), id(21)); await journal.once(intent(), async () => receipt(), now);
  await journal.reconcile(id(1), id(2), async () => lookup("recorded", at + 100_000), () => at + 100_000);
  const alias = JSON.parse(await readFile(join(path, `${id(1)}.lookup.json`), "utf8"));
  alias.observation.receipt.recorded_at = iso(at - 20_000);
  await writeFile(join(path, `${id(1)}.lookup.json`), JSON.stringify(alias) + "\n");
  await writeFile(join(path, `${id(2)}.outcome.json`), JSON.stringify(alias) + "\n");
  await assert.rejects(() => journal.readOriginal(id(1)), /INTEGRITY_REQUIRED/);
});
test("journal publication failure prevents owner transport", async () => {
  const parent = await directory(), path = join(parent, "unsafe"); await writeFile(path, "file", {mode: 0o600}); let calls = 0;
  await assert.rejects(() => new EnrollmentJournal(path, id(20), id(21)).once(intent(), async () => {calls++; return receipt();}, now)); assert.equal(calls, 0);
});
test("reviewed helper binding rejects replacement, symlink and hardlink alias", async () => {
  const item = await setup(); await verifyHelper(item.binding);
  await writeFile(item.binding.helper_path, "changed"); await assert.rejects(() => verifyHelper(item.binding), /HELPER_UNAVAILABLE/);
  const fresh = await setup(), alias = join(fresh.path, "alias"); await symlink(fresh.binding.helper_path, alias);
  await assert.rejects(() => verifyHelper({...fresh.binding, helper_path: alias}));
  await link(fresh.binding.helper_path, join(fresh.path, "hardlink")); await assert.rejects(() => verifyHelper(fresh.binding));
});
test("explicit key creation is claimed durably once; restart only permits read-public", async () => {
  const item = await setup(); const seen: string[] = [];
  const reader = async (_binding: unknown, command: string) => {seen.push(command); return metadata;};
  assert.deepEqual(await createEnrollmentKey(item.path, id(1), item.binding, reader, now), metadata);
  await assert.rejects(() => createEnrollmentKey(item.path, id(1), item.binding, reader, now)); assert.deepEqual(seen, ["create-key", "read-public"]);
  assert.equal(JSON.parse(await readFile(join(item.path, `${id(1)}.outcome.json`), "utf8")).outcome, "recorded");
});
test("unknown key creation retains original claim and never retries creation", async () => {
  const item = await setup(); let calls = 0;
  await assert.rejects(() => createEnrollmentKey(item.path, id(1), item.binding, async () => {calls++; throw Error("private detail");}, now), /KEY_OUTCOME_UNKNOWN/);
  await assert.rejects(() => createEnrollmentKey(item.path, id(1), item.binding, async () => {calls++; return metadata;}, now)); assert.equal(calls, 1);
});
test("canonical private profile readback verifies current active identity and local hardware key", async () => {
  const item = await setup(), path = join(item.path, "profile.json"); let reads = 0;
  const rpc: OwnerRpc = async name => {assert.equal(name, "admin_get_receipt_operations_identity_v3"); reads++; return observation();};
  const result = await publishEnrollmentProfile(path, item.profile, rpc, item.reader, now);
  assert.equal(result.status, "PROFILE_VERIFIED"); assert.equal(result.scheduler_started, false); assert.equal(reads, 2);
  assert.deepEqual(await loadUnattendedProfile(path), item.profile);
  await assert.rejects(() => publishEnrollmentProfile(path, item.profile, rpc, item.reader, now));
});
for (const state of ["pending", "revoked"] as const) test(`profile publication refuses current ${state} state`, async () => {
  const item = await setup(), path = join(item.path, "profile.json");
  await assert.rejects(() => publishEnrollmentProfile(path, item.profile, async () => observation(state), item.reader, now));
  assert.equal((await readdir(item.path)).includes("profile.json"), false);
});
test("revocation during profile publication leaves unverified file, never a success claim", async () => {
  const item = await setup(), path = join(item.path, "profile.json"); let count = 0;
  await assert.rejects(() => publishEnrollmentProfile(path, item.profile, async () => observation(++count === 1 ? "active" : "revoked"), item.reader, now));
  assert.deepEqual(await loadUnattendedProfile(path), item.profile);
  await assert.rejects(() => validateInstalledEnrollmentProfile(path, async () => observation("revoked"), item.reader, now));
});
test("profile refuses insecure parent, wrong key and different helper without overwriting", async () => {
  const item = await setup(), path = join(item.path, "profile.json");
  await assert.rejects(() => publishEnrollmentProfile(path, {...item.profile, identity: {...item.profile.identity, keySha256: "a".repeat(64)}}, async () => observation(), item.reader, now));
  await chmod(item.path, 0o755); await assert.rejects(() => publishEnrollmentProfile(path, item.profile, async () => observation(), item.reader, now));
});
test("guided flow prepares all three original stages once and resumes without mutation replay", async () => {
  const item = await setup(); let state: "pending" | "active" = "pending", writes = 0, proofs = 0;
  const rpc: OwnerRpc = async (name, input) => {
    if (name === "admin_get_receipt_operations_identity_v3") return observation(state);
    writes++; const value = intent(String(input.p_request_id), name.includes("activate") ? "activate" : "enroll");
    if (value.action === "activate") state = "active"; return receipt(value);
  };
  const fetcher: typeof fetch = async (_url, init) => {
    proofs++; const body = JSON.parse(String(init?.body));
    return Response.json({contract_version: 2, principal_id: id(9), request_id: body.request_id, action: "prove_key", result: {contract_version: 2, principal_id: id(9), request_id: body.request_id,
      action: "prove_key", observed_at: iso(at), expires_at: item.profile.identity.expiresAt, scope: unattendedScope, business_handled: false, financial_action: false, send_action: false}});
  };
  const flow = new EnrollmentPreparation(item.path, id(20), id(21), rpc, async () => ({keySha256: metadata.key_sha256, signature: Buffer.alloc(8).toString("base64")}), item.reader, fetcher, now);
  await flow.create({workflow_id: id(4), enrollment_request_id: id(1), proof_request_id: id(2), activation_request_id: id(3), identity_expires_at: expiry, helper: item.binding, profile_path: join(item.path, "profile.json")});
  assert.equal((await flow.resume(id(4))).status, "PROFILE_PREPARED");
  assert.equal((await flow.resume(id(4))).status, "PROFILE_PREPARED"); assert.equal(writes, 2); assert.equal(proofs, 1);
});
test("guided unknown enrollment blocks proof and activation after filesystem restart", async () => {
  const item = await setup(); let writes = 0, signed = 0;
  const make = () => new EnrollmentPreparation(item.path, id(20), id(21), async () => {writes++; throw Error();}, async () => {signed++; throw Error();}, item.reader, fetch, now);
  const first = make(); await first.create({workflow_id: id(4), enrollment_request_id: id(1), proof_request_id: id(2), activation_request_id: id(3), identity_expires_at: expiry, helper: item.binding, profile_path: join(item.path, "profile.json")});
  assert.equal((await first.resume(id(4))).status, "ENROLLMENT_UNKNOWN"); assert.equal((await make().resume(id(4))).status, "ENROLLMENT_UNKNOWN");
  assert.equal(writes, 1); assert.equal(signed, 0);
});
for (const stage of ["proof", "activation"] as const) test(`guided uncertain ${stage} stops progress and never replays on resume`, async () => {
  const item = await setup(); let writes = 0, proofs = 0;
  const rpc: OwnerRpc = async (name, input) => {
    if (name === "admin_get_receipt_operations_identity_v3") return observation("pending");
    writes++; if (name.includes("activate")) throw Error("unknown activation"); return receipt(intent(String(input.p_request_id)));
  };
  const fetcher: typeof fetch = async (_url, input) => {
    proofs++; if (stage === "proof") throw Error("unknown proof"); const body = JSON.parse(String(input?.body));
    return Response.json({contract_version: 2, principal_id: id(9), request_id: body.request_id, action: "prove_key", result: {contract_version: 2, principal_id: id(9), request_id: body.request_id,
      action: "prove_key", observed_at: iso(at), expires_at: item.profile.identity.expiresAt, scope: unattendedScope, business_handled: false, financial_action: false, send_action: false}});
  };
  const make = () => new EnrollmentPreparation(item.path, id(20), id(21), rpc, async () => ({keySha256: metadata.key_sha256, signature: Buffer.alloc(8).toString("base64")}), item.reader, fetcher, now);
  const flow = make(); await flow.create({workflow_id: id(4), enrollment_request_id: id(1), proof_request_id: id(2), activation_request_id: id(3), identity_expires_at: expiry, helper: item.binding, profile_path: join(item.path, "profile.json")});
  assert.equal((await flow.resume(id(4))).status, stage === "proof" ? "KEY_PROOF_UNKNOWN" : "ACTIVATION_UNKNOWN");
  assert.equal((await make().resume(id(4))).status, stage === "proof" ? "KEY_PROOF_UNKNOWN" : "ACTIVATION_UNKNOWN");
  assert.equal(proofs, 1); assert.equal(writes, stage === "proof" ? 1 : 2); assert.equal((await readdir(item.path)).includes("profile.json"), false);
});
test("missing/insecure profile prerequisites refuse before any enrollment mutation", async () => {
  const item = await setup(); let calls = 0;
  const flow = new EnrollmentPreparation(item.path, id(20), id(21), async () => {calls++; throw Error();}, async () => {throw Error();}, item.reader, fetch, now);
  const input = {workflow_id: id(4), enrollment_request_id: id(1), proof_request_id: id(2), activation_request_id: id(3), identity_expires_at: expiry, helper: item.binding, profile_path: join(item.path, "missing", "profile.json")};
  await assert.rejects(() => flow.create(input), /DESTINATION_UNAVAILABLE/);
  const target = join(item.path, "existing.json"); await writeFile(target, "protected", {mode: 0o600});
  await assert.rejects(() => flow.create({...input, profile_path: target}), /DESTINATION_UNAVAILABLE/); assert.equal(calls, 0); assert.equal(await readFile(target, "utf8"), "protected");
});
test("guided key possession uses the actual Edge P256 verifier and exact v2 signed envelope", async () => {
  const item = await setup(), pair = generateKeyPairSync("ec", {namedCurve: "prime256v1"}), spki = pair.publicKey.export({type: "spki", format: "der"});
  const publicMetadata = {...metadata, public_key_spki_base64: spki.toString("base64"), key_sha256: sha256(spki)};
  let active = false, proofs = 0, wrote = 0;
  const current = () => ({...observation(active ? "active" : "pending"), identity: {...observation(active ? "active" : "pending").identity, key_sha256: publicMetadata.key_sha256}});
  const rpc: OwnerRpc = async (name, input) => {
    if (name === "admin_get_receipt_operations_identity_v3") return current();
    wrote++; if (name.includes("activate")) {assert.equal(proofs, 1); active = true;}
    return {...receipt(intent(String(input.p_request_id), name.includes("activate") ? "activate" : "enroll")), key_sha256: publicMetadata.key_sha256};
  };
  const handler = createSupervisorHandler({now, rpc: async (name, args) => {
    if (name === "receipt_supervisor_key_v1") return {data: {contract_version: 1, principal_id: id(9), state: "pending", scope: unattendedScope,
      public_key_spki_base64: publicMetadata.public_key_spki_base64, key_sha256: publicMetadata.key_sha256, expires_at: item.profile.identity.expiresAt}, error: null};
    assert.equal(name, "receipt_operations_execute_v2"); assert.equal(args.p_action, "prove_key"); proofs++;
    return {data: {contract_version: 2, principal_id: id(9), request_id: args.p_request_id, action: "prove_key", observed_at: iso(at),
      expires_at: item.profile.identity.expiresAt, scope: unattendedScope, business_handled: false, financial_action: false, send_action: false}, error: null};
  }});
  const flow = new EnrollmentPreparation(item.path, id(20), id(21), rpc, async bytes => ({keySha256: publicMetadata.key_sha256, signature: sign("sha256", bytes, pair.privateKey).toString("base64")}),
    async () => publicMetadata, async (url, options) => handler(new Request(url, options)), now);
  await flow.create({workflow_id: id(4), enrollment_request_id: id(1), proof_request_id: id(2), activation_request_id: id(3), identity_expires_at: expiry, helper: item.binding, profile_path: join(item.path, "profile.json")});
  assert.equal((await flow.resume(id(4))).status, "PROFILE_PREPARED"); assert.equal(proofs, 1); assert.equal(wrote, 2);
});
test("private helper subprocess strips credential/proxy environment and returns only exact public metadata", async () => {
  const item = await setup();
  const source = `#!${process.execPath}\nif(process.env.ENROLLMENT_TEST_SECRET || process.env.HTTPS_PROXY)process.exit(2);process.stdout.write(${JSON.stringify(JSON.stringify(metadata))});\n`;
  await writeFile(item.binding.helper_path, source); const binding = {...item.binding, helper_sha256: sha256(source)};
  process.env.ENROLLMENT_TEST_SECRET = "do-not-forward";
  try {assert.deepEqual(await readEnrollmentKey(binding, "read-public"), metadata);} finally {delete process.env.ENROLLMENT_TEST_SECRET;}
});
const token = (changes: Record<string, unknown> = {}) => [Buffer.from(JSON.stringify({alg: "ES256"})).toString("base64url"), Buffer.from(JSON.stringify({sub: id(20), session_id: id(21), role: "authenticated", iss: `${enrollmentOrigin}/auth/v1`, exp: Math.floor(at / 1000) + 3600, ...changes})).toString("base64url"), "signature"].join(".");
test("owner verifies current selected confirmed email before exposing only internal credentials", async () => {
  const environment = {COLLECT_SUPABASE_URL: enrollmentOrigin, COLLECT_SUPABASE_ANON_KEY: "sb_publishable_synthetic", COLLECT_OPERATOR_ACCESS_TOKEN: token()};
  const owner = await enrollmentOwner(environment, async () => Response.json({id: id(20), email: "info@ikanisa.com", email_confirmed_at: iso(at - 1000)}), now);
  assert.equal(owner.actorId, id(20));
  await assert.rejects(() => enrollmentOwner(environment, async () => Response.json({id: id(20), email: "info@ikanisa.com", email_confirmed_at: null}), now));
  await assert.rejects(() => enrollmentOwner({...environment, COLLECT_OPERATOR_ACCESS_TOKEN: token({role: "service_role"})}, async () => {throw Error("must not fetch");}, now));
});
test("owner transport uses one fixed authenticated RPC, refuses extras and redacts authorization failures", async () => {
  let calls = 0;
  const rpc = enrollmentOwnerRpc({actorId: id(20), sessionId: id(21), publicKey: "synthetic-public", accessToken: "synthetic-owner"}, async (url, input) => {
    calls++; assert.equal(url, `${enrollmentOrigin}/rest/v1/rpc/admin_get_receipt_operations_identity_v3`); assert.equal(input?.redirect, "error"); return Response.json({error: "private phone credential"}, {status: 403});
  });
  await assert.rejects(() => rpc("arbitrary_sql", {}), /ARGUMENTS_INVALID/);
  await assert.rejects(() => rpc("admin_get_receipt_operations_identity_v3", {p_principal_id: id(9), extra: true}), /ARGUMENTS_INVALID/);
  await assert.rejects(() => rpc("admin_get_receipt_operations_identity_v3", {p_principal_id: id(9)}), /ENROLLMENT_TRANSPORT_OUTCOME_UNKNOWN/); assert.equal(calls, 1);
});
test("owner transport deadline bounds a fetcher ignoring AbortSignal with no retries", async () => {
  let calls = 0; const rpc = enrollmentOwnerRpc({actorId: id(20), sessionId: id(21), publicKey: "synthetic-public", accessToken: "synthetic-owner"}, async () => {calls++; return new Promise(() => {});}, 20);
  await assert.rejects(() => rpc("admin_get_receipt_operations_identity_v3", {p_principal_id: id(9)}), /OUTCOME_UNKNOWN/); assert.equal(calls, 1);
});
test("owner transport refuses redirected success and oversized response before parsing", async () => {
  const owner = {actorId: id(20), sessionId: id(21), publicKey: "synthetic-public", accessToken: "synthetic-owner"};
  await assert.rejects(() => enrollmentOwnerRpc(owner, async () => Response.redirect("https://example.com", 302))("admin_get_receipt_operations_identity_v3", {p_principal_id: id(9)}));
  await assert.rejects(() => enrollmentOwnerRpc(owner, async () => new Response("{}", {headers: {"content-type": "application/json", "content-length": "999999"}}))("admin_get_receipt_operations_identity_v3", {p_principal_id: id(9)}));
});
test("CLI rejects unknown/repeated/unsafe inputs before any auth, key or transport action", () => {
  assert.deepEqual(enrollmentCliOptions(["verify", "--profile", "/private/profile.json"]), {command: "verify", profile: "/private/profile.json"});
  for (const args of [["verify", "--profile", "relative"], ["verify", "--profile", "/p", "--live"], ["resume", "--directory", "/p", "--directory", "/q"], ["reconcile", "--directory", "/p", "--workflow-id", id(1), "--request-id", id(2), "--lookup-id", id(2)], ["create-key", "--directory", "/p", "--helper", "/h", "--helper-sha", "bad", "--request-id", id(1)]]) assert.throws(() => enrollmentCliOptions(args), /ARGUMENTS_INVALID/);
});
test("actual standalone CLI rejects invalid input without credential configuration or raw diagnostics", () => {
  const child = spawnSync(process.execPath, ["--experimental-strip-types", new URL("./unattended_enroll_cli.ts", import.meta.url).pathname, "prepare", "--send", "secret-input"],
    {encoding: "utf8", timeout: 5000, env: {PATH: "/usr/bin:/bin", LANG: "C"}});
  assert.equal(child.status, 2); assert.equal(child.stdout, ""); assert.equal(child.stderr.includes("secret-input"), false);
  assert.equal(JSON.parse(child.stderr).scheduler_started, false);
});
test("replacement tag passes only as an explicit helper argument and is retained by the strict profile", async () => {
  const item = await setup(), tag = id(77);
  const source = `#!${process.execPath}\nif(process.argv[2]!=="read-public"||process.argv[3]!==${JSON.stringify(tag)})process.exit(2);process.stdout.write(${JSON.stringify(JSON.stringify(metadata))});\n`;
  await writeFile(item.binding.helper_path, source); const binding = {...item.binding, helper_sha256: sha256(source), key_tag_id: tag};
  assert.deepEqual(await readEnrollmentKey(binding, "read-public"), metadata);
  const profile = {...item.profile, helper_sha256: binding.helper_sha256, key_tag_id: tag}, path = join(item.path, "tagged-profile.json");
  assert.equal((await publishEnrollmentProfile(path, profile, async () => observation(), readEnrollmentKey, now)).status, "PROFILE_VERIFIED");
  assert.equal((await loadUnattendedProfile(path)).key_tag_id, tag);
  await writeFile(path, JSON.stringify({...profile, key_tag_id: "../unsafe"}) + "\n"); await assert.rejects(() => loadUnattendedProfile(path));
});
test("current profile requires the selected replacement key fingerprint; no default-key fallback", async () => {
  const item = await setup(), path = join(item.path, "tagged-profile.json"), profile = {...item.profile, key_tag_id: id(77)};
  await writeFile(path, JSON.stringify(profile) + "\n", {mode: 0o600});
  await assert.rejects(() => validateInstalledEnrollmentProfile(path, async () => observation(), async () => ({...metadata, key_sha256: "a".repeat(64)}), now));
});
test("replacement signer validates the UUID tag and forwards it without parent credentials", async () => {
  const item = await setup(), tag = id(77), reply = {contract_version: 2, key_sha256: metadata.key_sha256, signature_base64: Buffer.alloc(8).toString("base64")};
  const source = `#!${process.execPath}\nif(process.argv[2]!=="sign"||process.argv[3]!==${JSON.stringify(tag)}||process.env.ENROLLMENT_TEST_SECRET)process.exit(2);process.stdin.resume();process.stdin.on("end",()=>process.stdout.write(${JSON.stringify(JSON.stringify(reply))}));\n`;
  await writeFile(item.binding.helper_path, source); const helperHash = sha256(source), signal = new AbortController().signal;
  await assert.rejects(() => unattendedKeychainSigner(item.binding.helper_path, helperHash, "../unsafe")(new Uint8Array(), signal), /SIGNING_UNAVAILABLE/);
  if (process.platform !== "darwin") {await assert.rejects(() => unattendedKeychainSigner(item.binding.helper_path, helperHash, tag)(new Uint8Array(), signal), /SIGNING_UNAVAILABLE/); return;}
  process.env.ENROLLMENT_TEST_SECRET = "do-not-forward";
  try {assert.deepEqual(await unattendedKeychainSigner(item.binding.helper_path, helperHash, tag)(Buffer.from("synthetic exact bytes"), signal), {keySha256: metadata.key_sha256, signature: reply.signature_base64});}
  finally {delete process.env.ENROLLMENT_TEST_SECRET;}
});
test("controlled revocation retains only reason digest and original identity without executing signer", async () => {
  const item = await setup(), path = join(item.path, "profile.json"); await writeFile(path, JSON.stringify(item.profile) + "\n", {mode: 0o600});
  const reason = "Retire compromised signing identity"; let mutations = 0;
  const rpc: OwnerRpc = async (name, input) => {
    if (name === "admin_get_receipt_operations_identity_v3") return observation();
    assert.equal(name, "admin_revoke_receipt_operations_identity_v3"); assert.equal(input.p_reason, reason); mutations++;
    return {...receipt({...intent(String(input.p_request_id), "activate"), action: "revoke", reason_sha256: sha256(reason)}), action: "revoke", state_at_action: "revoked", reason_sha256: sha256(reason)};
  };
  const result = await revokePreparedIdentity(item.path, path, id(30), id(20), id(21), rpc, reason, now);
  assert.equal(result.outcome, "recorded"); assert.equal(result.receipt?.state_at_action, "revoked");
  assert.equal((await revokePreparedIdentity(item.path, path, id(30), id(20), id(22), rpc, reason, now)).outcome, "recorded"); assert.equal(mutations, 1);
  for (const file of await readdir(item.path)) if (file.endsWith(".json")) assert.equal((await readFile(join(item.path, file), "utf8")).includes(reason), false);
  assert.equal((await localEnrollmentStatus(item.path, id(30))).outcome, "recorded");
});
test("unknown revocation keeps its UUID and requires lookup rather than another mutation", async () => {
  const item = await setup(), path = join(item.path, "profile.json"); await writeFile(path, JSON.stringify(item.profile) + "\n", {mode: 0o600}); let writes = 0;
  const rpc: OwnerRpc = async name => {if (name === "admin_get_receipt_operations_identity_v3") return observation(); writes++; throw Error("private diagnostic");};
  const reason = "Revoke suspect operations key";
  assert.equal((await revokePreparedIdentity(item.path, path, id(30), id(20), id(21), rpc, reason, now)).outcome, "unknown");
  assert.equal((await revokePreparedIdentity(item.path, path, id(30), id(20), id(22), rpc, reason, now)).outcome, "unknown"); assert.equal(writes, 1);
  await assert.rejects(() => revokePreparedIdentity(item.path, path, id(30), id(20), id(22), rpc, "Changed reason cannot replace intent", now));
});
test("expired identity revocation remains permitted but current profile verification refuses it", async () => {
  const item = await setup(), expired = iso(at - 1000), profile = {...item.profile, identity: {...item.profile.identity, expiresAt: expired}}, path = join(item.path, "expired-profile.json");
  await writeFile(path, JSON.stringify(profile) + "\n", {mode: 0o600});
  const row = {...observation(), identity: {...observation().identity, created_at: iso(at - 100_000), activated_at: iso(at - 50_000), expires_at: expired}};
  const reason = "Retire expired signing identity";
  const rpc: OwnerRpc = async (name, input) => name === "admin_get_receipt_operations_identity_v3" ? row : {...receipt(intent(String(input.p_request_id), "activate")), action: "revoke", state_at_action: "revoked", identity_expires_at: expired, reason_sha256: sha256(reason)};
  assert.equal((await revokePreparedIdentity(item.path, path, id(30), id(20), id(21), rpc, reason, now)).outcome, "recorded");
  await assert.rejects(() => validateInstalledEnrollmentProfile(path, rpc, item.reader, now));
});
