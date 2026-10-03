import {spawn} from "node:child_process";
import {randomBytes} from "node:crypto";
import {constants} from "node:fs";
import * as fs from "node:fs/promises";
import {dirname, isAbsolute, join} from "node:path";
import {keys, uuid, hash, utc, unattendedScope} from "./unattended_contract.ts";
import {loadUnattendedProfile} from "./unattended_profile.ts";
import type {UnattendedProfile} from "./unattended_profile.ts";
import {UnattendedStore} from "./unattended_store.ts";
import {publicKeyMetadata, sha256, validIdentityObservation} from "./unattended_enrollment_contract.ts";
import type {IdentityObservation, PublicKeyMetadata} from "./unattended_enrollment_contract.ts";
import type {OwnerRpc} from "./unattended_enrollment_owner.ts";

export interface HelperBinding {helper_path: string; helper_sha256: string; key_tag_id?: string}
export type KeyReader = (binding: HelperBinding, command: "read-public" | "create-key") => Promise<PublicKeyMetadata>;
export async function privateAncestors(path: string, directory = false) {
  if (!isAbsolute(path) || path.includes("\0") || !process.getuid) throw Error();
  let ancestor = path;
  for (;;) {
    const stat = await fs.lstat(ancestor);
    if (stat.isSymbolicLink() || (ancestor !== path || directory) && !stat.isDirectory()) throw Error();
    const parent = dirname(ancestor); if (parent === ancestor) break; ancestor = parent;
  }
}
async function privateDirectory(path: string) {
  await privateAncestors(path, true);
  const stat = await fs.lstat(path);
  if (stat.uid !== process.getuid?.() || (stat.mode & 0o7777) !== 0o700) throw Error();
  return stat;
}
export async function prepareProfileDestination(path: string) {
  try {
    if (!isAbsolute(path) || path.includes("\0")) throw Error();
    await privateDirectory(dirname(path));
    try {await fs.lstat(path); throw new Error("EXISTS");}
    catch (error) {if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;}
  } catch {throw new Error("ENROLLMENT_PROFILE_DESTINATION_UNAVAILABLE");}
}
/** Reviewed executable, owner-controlled parent, no symlink or hardlink alias. */
export async function verifyHelper(binding: HelperBinding): Promise<void> {
  let file;
  try {
    if (!keys(binding, binding.key_tag_id === undefined ? ["helper_path", "helper_sha256"] : ["helper_path", "helper_sha256", "key_tag_id"]) ||
        !hash(binding.helper_sha256) || binding.key_tag_id !== undefined && !uuid(binding.key_tag_id)) throw Error();
    await privateAncestors(binding.helper_path);
    await privateDirectory(dirname(binding.helper_path));
    file = await fs.open(binding.helper_path, constants.O_RDONLY | constants.O_NOFOLLOW);
    const before = await file.stat();
    if (!before.isFile() || before.uid !== process.getuid?.() || before.nlink !== 1 || (before.mode & 0o022) !== 0 ||
        (before.mode & 0o100) === 0 || before.size < 1 || before.size > 16 * 1024 * 1024) throw Error();
    const bytes = Buffer.alloc(before.size + 1); let length = 0;
    while (length < bytes.length) {const part = await file.read(bytes, length, bytes.length - length, length); if (part.bytesRead === 0) break; length += part.bytesRead;}
    const after = await file.stat(), current = await fs.lstat(binding.helper_path);
    for (const stat of [after, current]) if (stat.dev !== before.dev || stat.ino !== before.ino || stat.mode !== before.mode || stat.uid !== before.uid ||
      stat.nlink !== before.nlink || stat.size !== before.size || stat.mtimeMs !== before.mtimeMs || stat.ctimeMs !== before.ctimeMs) throw Error();
    if (length !== before.size || sha256(bytes.subarray(0, length)) !== binding.helper_sha256) throw Error();
  } catch {throw new Error("ENROLLMENT_HELPER_UNAVAILABLE");}
  finally {await file?.close().catch(() => {});}
}
export const readEnrollmentKey: KeyReader = async (binding, command) => {
  await verifyHelper(binding);
  if (command !== "read-public" && command !== "create-key") throw new Error("ENROLLMENT_ARGUMENTS_INVALID");
  const value = await new Promise<unknown>((resolve, reject) => {
    const child = spawn(binding.helper_path, binding.key_tag_id === undefined ? [command] : [command, binding.key_tag_id], {stdio: ["ignore", "pipe", "ignore"], env: {PATH: "/usr/bin:/bin", LANG: "C"}});
    const chunks: Buffer[] = []; let length = 0, settled = false;
    const finish = (value?: unknown) => {if (settled) return; settled = true; clearTimeout(timer); value === undefined ? reject(new Error("ENROLLMENT_KEY_UNAVAILABLE")) : resolve(value);};
    const timer = setTimeout(() => {child.kill(); finish();}, 5000);
    child.on("error", () => finish());
    child.stdout.on("data", (chunk: Buffer) => {length += chunk.length; if (length > 4096) {child.kill(); finish();} else chunks.push(chunk);});
    child.on("close", code => {if (code !== 0) return finish(); try {finish(JSON.parse(Buffer.concat(chunks).toString("utf8")));} catch {finish();}});
  });
  await verifyHelper(binding);
  if (!publicKeyMetadata(value)) throw new Error("ENROLLMENT_KEY_UNAVAILABLE");
  return value;
};
/** Explicit key creation has its own durable original claim; a duplicate or
 * crash permits read-public inspection, never another create-key invocation. */
