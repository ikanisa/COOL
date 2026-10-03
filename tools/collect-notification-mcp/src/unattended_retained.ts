import {createHash, randomUUID} from "node:crypto";
import {constants, type Stats} from "node:fs";
import * as fs from "node:fs/promises";
import {dirname, join, resolve} from "node:path";
import {unattendedBasenamePattern as NAME} from "./unattended_store_names.ts";

const INTEGRITY = "UNATTENDED_JOURNAL_INTEGRITY_REQUIRED";
const UNAVAILABLE = "UNATTENDED_JOURNAL_UNAVAILABLE";
const MAX_BYTES = 65_536;
const NODE_BYTES = 32_768;
const HEX = /^[0-9a-f]{64}$/;
export const retainedPolicy = Object.freeze({contract_version: 1, trie_leaf_entries: 32, trie_max_depth: 64,
  maintenance_files: 128, maintenance_bytes: 4_194_304, export_entries: 64, export_bytes: 4_194_304,
  preserve_latest_diagnostics: 2, preserve_recent_ms: 120_000, automatic_replay: false});
export const retentionPolicySha256 = createHash("sha256").update(JSON.stringify(retainedPolicy) + "\n").digest("hex");
const fail = (): never => {throw Error(INTEGRITY);};
const sha = (bytes: Uint8Array | string) => createHash("sha256").update(bytes).digest("hex");
const canonical = (value: unknown): Buffer => {
  try {const body = JSON.stringify(value); if (body === undefined) return fail(); return Buffer.from(body + "\n");}
  catch {return fail();}
};
const missing = (error: unknown) => (error as NodeJS.ErrnoException)?.code === "ENOENT";
const same = (a: Stats, b: Stats) => a.dev === b.dev && a.ino === b.ino && a.uid === b.uid && a.mode === b.mode &&
  a.nlink === b.nlink && a.size === b.size && a.mtimeMs === b.mtimeMs && a.ctimeMs === b.ctimeMs;
const privateDir = (s: Stats) => {if (!s.isDirectory() || s.isSymbolicLink() || s.uid !== process.getuid?.() || (s.mode & 0o7777) !== 0o700) fail();};
const privateFile = (s: Stats, bound: number) => {if (!s.isFile() || s.isSymbolicLink() || s.uid !== process.getuid?.() ||
  (s.mode & 0o7777) !== 0o600 || s.nlink !== 1 || s.size < 0 || s.size > bound) fail();};
interface Entry {name: string; name_sha256: string; bytes_sha256: string; bytes_length: number; receipt_sha256: string}
interface Leaf {kind: "leaf"; entries: Entry[]}
interface Branch {kind: "branch"; children: Record<string, string>}
type Node = Leaf | Branch;
interface Head {contract_version: 1; kind: "retained_evidence_head"; directory_sha256: string; sequence: number; root_sha256: string | null; restored_inactive: boolean}
interface Pending {contract_version: 1; kind: "retained_evidence_transaction"; request_id: string; pid: number;
  directory_sha256: string; name: string; bytes_sha256: string; bytes_length: number; receipt_sha256: string; before_sha256: string}
export interface RetainedExport {contract_version: 1; kind: "retained_evidence_export"; root_sha256: string | null;
  restored_inactive: true; entries: {name: string; value: unknown; bytes_sha256: string}[]; next_cursor: string | null}
export type RetentionStage = "object_durable" | "transaction_durable" | "generation_durable" | "index_durable";

/** Private cold evidence is separate from the bounded flat hot directories.
 * Immutable content-addressed trie nodes retain every basename identity. The
 * bounded-depth lookup proves absence against an accepted root rather than an
 * absent object pathname. The mutable head only selects an append-only superset;
 * a durable transaction records crash recovery before that selection changes. */
