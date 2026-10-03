import test from "node:test";
import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
import {sha256, publicKeyMetadata, validIntent, validReceipt, validLookup, validIdentityObservation, validDirectory} from "./unattended_enrollment_contract.ts";
import type {EnrollmentIntent, IdentityCursor} from "./unattended_enrollment_contract.ts";
const directory = new URL("./testing/unattended_enrollment_observed/", import.meta.url);
const fixture = async (name: string) => JSON.parse(await readFile(new URL(`observed-${name}-v3.json`, directory), "utf8"));
test("actual isolated SQL fixtures bind to unchanged final migration and source hashes", async () => {
  const provenance = JSON.parse(await readFile(new URL("provenance.json", directory), "utf8"));
  const migration = await readFile(new URL("../../../supabase/migrations/20261001180000_receipt_operations_enrollment_workflow.sql", import.meta.url));
  assert.equal(sha256(migration), provenance.migration_sha256);
  for (const item of provenance.files) assert.equal(sha256(await readFile(new URL(item.name, directory))), item.sha256);
  assert.equal(provenance.source_kind, "actual_isolated_sql_outputs"); assert.equal(provenance.hosted_execution, false);
});
for (const action of ["enroll", "activate", "revoke"] as const) test(`actual SQL ${action} receipt and original lookup satisfy exact Node schema`, async () => {
  const value = await fixture(action), observed = await fixture(`${action}-lookup`);
  const original = await fixture(action === "enroll" ? "enroll-input" : action === "revoke" ? "revoke-input" : "enroll-input");
  const intent: EnrollmentIntent = {action, request_id: value.request_id, key_sha256: value.key_sha256, request_expires_at: value.request_expires_at,
    identity_expires_at: value.identity_expires_at, principal_id: action === "enroll" ? null : value.principal_id,
    public_key_spki_base64: action === "enroll" ? original.public_key_spki_base64 : null,
    ...(action === "revoke" ? {reason_sha256: value.reason_sha256} : {})};
  assert.equal(validIntent(intent), true); assert.equal(validReceipt(value, intent), true);
  assert.equal(validLookup(observed, intent, Date.parse(observed.checked_at)), true);
  assert.equal(validReceipt({...value, principal_id: "99810000-0000-4000-8000-000000000099"}, {...intent, principal_id: value.principal_id}), false);
});
test("actual original public enrollment arguments and expiry are preserved", async () => {
  const input = await fixture("enroll-input"), value = await fixture("enroll");
  assert.equal(publicKeyMetadata({contract_version: 2, scope: "rw_receipt_operations", public_key_spki_base64: input.public_key_spki_base64, key_sha256: input.key_sha256}), true);
  assert.equal(validReceipt(value, {action: "enroll", principal_id: null, public_key_spki_base64: input.public_key_spki_base64, ...input}), true);
});
for (const state of ["active", "revoked", "expired-active"] as const) test(`actual SQL current ${state} identity is a strict redacted observation`, async () => {
  const value = await fixture(`identity-${state}`);
  assert.equal(validIdentityObservation(value, value.identity.principal_id, Date.parse(value.checked_at)), true);
  assert.equal(validIdentityObservation(value, value.identity.principal_id, Date.parse(value.sample_valid_until)), false);
});
test("actual bounded directory pages retain exact cursors, states and six-digit ordering", async () => {
  const pages = await fixture("identity-pages"); let before: IdentityCursor | null = null; const seen = new Set<string>();
  for (const page of pages) {
    assert.equal(validDirectory(page, 2, before, Date.parse(page.checked_at)), true);
    for (const row of page.rows) {assert.equal(seen.has(row.principal_id), false); seen.add(row.principal_id);}
    before = page.next_cursor;
  }
  assert.ok(seen.size > 25); assert.equal(before, null);
  const bad = {...pages[0], next_cursor: {...pages[0].next_cursor, principal_id: "99810000-0000-4000-8000-000000000099"}};
  assert.equal(validDirectory(bad, 2, null, Date.parse(bad.checked_at)), false);
});
for (const state of ["not-recorded", "in-progress"] as const) test(`actual SQL ${state} lookup exposes no original deadline or receipt`, async () => {
  const value = await fixture(state), enrolled = await fixture("enroll");
  const intent: EnrollmentIntent = {action: "activate", request_id: value.request_id, principal_id: enrolled.principal_id, key_sha256: enrolled.key_sha256,
    identity_expires_at: enrolled.identity_expires_at, request_expires_at: enrolled.request_expires_at, public_key_spki_base64: null};
  assert.equal(validLookup(value, intent, Date.parse(value.checked_at)), true); assert.equal(value.request_expires_at, null); assert.equal(value.receipt, null);
});