export async function createEnrollmentKey(directory: string, requestId: string, binding: HelperBinding, reader: KeyReader = readEnrollmentKey, now: () => number = Date.now) {
  if (!uuid(requestId)) throw new Error("ENROLLMENT_ARGUMENTS_INVALID");
  await verifyHelper(binding);
  const store = new UnattendedStore(directory), intent = {contract_version: 3, action: "create_key", request_id: requestId,
    binding, created_at: new Date(now()).toISOString()};
  await store.publish(`${requestId}.checkpoint.json`, intent);
  await store.publish(`${requestId}.armed.json`, {contract_version: 3, request_id: requestId, intent_sha256: sha256(JSON.stringify(intent))});
  if (JSON.stringify(await store.read(`${requestId}.checkpoint.json`)) !== JSON.stringify(intent)) throw new Error("ENROLLMENT_JOURNAL_INTEGRITY_REQUIRED");
  try {
    const metadata = await reader(binding, "create-key");
    if (!publicKeyMetadata(metadata)) throw Error();
    const current = await reader(binding, "read-public");
    if (JSON.stringify(metadata) !== JSON.stringify(current)) throw Error();
    await store.publish(`${requestId}.outcome.json`, {contract_version: 3, request_id: requestId, outcome: "recorded", public_key: metadata});
    return metadata;
  } catch {throw new Error("ENROLLMENT_KEY_OUTCOME_UNKNOWN");}
}
function matchesObservation(observation: IdentityObservation, profile: UnattendedProfile, now: number) {
  return validIdentityObservation(observation, profile.identity.principalId, now) && observation.found && observation.identity?.state === "active" &&
    observation.identity.key_sha256 === profile.identity.keySha256 && observation.identity.expires_at === profile.identity.expiresAt &&
    Date.parse(observation.identity.expires_at) > now + 15_000;
}
export async function validateInstalledEnrollmentProfile(path: string, rpc: OwnerRpc, reader: KeyReader = readEnrollmentKey, now: () => number = Date.now) {
  try {
    const profile = await loadUnattendedProfile(path);
    const binding: HelperBinding = {helper_path: profile.helper_path, helper_sha256: profile.helper_sha256, ...(profile.key_tag_id === undefined ? {} : {key_tag_id: profile.key_tag_id})};
    await verifyHelper(binding);
    const key = await reader(binding, "read-public");
    if (!publicKeyMetadata(key) || key.key_sha256 !== profile.identity.keySha256) throw Error();
    await privateDirectory(profile.journal_directory);
    const observation = await rpc("admin_get_receipt_operations_identity_v3", {p_principal_id: profile.identity.principalId});
    if (!validIdentityObservation(observation, profile.identity.principalId, now()) || !matchesObservation(observation, profile, now())) throw Error();
    if (JSON.stringify(profile) !== JSON.stringify(await loadUnattendedProfile(path))) throw Error();
    await verifyHelper(binding);
    return {contract_version: 3, status: "PROFILE_VERIFIED" as const, principal_id: profile.identity.principalId, key_sha256: profile.identity.keySha256,
      identity_expires_at: profile.identity.expiresAt, checked_at: observation.checked_at, sample_valid_until: observation.sample_valid_until,
      profile_sha256: sha256(JSON.stringify(profile) + "\n"), helper_sha256: profile.helper_sha256, scheduler_installed: false, scheduler_started: false};
  } catch {throw new Error("ENROLLMENT_PROFILE_UNVERIFIED");}
}
/** Exclusive publication; existing profiles are never overwritten. A final
 * fresh backend validation is required even after successful byte readback. */