export class RetainedEvidence {
  readonly directory: string;
  readonly hotDirectory: string;
  private readonly binding: string;
  constructor(hotDirectory: string) {
    this.hotDirectory = resolve(hotDirectory);
    this.directory = resolve(hotDirectory) + ".retained";
    this.binding = sha(resolve(hotDirectory));
  }
  private async ancestors(path: string, privateParent = true) {
    for (let item = path;;) {
      const stat = await fs.lstat(item); if (!stat.isDirectory() || stat.isSymbolicLink()) fail();
      const parent = dirname(item); if (parent === item) break; item = parent;
    }
    if (privateParent) privateDir(await fs.lstat(path));
  }
  private async syncDir(path: string) {
    await this.ancestors(path);
    const handle = await fs.open(path, constants.O_RDONLY | constants.O_DIRECTORY | constants.O_NOFOLLOW);
    try {privateDir(await handle.stat()); await handle.sync();} finally {await handle.close();}
  }
  private async readFile(path: string, bound: number, optional = false, privateParent = true): Promise<Buffer | null> {
    let handle;
    try {
      await this.ancestors(dirname(path), privateParent);
      try {handle = await fs.open(path, constants.O_RDONLY | constants.O_NOFOLLOW);}
      catch (error) {if (optional && missing(error)) return null; throw error;}
      const before = await handle.stat(); privateFile(before, bound);
      const data = Buffer.alloc(bound + 1); let total = 0;
      while (total < data.length) {const next = await handle.read(data, total, data.length - total, total); if (!next.bytesRead) break; total += next.bytesRead;}
      if (total !== before.size || total > bound || !same(before, await handle.stat()) || !same(before, await fs.lstat(path))) fail();
      return data.subarray(0, total);
    } catch {return fail();} finally {await handle?.close().catch(() => {});}
  }
  private async immutable(path: string, bytes: Buffer) {
    const existing = await this.readFile(path, Math.max(MAX_BYTES, NODE_BYTES), true);
    if (existing !== null) {if (!existing.equals(bytes)) fail(); return;}
    const temporary = join(dirname(path), `.${randomUUID()}.tmp`);
    let handle;
    try {
      handle = await fs.open(temporary, constants.O_RDWR | constants.O_CREAT | constants.O_EXCL | constants.O_NOFOLLOW, 0o600);
      await handle.writeFile(bytes); await handle.sync(); await handle.close(); handle = undefined;
      if (!(await this.readFile(temporary, Math.max(MAX_BYTES, NODE_BYTES)))?.equals(bytes)) fail();
      try {await fs.link(temporary, path);} catch (error) {if ((error as NodeJS.ErrnoException).code !== "EEXIST") throw error;}
      await fs.unlink(temporary); await this.syncDir(dirname(path));
      if (!(await this.readFile(path, Math.max(MAX_BYTES, NODE_BYTES)))?.equals(bytes)) fail();
    } catch {throw Error(UNAVAILABLE);} finally {await handle?.close().catch(() => {}); await fs.unlink(temporary).catch(() => {});}
  }
  private async replaceHead(head: Head, hook?: (stage: RetentionStage) => Promise<void>) {
    const path = join(this.directory, "head.json"), bytes = canonical(head), temporary = join(this.directory, `.${randomUUID()}.tmp`);
    let handle;
    try {
      await this.readFile(path, NODE_BYTES); // Replacement never initializes a missing head.
      await this.immutable(join(this.directory, "heads", String(head.sequence).padStart(16, "0")), bytes);
      await hook?.("generation_durable");
      handle = await fs.open(temporary, constants.O_RDWR | constants.O_CREAT | constants.O_EXCL | constants.O_NOFOLLOW, 0o600);
      await handle.writeFile(bytes); await handle.sync(); await handle.close(); handle = undefined;
      if (!(await this.readFile(temporary, NODE_BYTES))?.equals(bytes)) fail();
      await fs.rename(temporary, path); await this.syncDir(this.directory);
      if (!(await this.readFile(path, NODE_BYTES))?.equals(bytes)) fail();
    } finally {await handle?.close().catch(() => {}); await fs.unlink(temporary).catch(() => {});}
  }
  private async ready(create = false, recovery = false): Promise<Head | null> {
    const established = join(dirname(this.directory), `.${sha(this.hotDirectory)}.retained-established.json`);
    const marker = await this.readFile(established, NODE_BYTES, true, false);
    if (marker !== null && !marker.equals(canonical({contract_version: 1, kind: "retained_evidence_established", directory_sha256: this.binding}))) fail();
    try {
      await fs.lstat(this.directory);
    } catch (error) {
      if (!missing(error)) fail();
      if (marker !== null) fail();
      if (!create) return null;
      await this.ancestors(dirname(this.directory));
      try {await fs.mkdir(this.directory, {mode: 0o700});} catch (error) {if ((error as NodeJS.ErrnoException).code !== "EEXIST") throw error;}
      await this.ancestors(this.directory);
      for (const sub of ["objects", "nodes", "heads"]) await fs.mkdir(join(this.directory, sub), {mode: 0o700});
      const head: Head = {contract_version: 1, kind: "retained_evidence_head", directory_sha256: this.binding,
        sequence: 0, root_sha256: null, restored_inactive: false};
      await this.immutable(join(this.directory, "heads", "0000000000000000"), canonical(head));
      await this.immutable(join(this.directory, "head.json"), canonical(head));
      await this.syncDir(this.directory); await this.syncDir(dirname(this.directory));
      await this.immutable(established, canonical({contract_version: 1, kind: "retained_evidence_established", directory_sha256: this.binding}));
    }
    await this.ancestors(this.directory);
    for (const sub of ["objects", "nodes", "heads"]) await this.ancestors(join(this.directory, sub));
    if (!(await this.readFile(established, NODE_BYTES))?.equals(canonical({contract_version: 1, kind: "retained_evidence_established", directory_sha256: this.binding}))) fail();
    const raw = await this.readFile(join(this.directory, "head.json"), NODE_BYTES);
    const head = JSON.parse(raw!.toString("utf8")) as Head;
    if (!canonical(head).equals(raw!) || Object.keys(head).sort().join() !== "contract_version,directory_sha256,kind,restored_inactive,root_sha256,sequence" ||
      head.contract_version !== 1 || head.kind !== "retained_evidence_head" || head.directory_sha256 !== this.binding ||
      !Number.isSafeInteger(head.sequence) || head.sequence < 0 || head.sequence === 0 && head.root_sha256 !== null ||
      head.root_sha256 !== null && !HEX.test(head.root_sha256) || typeof head.restored_inactive !== "boolean") fail();
    const selected = await this.readFile(join(this.directory, "heads", String(head.sequence).padStart(16, "0")), NODE_BYTES);
    if (!selected!.equals(raw!)) fail();
    const successor = await this.readFile(join(this.directory, "heads", String(head.sequence + 1).padStart(16, "0")), NODE_BYTES, true);
    if (successor !== null && !recovery) fail();
    return head;
  }
  private async node(digest: string, depth: number): Promise<Node> {
    if (!HEX.test(digest) || depth > retainedPolicy.trie_max_depth) fail();
    const raw = await this.readFile(join(this.directory, "nodes", digest), NODE_BYTES);
    if (sha(raw!) !== digest) fail(); const value = JSON.parse(raw!.toString("utf8")) as Node;
    if (!canonical(value).equals(raw!)) fail();
    if (value.kind === "leaf") {
      if (Object.keys(value).sort().join() !== "entries,kind" || !Array.isArray(value.entries) || value.entries.length > retainedPolicy.trie_leaf_entries) fail();
      let previous = "";
      for (const e of value.entries) {
        if (Object.keys(e).sort().join() !== "bytes_length,bytes_sha256,name,name_sha256,receipt_sha256" || !NAME.test(e.name) ||
          e.name_sha256 !== sha(e.name) || e.name_sha256 <= previous || !HEX.test(e.bytes_sha256) || !HEX.test(e.receipt_sha256) ||
          !Number.isSafeInteger(e.bytes_length) || e.bytes_length < 1 || e.bytes_length > MAX_BYTES) fail();
        previous = e.name_sha256;
      }
    } else if (value.kind === "branch") {
      if (Object.keys(value).sort().join() !== "children,kind" || !value.children || typeof value.children !== "object" || Array.isArray(value.children) ||
        Object.entries(value.children).some(([key, child]) => !/^[0-9a-f]$/.test(key) || !HEX.test(child)) || depth === retainedPolicy.trie_max_depth) fail();
    } else fail();
    return value;
  }
  private async saveNode(value: Node) {const raw = canonical(value), digest = sha(raw); if (raw.length > NODE_BYTES) fail(); await this.immutable(join(this.directory, "nodes", digest), raw); return digest;}
  private async insert(root: string | null, entry: Entry, depth = 0): Promise<string> {
    const node: Node = root === null ? {kind: "leaf", entries: []} : await this.node(root, depth);
    if (node.kind === "branch") {
      const branch = entry.name_sha256[depth]!;
      const child = await this.insert(node.children[branch] ?? null, entry, depth + 1);
      return this.saveNode({kind: "branch", children: Object.fromEntries(Object.entries({...node.children, [branch]: child}).sort())});
    }
    const old = node.entries.find(row => row.name_sha256 === entry.name_sha256);
    if (old) {if (canonical(old).toString() !== canonical(entry).toString()) fail(); return root!;}
    const entries = [...node.entries, entry].sort((a, b) => a.name_sha256.localeCompare(b.name_sha256));
    if (entries.length <= retainedPolicy.trie_leaf_entries) return this.saveNode({kind: "leaf", entries});
    if (depth >= retainedPolicy.trie_max_depth) fail();
    const groups = new Map<string, Entry[]>();
    for (const row of entries) {const key = row.name_sha256[depth]!; groups.set(key, [...groups.get(key) ?? [], row]);}
    const children: Record<string, string> = {};
    for (const [key, group] of [...groups].sort()) {
      let child: string | null = null; for (const row of group) child = await this.insert(child, row, depth + 1); children[key] = child!;
    }
    return this.saveNode({kind: "branch", children});
  }
  private async entry(head: Head, name: string): Promise<Entry | null> {
    const digest = sha(name); let root = head.root_sha256;
    for (let depth = 0; root !== null; depth++) {
      const node = await this.node(root, depth);
      if (node.kind === "leaf") {const entry = node.entries.find(row => row.name_sha256 === digest) ?? null; if (entry && entry.name !== name) fail(); return entry;}
      root = node.children[digest[depth]!] ?? null;
    }
    return null;
  }
  private async bytes(entry: Entry): Promise<Buffer> {
    const bytes = await this.readFile(join(this.directory, "objects", entry.bytes_sha256), MAX_BYTES);
    if (bytes!.length !== entry.bytes_length || sha(bytes!) !== entry.bytes_sha256) fail();
    const value: unknown = JSON.parse(bytes!.toString("utf8")); if (!canonical(value).equals(bytes!)) fail();
    const receipt = await this.readFile(join(this.directory, "objects", entry.receipt_sha256), NODE_BYTES);
    if (sha(receipt!) !== entry.receipt_sha256 || !receipt!.equals(canonical({contract_version: 1, kind: "retained_evidence_receipt", name: entry.name,
      bytes_sha256: entry.bytes_sha256, bytes_length: entry.bytes_length}))) fail();
    return bytes!;
  }
  async read(name: string): Promise<unknown | null> {
    if (!NAME.test(name)) fail(); const head = await this.ready(); if (!head) return null;
    const entry = await this.entry(head, name); return entry === null ? null : JSON.parse((await this.bytes(entry)).toString("utf8"));
  }
  async inactive() {return (await this.ready())?.restored_inactive ?? false;}
  private async finish(pending: Pending, head: Head, hook?: (stage: RetentionStage) => Promise<void>) {
    const entry: Entry = {name: pending.name, name_sha256: sha(pending.name), bytes_sha256: pending.bytes_sha256,
      bytes_length: pending.bytes_length, receipt_sha256: pending.receipt_sha256};
    await this.bytes(entry);
    const exists = await this.entry(head, pending.name);
    if (exists) {if (!canonical(exists).equals(canonical(entry))) fail(); return;}
    // The original intent may have read an earlier accepted root before it won
    // the exclusive transaction. Insert into the current checked tree instead
    // of replacing it with that older snapshot: every concurrent claim survives.
    const root = await this.insert(head.root_sha256, entry);
    await this.replaceHead({...head, sequence: head.sequence + 1, root_sha256: root}, hook);
    const readback = await this.ready(); if (!readback || !canonical(await this.entry(readback, entry.name)).equals(canonical(entry))) fail();
  }
  private async recover(head: Head) {
    const raw = await this.readFile(join(this.directory, "pending.json"), NODE_BYTES, true); if (raw === null) return;
    const p = JSON.parse(raw.toString("utf8")) as Pending;
    if (!canonical(p).equals(raw) || Object.keys(p).sort().join() !== "before_sha256,bytes_length,bytes_sha256,contract_version,directory_sha256,kind,name,pid,receipt_sha256,request_id" ||
      p.contract_version !== 1 || p.kind !== "retained_evidence_transaction" || p.directory_sha256 !== this.binding || !NAME.test(p.name) ||
      !Number.isSafeInteger(p.pid) || p.pid < 1 || !HEX.test(p.before_sha256) || !HEX.test(p.bytes_sha256) || !HEX.test(p.receipt_sha256) ||
      !/^[0-9a-f-]{36}$/.test(p.request_id) || !Number.isSafeInteger(p.bytes_length) || p.bytes_length < 1 || p.bytes_length > MAX_BYTES) fail();
    // A currently running publisher owns this transaction. PID reuse is
    // conservatively treated as live; no timeout permits overwriting its work.
    try {process.kill(p.pid, 0); throw Error(UNAVAILABLE);} catch (error) {if ((error as NodeJS.ErrnoException).code !== "ESRCH") throw error;}
    await this.finish(p, head); await fs.unlink(join(this.directory, "pending.json")); await this.syncDir(this.directory);
  }
  async retain(name: string, value: unknown, hook?: (stage: RetentionStage) => Promise<void>) {
    if (!NAME.test(name)) fail(); const bytes = canonical(value); if (bytes.length > MAX_BYTES) fail();
    let head = (await this.ready(true, true))!; await this.recover(head); head = (await this.ready())!;
    const old = await this.entry(head, name);
    if (old) {if (!(await this.bytes(old)).equals(bytes)) fail(); return;}
    const digest = sha(bytes), receipt = canonical({contract_version: 1, kind: "retained_evidence_receipt", name, bytes_sha256: digest, bytes_length: bytes.length});
    await this.immutable(join(this.directory, "objects", digest), bytes);
    await this.immutable(join(this.directory, "objects", sha(receipt)), receipt); await hook?.("object_durable");
    const pending: Pending = {contract_version: 1, kind: "retained_evidence_transaction", request_id: randomUUID(), pid: process.pid,
      directory_sha256: this.binding, name, bytes_sha256: digest, bytes_length: bytes.length, receipt_sha256: sha(receipt), before_sha256: sha(canonical(head))};
    // Exclusive publication is the local maintenance lock. A competing writer
    // may retry on a later tick; it cannot regress the accepted root.
    let lock;
    try {
      lock = await fs.open(join(this.directory, "pending.json"), constants.O_RDWR | constants.O_CREAT | constants.O_EXCL | constants.O_NOFOLLOW, 0o600);
      await lock.writeFile(canonical(pending)); await lock.sync(); await lock.close(); lock = undefined; await this.syncDir(this.directory);
    } catch {await lock?.close().catch(() => {}); throw Error(UNAVAILABLE);}
    try {
      await hook?.("transaction_durable");
      const current = (await this.ready())!;
      await this.finish(pending, current, hook); await hook?.("index_durable");
      await fs.unlink(join(this.directory, "pending.json")); await this.syncDir(this.directory);
    } catch (error) {
      // A caught failure leaves the original durable transaction. Mark this
      // process as no longer owning it only after the exact recovery completes.
      await this.finish(pending, (await this.ready(false, true))!).then(async () => {await fs.unlink(join(this.directory, "pending.json")); await this.syncDir(this.directory);}).catch(() => {});
      throw error;
    }
  }
  async exportPage(cursor: string | null = null, maximum: number = retainedPolicy.export_entries, expectedRoot?: string | null): Promise<RetainedExport> {
    if (cursor !== null && !HEX.test(cursor) || !Number.isSafeInteger(maximum) || maximum < 1 || maximum > retainedPolicy.export_entries) fail();
    const head = await this.ready(); if (expectedRoot !== undefined && head?.root_sha256 !== expectedRoot) fail();
    const entries: RetainedExport["entries"] = []; let bytes = 0, visited = 0, more = false, next: string | null = null;
    const walk = async (root: string, prefix: string, depth: number): Promise<void> => {
      if (more || cursor !== null && (prefix + "f".repeat(64 - prefix.length)) <= cursor) return;
      if (++visited > 4096) fail(); const node = await this.node(root, depth);
      if (node.kind === "branch") {for (const [key, child] of Object.entries(node.children).sort()) await walk(child, prefix + key, depth + 1); return;}
      for (const entry of node.entries) {
        if (cursor !== null && entry.name_sha256 <= cursor) continue;
        if (entries.length === maximum || bytes + entry.bytes_length > retainedPolicy.export_bytes) {more = true; return;}
        const raw = await this.bytes(entry); entries.push({name: entry.name, value: JSON.parse(raw.toString("utf8")), bytes_sha256: sha(raw)}); bytes += raw.length; next = entry.name_sha256;
      }
    };
    if (head?.root_sha256) await walk(head.root_sha256, "", 0);
    return {contract_version: 1, kind: "retained_evidence_export", root_sha256: head?.root_sha256 ?? null, restored_inactive: true,
      entries, next_cursor: more ? next : null};
  }
  /** A new target has no hot claims or credentials. Restored control records
   * remain queryable but never permit a tick; activation needs a new deployment. */
  async restorePage(page: RetainedExport) {
    if (page.contract_version !== 1 || page.kind !== "retained_evidence_export" || page.restored_inactive !== true ||
      !Array.isArray(page.entries) || page.entries.length > retainedPolicy.export_entries || page.root_sha256 !== null && !HEX.test(page.root_sha256) ||
      page.next_cursor !== null && !HEX.test(page.next_cursor)) fail();
    const head = await this.ready(true);
    if (!head) return fail();
    if (head.sequence !== 0 && !head.restored_inactive) fail();
    if (!head.restored_inactive) await this.replaceHead({...head, sequence: head.sequence + 1, restored_inactive: true});
    let total = 0;
    for (const entry of page.entries) {
      if (!NAME.test(entry.name) || !HEX.test(entry.bytes_sha256)) fail(); const raw = canonical(entry.value);
      total += raw.length; if (raw.length > MAX_BYTES || total > retainedPolicy.export_bytes || sha(raw) !== entry.bytes_sha256) fail();
      await this.retain(entry.name, entry.value);
    }
  }
}
