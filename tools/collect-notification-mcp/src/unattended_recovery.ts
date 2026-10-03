import {constants, type Stats} from "node:fs";
import * as fs from "node:fs/promises";
import {createHash, randomBytes} from "node:crypto";
import {dirname, join, resolve} from "node:path";
import {capturedSchedulerConfiguration, loadSchedulerDeployment, schedulerDirectory, selectedSchedulerPath,
  type CapturedSchedulerConfiguration} from "./unattended_deployment.ts";
import {loadUnattendedProfile} from "./unattended_profile.ts";
import {UnattendedStore} from "./unattended_store.ts";
import {UnattendedJournal} from "./unattended_journal.ts";
import {RetainedEvidence, retainedPolicy} from "./unattended_retained.ts";
import {validUnattendedBasename} from "./unattended_store_names.ts";
import {validHistoryPlan, validHistoryClosure} from "./unattended_history.ts";
import {keys, hash, integer, uuid, unattendedScope, type Json} from "./unattended_contract.ts";

/** Explicit local evidence operations. No transport, signer or launchctl seam.
 * Source writes are not locked: monotonic inventories and file identities must
 * survive both captures unchanged or the export gets no completion seal. */
export const schedulerRecoveryPolicy = Object.freeze({contract_version: 1, page_entries: 64, page_bytes: 4_194_304,
  record_bytes: 65_536, hot_entries: 65_536, hot_bytes: 134_217_728, maximum_pages: 65_536,
  context_bytes: 33_554_432, runtime_entries: 20_000, runtime_bytes: 536_870_912});
const policySha = checksum(canonical(schedulerRecoveryPolicy));
const STORES = ["control", "diagnostics", "journal"] as const;
type StoreName = typeof STORES[number];
type Tier = "cold" | "hot";
type ConfigName = "PREPARATION.json" | "profile.json" | "runtime.sha256" | "tick.sh" | "com.ikanisa.collect.receipt-operations.plist";
interface ConfigFile {name: ConfigName; source_path: string; bytes_base64: string; bytes_sha256: string}
interface Hot {name: string; bytes_sha256: string; stamp: string}
interface Source {name: StoreName; source_directory: string; hot_count: number; hot_inventory_sha256: string;
  source_stamp_sha256: string; cold_root_sha256: string | null; cold_head_stamp: string | null; restored_inactive: boolean}
interface Context {contract_version: 1; kind: "scheduler_recovery_context"; policy_sha256: string;
  source_deployment_directory: string; configuration: ConfigFile[]; sources: Source[]; runtime_state_sha256: string;
  source_snapshot_sha256: string; automatic_replay: false; restored_inactive: true}
interface Entry {store: StoreName; tier: Tier; name: string; value: unknown; bytes_sha256: string}
interface Page {contract_version: 1; kind: "scheduler_recovery_page"; context_sha256: string; sequence: number;
  previous_sha256: string; entries: Entry[]}
interface Seal {contract_version: 1; kind: "scheduler_recovery_seal"; context_sha256: string; source_snapshot_sha256: string;
  pages: number; records: number; last_page_sha256: string; restored_inactive: true; automatic_replay: false}
interface Intent {contract_version: 1; kind: "scheduler_recovery_import"; context_sha256: string; seal_sha256: string;
  target_directory: string; stores: Record<StoreName, string>; restored_inactive: true; automatic_replay: false}
interface Snapshot {context: Context; captured: CapturedSchedulerConfiguration; hot: Map<StoreName, Hot[]>}
export interface RecoveryDependencies {hook?: (stage: "source_captured" | "page_exported" | "stores_inactive" | "record_imported") => Promise<void>}
const boundary = {contract_version: 1, scope: unattendedScope, sender_actions: 0, credentials_printed: false,
  automatic_replay: false, cadence_verified: false, carrier_delivery_verified: false};