export async function publishEnrollmentProfile(path: string, profile: UnattendedProfile, rpc: OwnerRpc, reader: KeyReader = readEnrollmentKey, now: () => number = Date.now) {
  let file; let temporary = "";
  try {
    const fields = ["contract_version", "scope", "identity", "helper_path", "helper_sha256", "journal_directory"];
    if (!isAbsolute(path) || !keys(profile, profile.key_tag_id === undefined ? fields : [...fields, "key_tag_id"]) || profile.key_tag_id !== undefined && !uuid(profile.key_tag_id) ||
        profile.contract_version !== 2 || profile.scope !== unattendedScope || !keys(profile.identity, ["principalId", "keySha256", "expiresAt"]) ||
        !uuid(profile.identity.principalId) || !hash(profile.identity.keySha256) || !utc(profile.identity.expiresAt)) throw Error();
    const parent = await privateDirectory(dirname(path));
    await privateDirectory(profile.journal_directory);
    const binding: HelperBinding = {helper_path: profile.helper_path, helper_sha256: profile.helper_sha256, ...(profile.key_tag_id === undefined ? {} : {key_tag_id: profile.key_tag_id})};
    await verifyHelper(binding);
    const metadata = await reader(binding, "read-public");
    if (!publicKeyMetadata(metadata) || metadata.key_sha256 !== profile.identity.keySha256) throw Error();
    const observation = await rpc("admin_get_receipt_operations_identity_v3", {p_principal_id: profile.identity.principalId});
    if (!validIdentityObservation(observation, profile.identity.principalId, now()) || !matchesObservation(observation, profile, now())) throw Error();
    const bytes = Buffer.from(JSON.stringify(profile) + "\n");
    if (bytes.length > 8192) throw Error();
    temporary = join(dirname(path), `.collect-profile-${randomBytes(16).toString("hex")}.tmp`);
    file = await fs.open(temporary, constants.O_RDWR | constants.O_CREAT | constants.O_EXCL | constants.O_NOFOLLOW, 0o600);
    await file.writeFile(bytes); await file.sync();
    const stat = await file.stat(), readback = Buffer.alloc(bytes.length + 1); let size = 0;
    while (size < readback.length) {const part = await file.read(readback, size, readback.length - size, size); if (part.bytesRead === 0) break; size += part.bytesRead;}
    if (stat.uid !== process.getuid?.() || (stat.mode & 0o7777) !== 0o600 || stat.nlink !== 1 || size !== bytes.length || !readback.subarray(0, size).equals(bytes)) throw Error();
    const currentParent = await privateDirectory(dirname(path));
    if (currentParent.dev !== parent.dev || currentParent.ino !== parent.ino) throw Error();
    await file.close(); file = undefined;
    await fs.link(temporary, path); await fs.unlink(temporary); temporary = "";
    const directory = await fs.open(dirname(path), constants.O_RDONLY | constants.O_DIRECTORY | constants.O_NOFOLLOW);
    try {await directory.sync();} finally {await directory.close();}
    return await validateInstalledEnrollmentProfile(path, rpc, reader, now);
  } catch {throw new Error("ENROLLMENT_PROFILE_PUBLICATION_UNVERIFIED");}
  finally {await file?.close().catch(() => {}); if (temporary) await fs.unlink(temporary).catch(() => {});}
}