function fail(code = "SCHEDULER_RECOVERY_INTEGRITY_REQUIRED"): never {throw Error(code);}
function canonical(value: unknown) {const raw = JSON.stringify(value); if (raw === undefined) fail(); return Buffer.from(raw + "\n");}
function checksum(bytes: Uint8Array) {return createHash("sha256").update(bytes).digest("hex");}
function missing(error: unknown) {return (error as NodeJS.ErrnoException)?.code === "ENOENT";}
function stamp(s: Stats) {return JSON.stringify([s.dev, s.ino, s.uid, s.mode, s.nlink, s.size, s.mtimeMs, s.ctimeMs]);}
function same(a: Stats, b: Stats) {if (stamp(a) !== stamp(b)) fail("SCHEDULER_RECOVERY_SOURCE_CHANGED");}
function nameHash(name: string) {return checksum(Buffer.from(name));}
function entryOrder(entry: Entry) {return `${STORES.indexOf(entry.store)}:${entry.tier === "cold" ? 0 : 1}:${nameHash(entry.name)}`;}
function overlaps(a: string, b: string) {a = resolve(a); b = resolve(b); return a === b || a.startsWith(b + "/") || b.startsWith(a + "/");}
async function ancestry(path: string) {
  if (!selectedSchedulerPath(path)) fail();
  let item = path;
  for (;;) {const info = await fs.lstat(item); if (info.isSymbolicLink()) fail(); const parent = dirname(item); if (parent === item) return; item = parent;}
}
async function syncDir(path: string) {
  await schedulerDirectory(path); const before = await fs.lstat(path), fd = await fs.open(path, constants.O_RDONLY | constants.O_DIRECTORY | constants.O_NOFOLLOW);
  try {const opened = await fd.stat(); if (opened.dev !== before.dev || opened.ino !== before.ino) fail(); await fd.sync();
    const after = await fs.lstat(path); if (after.dev !== before.dev || after.ino !== before.ino) fail();} finally {await fd.close();}
}
async function freshDirectory(path: string) {
  if (!selectedSchedulerPath(path) || resolve(path) !== path) fail(); await schedulerDirectory(dirname(path));
  await fs.mkdir(path, {mode: 0o700}); await syncDir(dirname(path)); await schedulerDirectory(path);
}
async function fileBytes(path: string, maximum: number, privateFile = true): Promise<{bytes: Buffer; info: Stats}> {
  await ancestry(path); const file = await fs.open(path, constants.O_RDONLY | constants.O_NOFOLLOW);
  try {const before = await file.stat();
    if (!before.isFile() || before.uid !== process.getuid?.() || before.nlink !== 1 || before.size > maximum ||
        (before.mode & 0o022) !== 0 || privateFile && (before.mode & 0o7777) !== 0o600) fail();
    const parts: Buffer[] = []; let length = 0;
    while (length <= maximum) {const buf = Buffer.alloc(Math.min(65536, maximum + 1 - length));
      const {bytesRead} = await file.read(buf, 0, buf.length, length); if (!bytesRead) break; parts.push(buf.subarray(0, bytesRead)); length += bytesRead;}
    same(before, await file.stat()); same(before, await fs.lstat(path)); if (length !== before.size || length > maximum) fail();
    return {bytes: Buffer.concat(parts), info: before};
  } finally {await file.close();}
}
async function jsonFile(path: string, maximum: number) {
  const {bytes} = await fileBytes(path, maximum); const value: unknown = JSON.parse(bytes.toString("utf8"));
  if (!canonical(value).equals(bytes)) fail(); return {value, sha: checksum(bytes)};
}
async function immutable(path: string, bytes: Buffer) {
  await schedulerDirectory(dirname(path)); const temporary = join(dirname(path), `.recovery-${randomBytes(16).toString("hex")}.tmp`);
  const file = await fs.open(temporary, constants.O_CREAT | constants.O_EXCL | constants.O_RDWR | constants.O_NOFOLLOW, 0o600);
  try {await file.writeFile(bytes); await file.sync(); await file.close();
    if (!(await fileBytes(temporary, bytes.length)).bytes.equals(bytes)) fail();
    await fs.link(temporary, path); await fs.unlink(temporary); await syncDir(dirname(path));
    if (!(await fileBytes(path, bytes.length)).bytes.equals(bytes)) fail();
  } catch (error) {await file.close().catch(() => {}); await fs.unlink(temporary).catch(() => {}); throw error;}
}
function safeEvidence(value: unknown) {
  // Existing evidence contracts prohibit signing material. Refuse unexpected
  // credential fields instead of copying them into a recovery bundle.
  // Field screening is finite; arbitrary secret strings are not classified.
  const credentialKeys = new Set(["signature", "privatekey", "authorization", "password", "accesstoken", "refreshtoken", "bearer", "credential", "credentials", "secret",
    "apikey", "clientsecret", "servicerolekey", "signingkey"]);
  let visited = 0;
  const walk = (node: unknown, depth: number): void => {
    if (++visited > 65536 || depth > 64) fail();
    if (node && typeof node === "object") for (const [key, child] of Object.entries(node)) {
      if (credentialKeys.has(key.replace(/[^a-zA-Z0-9]/g, "").toLowerCase())) fail();
      walk(child, depth + 1);
    }
  }; walk(value, 0);
}
function hotDigest(rows: Pick<Hot, "name" | "bytes_sha256">[]) {
  const digest = createHash("sha256"); for (const row of rows) digest.update(canonical({name: row.name, bytes_sha256: row.bytes_sha256})); return digest.digest("hex");
}
async function hotInventory(directory: string): Promise<{rows: Hot[]; directoryStamp: string}> {
  await schedulerDirectory(directory); const before = await fs.lstat(directory), rows: Hot[] = []; let bytes = 0;
  const stream = await fs.opendir(directory);
  for await (const item of stream) {
    if (rows.length >= schedulerRecoveryPolicy.hot_entries || !validUnattendedBasename(item.name)) fail();
    const file = await fileBytes(join(directory, item.name), schedulerRecoveryPolicy.record_bytes), value: unknown = JSON.parse(file.bytes.toString("utf8"));
    if (!canonical(value).equals(file.bytes)) fail(); safeEvidence(value); bytes += file.bytes.length;
    if (bytes > schedulerRecoveryPolicy.hot_bytes) fail(); rows.push({name: item.name, bytes_sha256: checksum(file.bytes), stamp: stamp(file.info)});
  }
  same(before, await fs.lstat(directory)); rows.sort((a, b) => nameHash(a.name).localeCompare(nameHash(b.name)));
  return {rows, directoryStamp: stamp(before)};
}
async function runtimeState(captured: CapturedSchedulerConfiguration) {
  const manifest = captured.manifest, digest = createHash("sha256"); let total = 0;
  const entries = Object.entries(manifest.runtime_inputs).sort(([a], [b]) => a.localeCompare(b));
  if (entries.length > schedulerRecoveryPolicy.runtime_entries) fail();
  // A newly added module/dependency must not escape the original preparer's
  // inventory merely because it has no declared hash yet. Match its finite
  // no-symlink walk, excluding unused package-manager .bin links.
  const actualFiles = new Set<string>(), actualLinks = new Map<string, string>(); let visited = 0;
  const directories: {path: string; stamp: string}[] = [];
  const scan = async (path: string, dependencies: boolean, depth = 0): Promise<void> => {
    if (depth > 64 || ++visited > 65536) fail(); await ancestry(path); const before = await fs.lstat(path);
    if (!before.isDirectory()) fail(); directories.push({path, stamp: stamp(before)});
    const stream = await fs.opendir(path);
    for await (const entry of stream) {
      if (dependencies && entry.name === ".bin") continue; if (++visited > 65536) fail();
      const selected = join(path, entry.name), info = await fs.lstat(selected);
      if (info.isSymbolicLink()) {if (!dependencies) fail(); actualLinks.set(selected, await fs.readlink(selected));}
      else if (info.isDirectory()) await scan(selected, dependencies, depth + 1);
      else if (info.isFile()) {actualFiles.add(selected); if (actualFiles.size > schedulerRecoveryPolicy.runtime_entries) fail();}
      else fail();
    }
    same(before, await fs.lstat(path));
  };
  await scan(join(manifest.source_directory, "src"), false); await scan(join(manifest.source_directory, "node_modules"), true);
  const expectedFiles = new Set(entries.map(([path]) => path).filter(path => path.startsWith(manifest.source_directory + "/src/") || path.startsWith(manifest.source_directory + "/node_modules/")));
  if (actualFiles.size !== expectedFiles.size || [...actualFiles].some(path => !expectedFiles.has(path)) ||
      actualLinks.size !== Object.keys(manifest.dependency_links).length || [...actualLinks].some(([path, target]) => manifest.dependency_links[path] !== target)) fail("SCHEDULER_RECOVERY_SOURCE_CHANGED");
  for (const [path, expected] of entries) {
    if (!selectedSchedulerPath(path)) fail(); await ancestry(path); const fd = await fs.open(path, constants.O_RDONLY | constants.O_NOFOLLOW);
    try {const before = await fd.stat(); if (!before.isFile() || before.uid !== process.getuid?.() || before.nlink !== 1 ||
        (before.mode & 0o022) !== 0 || before.size > 268435456) fail();
      const hash = createHash("sha256"); let length = 0; const buf = Buffer.alloc(65536);
      for (;;) {const {bytesRead} = await fd.read(buf, 0, buf.length, length); if (!bytesRead) break; length += bytesRead; total += bytesRead;
        if (length > before.size || total > schedulerRecoveryPolicy.runtime_bytes) fail(); hash.update(buf.subarray(0, bytesRead));}
      same(before, await fd.stat()); same(before, await fs.lstat(path)); if (length !== before.size || hash.digest("hex") !== expected) fail("SCHEDULER_RECOVERY_SOURCE_CHANGED");
      digest.update(canonical({path, expected, stamp: stamp(before)}));
    } finally {await fd.close();}
  }
  for (const [path, expected] of Object.entries(manifest.dependency_links).sort(([a], [b]) => a.localeCompare(b))) {
    if (!selectedSchedulerPath(path)) fail(); await ancestry(dirname(path)); const before = await fs.lstat(path);
    if (!before.isSymbolicLink() || before.uid !== process.getuid?.() || await fs.readlink(path) !== expected ||
        !(await fs.realpath(path)).startsWith(manifest.source_directory + "/node_modules/")) fail();
    same(before, await fs.lstat(path)); digest.update(canonical({path, expected, stamp: stamp(before)}));
  }
  for (const directory of directories.sort((a, b) => a.path.localeCompare(b.path))) {
    if (stamp(await fs.lstat(directory.path)) !== directory.stamp) fail("SCHEDULER_RECOVERY_SOURCE_CHANGED"); digest.update(canonical(directory));
  }
  return digest.digest("hex");
}
async function snapshot(directory: string): Promise<Snapshot> {
  const deployment = await loadSchedulerDeployment(directory, false), config: ConfigFile[] = [], configStamps: string[] = [];
  await loadUnattendedProfile(deployment.manifest.profile_path);
  for (const name of ["PREPARATION.json", "profile.json", "runtime.sha256", "tick.sh", "com.ikanisa.collect.receipt-operations.plist"] as ConfigName[]) {
    const path = name === "profile.json" ? deployment.manifest.profile_path : join(directory, name);
    const file = await fileBytes(path, name === "profile.json" ? 8192 : 4194304);
    config.push({name, source_path: path, bytes_base64: file.bytes.toString("base64"), bytes_sha256: checksum(file.bytes)}); configStamps.push(stamp(file.info));
  }
  const captured = configuration({source_deployment_directory: directory, configuration: config}), sources: Source[] = [], hot = new Map<StoreName, Hot[]>();
  for (const name of STORES) {
    const path = name === "journal" ? captured.manifest.journal_directory : join(directory, name), store = new UnattendedStore(path);
    const inventory = await hotInventory(path), first = await store.retained.exportPage(null, 1), inactive = await store.retained.inactive();
    let headStamp: string | null = null;
    try {headStamp = stamp((await fileBytes(join(store.retained.directory, "head.json"), 65536)).info);} catch (error) {if (!missing(error)) throw error;}
    hot.set(name, inventory.rows); sources.push({name, source_directory: path, hot_count: inventory.rows.length, hot_inventory_sha256: hotDigest(inventory.rows),
      source_stamp_sha256: checksum(canonical({directory: inventory.directoryStamp, rows: inventory.rows})),
      cold_root_sha256: first.root_sha256, cold_head_stamp: headStamp, restored_inactive: inactive});
  }
  const runtime = await runtimeState(captured);
  const context: Context = {contract_version: 1, kind: "scheduler_recovery_context", policy_sha256: policySha,
    source_deployment_directory: directory, configuration: config, sources, runtime_state_sha256: runtime,
    source_snapshot_sha256: checksum(canonical({configStamps, sources, runtime})), automatic_replay: false, restored_inactive: true};
  return {context, captured, hot};
}
function configuration(context: Pick<Context, "configuration" | "source_deployment_directory">) {
  if (!Array.isArray(context.configuration) || context.configuration.length !== 5) fail();
  const expected = ["PREPARATION.json", "profile.json", "runtime.sha256", "tick.sh", "com.ikanisa.collect.receipt-operations.plist"];
  const files: Record<string, Buffer> = {};
  context.configuration.forEach((file, index) => {
    if (!keys(file, ["name", "source_path", "bytes_base64", "bytes_sha256"]) || file.name !== expected[index] ||
        !selectedSchedulerPath(file.source_path) || typeof file.bytes_base64 !== "string" || file.bytes_base64.length > 5592416 || !hash(file.bytes_sha256)) fail();
    const bytes = Buffer.from(file.bytes_base64, "base64"); if (bytes.toString("base64") !== file.bytes_base64 || checksum(bytes) !== file.bytes_sha256) fail(); files[file.name] = bytes;
  });
  const captured = capturedSchedulerConfiguration(context.source_deployment_directory, files["PREPARATION.json"]!, files["profile.json"]!,
    Object.fromEntries(expected.slice(2).map(name => [name, files[name]!])));
  context.configuration.forEach(file => {if (file.source_path !== (file.name === "profile.json" ? captured.manifest.profile_path : join(context.source_deployment_directory, file.name))) fail();});
  return captured;
}
function validContext(value: unknown): value is Context {
  if (!keys(value, ["contract_version", "kind", "policy_sha256", "source_deployment_directory", "configuration", "sources", "runtime_state_sha256", "source_snapshot_sha256", "automatic_replay", "restored_inactive"]) ||
      value.contract_version !== 1 || value.kind !== "scheduler_recovery_context" || value.policy_sha256 !== policySha || !selectedSchedulerPath(value.source_deployment_directory) ||
      !hash(value.runtime_state_sha256) || !hash(value.source_snapshot_sha256) || value.automatic_replay !== false || value.restored_inactive !== true || !Array.isArray(value.sources) || value.sources.length !== 3) return false;
  try {const captured = configuration(value as unknown as Context);
    return value.sources.every((source, index) => keys(source, ["name", "source_directory", "hot_count", "hot_inventory_sha256", "source_stamp_sha256", "cold_root_sha256", "cold_head_stamp", "restored_inactive"]) &&
      source.name === STORES[index] && source.source_directory === (source.name === "journal" ? captured.manifest.journal_directory : join(value.source_deployment_directory as string, source.name as string)) &&
      integer(source.hot_count, 0, schedulerRecoveryPolicy.hot_entries) && hash(source.hot_inventory_sha256) && hash(source.source_stamp_sha256) &&
      (source.cold_root_sha256 === null || hash(source.cold_root_sha256)) && (source.cold_head_stamp === null || typeof source.cold_head_stamp === "string" && source.cold_head_stamp.length <= 512) && typeof source.restored_inactive === "boolean");
  } catch {return false;}
}
function pageName(sequence: number) {return `page-${String(sequence).padStart(8, "0")}.json`;}
function validateEntry(value: unknown): value is Entry {
  if (!keys(value, ["store", "tier", "name", "value", "bytes_sha256"]) || !STORES.includes(value.store as StoreName) || !["hot", "cold"].includes(String(value.tier)) ||
      !validUnattendedBasename(value.name) || !hash(value.bytes_sha256)) return false;
  const bytes = canonical(value.value); safeEvidence(value.value); return bytes.length <= schedulerRecoveryPolicy.record_bytes && checksum(bytes) === value.bytes_sha256;
}
async function bundle(directory: string) {
  await schedulerDirectory(directory); const raw = await jsonFile(join(directory, "context.json"), schedulerRecoveryPolicy.context_bytes);
  if (!validContext(raw.value)) fail(); const seal = await jsonFile(join(directory, "seal.json"), 65536), value = seal.value;
  if (!keys(value, ["contract_version", "kind", "context_sha256", "source_snapshot_sha256", "pages", "records", "last_page_sha256", "restored_inactive", "automatic_replay"]) ||
      value.contract_version !== 1 || value.kind !== "scheduler_recovery_seal" || value.context_sha256 !== raw.sha || value.source_snapshot_sha256 !== raw.value.source_snapshot_sha256 ||
      !integer(value.pages, 0, schedulerRecoveryPolicy.maximum_pages) || !integer(value.records, 0, schedulerRecoveryPolicy.maximum_pages * 64) || !hash(value.last_page_sha256) ||
      value.restored_inactive !== true || value.automatic_replay !== false) fail();
  let count = 0; const entries = await fs.opendir(directory);
  for await (const entry of entries) {if (++count > value.pages + 2 || !["context.json", "seal.json"].includes(entry.name) &&
      (!/^page-[0-9]{8}\.json$/.test(entry.name) || !integer(Number(entry.name.slice(5, 13)), 1, value.pages))) fail();}
  if (count !== value.pages + 2) fail(); return {context: raw.value, contextSha: raw.sha, seal: value as unknown as Seal, sealSha: seal.sha};
}
async function walkPages(directory: string, source: Awaited<ReturnType<typeof bundle>>, visit: (entry: Entry) => Promise<void>) {
  let previous = source.contextSha, order = "", count = 0; const hotCounts = new Map<StoreName, number>(), hotHashes = new Map(STORES.map(name => [name, createHash("sha256")]));
  for (let sequence = 1; sequence <= source.seal.pages; sequence++) {
    const raw = await jsonFile(join(directory, pageName(sequence)), schedulerRecoveryPolicy.page_bytes), page = raw.value;
    if (!keys(page, ["contract_version", "kind", "context_sha256", "sequence", "previous_sha256", "entries"]) || page.contract_version !== 1 || page.kind !== "scheduler_recovery_page" ||
        page.context_sha256 !== source.contextSha || page.sequence !== sequence || page.previous_sha256 !== previous || !Array.isArray(page.entries) || !integer(page.entries.length, 1, 64)) fail();
    for (const entry of page.entries) {
      if (!validateEntry(entry) || entryOrder(entry) <= order) fail(); order = entryOrder(entry); count++;
      if (entry.tier === "hot") {hotCounts.set(entry.store, (hotCounts.get(entry.store) ?? 0) + 1); hotHashes.get(entry.store)!.update(canonical({name: entry.name, bytes_sha256: entry.bytes_sha256}));}
      await visit(entry);
    }
    previous = raw.sha;
  }
  if (previous !== source.seal.last_page_sha256 || count !== source.seal.records) fail();
  for (const store of source.context.sources) if ((hotCounts.get(store.name) ?? 0) !== store.hot_count || hotHashes.get(store.name)!.digest("hex") !== store.hot_inventory_sha256) fail();
  const after = await bundle(directory); if (after.contextSha !== source.contextSha || after.sealSha !== source.sealSha) fail();
}
export async function exportSchedulerRecovery(deployment: string, output: string, dependencies: RecoveryDependencies = {}): Promise<Json> {
  let created = false;
  try {
    if (!selectedSchedulerPath(deployment) || !selectedSchedulerPath(output) || overlaps(deployment, output)) fail();
    const initial = await snapshot(deployment);
    if (initial.context.sources.some(source => overlaps(source.source_directory, output) || overlaps(source.source_directory + ".retained", output)) || overlaps(initial.captured.manifest.source_directory, output)) fail();
    await freshDirectory(output); created = true; const contextBytes = canonical(initial.context);
    if (contextBytes.length > schedulerRecoveryPolicy.context_bytes) fail(); await immutable(join(output, "context.json"), contextBytes); await dependencies.hook?.("source_captured");
    const contextSha = checksum(contextBytes); let previous = contextSha, sequence = 0, records = 0, entries: Entry[] = [];
    const flush = async () => {if (!entries.length) return; if (++sequence > schedulerRecoveryPolicy.maximum_pages) fail();
      const page: Page = {contract_version: 1, kind: "scheduler_recovery_page", context_sha256: contextSha, sequence, previous_sha256: previous, entries};
      const bytes = canonical(page); if (bytes.length > schedulerRecoveryPolicy.page_bytes) fail(); await immutable(join(output, pageName(sequence)), bytes);
      previous = checksum(bytes); entries = []; await dependencies.hook?.("page_exported");};
    const append = async (entry: Entry) => {if (!validateEntry(entry)) fail();
      if (entries.length === 64 || canonical({entries: [...entries, entry]}).length > schedulerRecoveryPolicy.page_bytes - 1024) await flush(); entries.push(entry); records++;};
    for (const source of initial.context.sources) {
      const store = new UnattendedStore(source.source_directory); let cursor: string | null = null;
      do {const page = await store.retained.exportPage(cursor, retainedPolicy.export_entries, source.cold_head_stamp === null ? undefined : source.cold_root_sha256);
        for (const entry of page.entries) {if (checksum(canonical(await store.read(entry.name))) !== entry.bytes_sha256) fail(); await append({store: source.name, tier: "cold", ...entry});}
        cursor = page.next_cursor;
      } while (cursor !== null);
      for (const entry of initial.hot.get(source.name)!) {
        const file = await fileBytes(join(source.source_directory, entry.name), schedulerRecoveryPolicy.record_bytes);
        if (stamp(file.info) !== entry.stamp || checksum(file.bytes) !== entry.bytes_sha256) fail("SCHEDULER_RECOVERY_SOURCE_CHANGED");
        const value: unknown = JSON.parse(file.bytes.toString("utf8")); if (checksum(canonical(await store.read(entry.name))) !== entry.bytes_sha256) fail();
        await append({store: source.name, tier: "hot", name: entry.name, value, bytes_sha256: entry.bytes_sha256});
      }
    }
    await flush(); const final = await snapshot(deployment);
    if (!canonical(initial.context).equals(canonical(final.context))) fail("SCHEDULER_RECOVERY_SOURCE_CHANGED");
    const seal: Seal = {contract_version: 1, kind: "scheduler_recovery_seal", context_sha256: contextSha, source_snapshot_sha256: initial.context.source_snapshot_sha256,
      pages: sequence, records, last_page_sha256: previous, restored_inactive: true, automatic_replay: false};
    await immutable(join(output, "seal.json"), canonical(seal)); const checked = await bundle(output); await walkPages(output, checked, async () => {});
    return {status: "SCHEDULER_RECOVERY_EXPORTED", ...boundary, context_sha256: contextSha, pages: sequence, records, source_snapshot_verified: true, cooperative_writer_lock: false};
  } catch (error) {
    if (created) await immutable(join(output, "FAILED.json"), canonical({status: "SCHEDULER_RECOVERY_EXPORT_INCOMPLETE", automatic_replay: false})).catch(() => {});
    return {status: error instanceof Error && error.message === "SCHEDULER_RECOVERY_SOURCE_CHANGED" ? error.message : "SCHEDULER_RECOVERY_EXPORT_REFUSED", ...boundary, complete: false};
  }
}
function mappings(target: string): Record<StoreName, string> {return {control: join(target, "control"), diagnostics: join(target, "diagnostics"), journal: join(target, "journal")};}
export async function restoreSchedulerRecovery(input: string, target: string, dependencies: RecoveryDependencies = {}): Promise<Json> {
  let created = false;
  try {
    if (!selectedSchedulerPath(input) || !selectedSchedulerPath(target) || overlaps(input, target)) fail(); const source = await bundle(input);
    const captured = configuration(source.context);
    if (overlaps(target, source.context.source_deployment_directory) || overlaps(target, captured.manifest.source_directory) ||
        source.context.sources.some(store => overlaps(target, store.source_directory) || overlaps(target, store.source_directory + ".retained"))) fail();
    await freshDirectory(target); created = true; const stores = mappings(target);
    const intent: Intent = {contract_version: 1, kind: "scheduler_recovery_import", context_sha256: source.contextSha, seal_sha256: source.sealSha,
      target_directory: target, stores, restored_inactive: true, automatic_replay: false};
    await immutable(join(target, "IMPORT.json"), canonical(intent));
    for (const name of STORES) {await freshDirectory(stores[name]); await new RetainedEvidence(stores[name]).restorePage({contract_version: 1,
      kind: "retained_evidence_export", root_sha256: null, restored_inactive: true, entries: [], next_cursor: null});}
    for (const name of STORES) if (!await new RetainedEvidence(stores[name]).inactive()) fail();
    await immutable(join(target, "context.json"), canonical(source.context)); await dependencies.hook?.("stores_inactive");
    await walkPages(input, source, async entry => {
      const store = new UnattendedStore(stores[entry.store]), existing = await store.read(entry.name, true);
      if (existing !== null && checksum(canonical(existing)) !== entry.bytes_sha256) fail();
      await store.retained.retain(entry.name, entry.value); if (checksum(canonical(await store.read(entry.name))) !== entry.bytes_sha256 || !await store.retained.inactive()) fail();
      await dependencies.hook?.("record_imported");
    });
    await immutable(join(target, "COMPLETE.json"), canonical({contract_version: 1, kind: "scheduler_recovery_complete", context_sha256: source.contextSha,
      seal_sha256: source.sealSha, stores, pages: source.seal.pages, records: source.seal.records, restored_inactive: true, automatic_replay: false}));
    return {status: "SCHEDULER_RECOVERY_RESTORED_INACTIVE", ...boundary, context_sha256: source.contextSha, pages: source.seal.pages, records: source.seal.records, complete: true, restored_inactive: true};
  } catch {if (created) await immutable(join(target, "FAILED.json"), canonical({status: "SCHEDULER_RECOVERY_IMPORT_INCOMPLETE", restored_inactive: true, automatic_replay: false})).catch(() => {});
    return {status: "SCHEDULER_RECOVERY_RESTORE_REFUSED", ...boundary, complete: false, restored_inactive: created};}
}
export async function inspectSchedulerRecovery(target: string, requestId?: string): Promise<Json> {
  try {
    await schedulerDirectory(target); const raw = await jsonFile(join(target, "IMPORT.json"), 65536), intent = raw.value, stores = mappings(target);
    if (!keys(intent, ["contract_version", "kind", "context_sha256", "seal_sha256", "target_directory", "stores", "restored_inactive", "automatic_replay"]) ||
        intent.contract_version !== 1 || intent.kind !== "scheduler_recovery_import" || intent.target_directory !== target || !hash(intent.context_sha256) || !hash(intent.seal_sha256) ||
        JSON.stringify(intent.stores) !== JSON.stringify(stores) || intent.restored_inactive !== true || intent.automatic_replay !== false) fail();
    for (const name of STORES) if (!await new RetainedEvidence(stores[name]).inactive()) fail();
    let complete = false; try {const record = (await jsonFile(join(target, "COMPLETE.json"), 65536)).value;
      if (!keys(record, ["contract_version", "kind", "context_sha256", "seal_sha256", "stores", "pages", "records", "restored_inactive", "automatic_replay"]) || record.contract_version !== 1 ||
          record.kind !== "scheduler_recovery_complete" || record.context_sha256 !== intent.context_sha256 || record.seal_sha256 !== intent.seal_sha256 || JSON.stringify(record.stores) !== JSON.stringify(stores) ||
          !integer(record.pages, 0, schedulerRecoveryPolicy.maximum_pages) || !integer(record.records, 0, schedulerRecoveryPolicy.maximum_pages * 64) || record.restored_inactive !== true || record.automatic_replay !== false) fail(); complete = true;
    } catch (error) {if (!missing(error)) throw error;}
    const context = await jsonFile(join(target, "context.json"), schedulerRecoveryPolicy.context_bytes);
    if (!validContext(context.value) || context.sha !== intent.context_sha256) fail(); const captured = configuration(context.value);
    if (requestId !== undefined) {if (!uuid(requestId)) fail(); const result = await new UnattendedJournal(stores.journal).readOriginal(requestId);
      return {status: "SCHEDULER_RECOVERY_ORIGINAL_INSPECTED", ...boundary, complete, restored_inactive: true, request_id: requestId, outcome: result.outcome, reason_code: result.reason_code, action: result.action, lookup_request_id: result.lookup_request_id};}
    let originalRequests = 0, unknownRequests = 0, integrityRequests = 0, unresolvedRuns = 0;
    const journal = new UnattendedJournal(stores.journal); let cursor: string | null = null, pages = 0;
    do {if (++pages > schedulerRecoveryPolicy.maximum_pages) fail(); const page = await journal.store.retained.exportPage(cursor);
      for (const entry of page.entries) {
        if (entry.name.endsWith(".checkpoint.json")) {originalRequests++; try {if ((await journal.readOriginal(entry.name.slice(0, 36))).outcome === "unknown") unknownRequests++;} catch {integrityRequests++;}}
        else if (/\.(?:armed|outcome|lookup)\.json$/.test(entry.name) && await journal.store.read(`${entry.name.slice(0, 36)}.checkpoint.json`, true) === null) integrityRequests++;
        if (entry.name.endsWith(".run.json")) {const id = entry.name.slice(0, 36), closed = await journal.store.read(`${id}.closed.json`, true);
          if (!validHistoryPlan(entry.value, captured.profile.identity) || closed === null || !validHistoryClosure(closed, id, Date.now())) unresolvedRuns++;}
      } cursor = page.next_cursor;
    } while (cursor !== null);
    return {status: "SCHEDULER_RECOVERY_INSPECTED_INACTIVE", ...boundary, complete, restored_inactive: true, context_sha256: context.sha,
      original_requests: originalRequests, unknown_requests: unknownRequests, integrity_required_requests: integrityRequests, unresolved_runs: unresolvedRuns,
      graph_validation: "original_request_reads", configuration_relocated: false, runtime_restored: false};
  } catch {return {status: "SCHEDULER_RECOVERY_INSPECTION_REFUSED", ...boundary, complete: false};}
}
