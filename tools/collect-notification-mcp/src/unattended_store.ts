import {randomBytes} from "node:crypto";
import {constants} from "node:fs";
import type {Stats} from "node:fs";
import * as filesystem from "node:fs/promises";
import {dirname, isAbsolute, join, resolve} from "node:path";
import {RetainedEvidence, type RetentionStage} from "./unattended_retained.ts";
import {unattendedBasenamePattern as NAME} from "./unattended_store_names.ts";
import {boundEmergencyDisableEvidence} from "./unattended_disable_evidence.ts";

export type UnattendedStoreIO = Pick<typeof filesystem, "lstat" | "mkdir" | "open" | "link" | "unlink">;
type FailureCode = "UNATTENDED_JOURNAL_UNAVAILABLE" | "UNATTENDED_JOURNAL_INTEGRITY_REQUIRED" |
  "UNATTENDED_REQUEST_RECONCILIATION_REQUIRED";
const UNAVAILABLE = "UNATTENDED_JOURNAL_UNAVAILABLE";
const INTEGRITY = "UNATTENDED_JOURNAL_INTEGRITY_REQUIRED";
const RECONCILE = "UNATTENDED_REQUEST_RECONCILIATION_REQUIRED";
const MAX_BYTES = 65_536;

class StoreFailure extends Error {
  readonly code: FailureCode;
  constructor(code: FailureCode) {
    super(code);
    this.code = code;
    // Errors may cross the MCP boundary: neither native errors nor local paths
    // from a stack trace are part of the public evidence-store response.
    this.stack = code;
  }
}
function refuse(code: FailureCode): never {throw new StoreFailure(code);}
function failureCode(error: unknown, fallback: FailureCode): FailureCode {
  return error instanceof StoreFailure ? error.code : fallback;
}
function missing(error: unknown) {return (error as NodeJS.ErrnoException | null)?.code === "ENOENT";}
function ownerUid() {
  if (typeof process.getuid !== "function") refuse(UNAVAILABLE);
  return process.getuid();
}
function encoded(value: unknown): Buffer {
  try {
    const json = JSON.stringify(value);
    if (json === undefined) refuse(INTEGRITY);
    const data = Buffer.from(json + "\n");
    if (data.length > MAX_BYTES) refuse(INTEGRITY);
    return data;
  } catch {refuse(INTEGRITY);}
}
function sameNode(left: Stats, right: Stats) {return left.dev === right.dev && left.ino === right.ino;}
function privateDirectory(info: Stats) {
  if (!info.isDirectory() || info.isSymbolicLink() || info.uid !== ownerUid() || (info.mode & 0o7777) !== 0o700) refuse(UNAVAILABLE);
}
function privateFile(info: Stats) {
  if (!info.isFile() || info.uid !== ownerUid() || (info.mode & 0o7777) !== 0o600 || info.nlink !== 1 ||
      !Number.isSafeInteger(info.size) || info.size < 0 || info.size > MAX_BYTES) refuse(INTEGRITY);
}
function stableFile(before: Stats, after: Stats) {
  privateFile(after);
  if (!sameNode(before,after) || before.size !== after.size || before.uid !== after.uid || before.mode !== after.mode ||
      before.nlink !== after.nlink || before.mtimeMs !== after.mtimeMs || before.ctimeMs !== after.ctimeMs) refuse(INTEGRITY);
}
async function boundedRead(file: filesystem.FileHandle): Promise<Buffer> {
  // Bound memory even if a file grows after its initial fstat.
  const bytes = Buffer.alloc(MAX_BYTES + 1);
  let length = 0;
  while (length < bytes.length) {
    const {bytesRead} = await file.read(bytes,length,bytes.length - length,length);
    if (bytesRead === 0) break;
    length += bytesRead;
  }
  if (length > MAX_BYTES) refuse(INTEGRITY);
  return bytes.subarray(0,length);
}

/** Append-only storage for caller-validated, nonsensitive unattended evidence.
 * Publish never overwrites a claim and never removes a published record. A
 * persistence failure seals publishing on this instance; historical reads are
 * still available for reconciliation. The caller owns evidence schemas and
 * must never pass keys, signatures, credentials, or private response bodies. */
export class UnattendedStore {
  readonly directory: string;
  private readonly io: UnattendedStoreIO;
  private publishingFailed = false;
  readonly retained: RetainedEvidence;

  constructor(directory: string, io: UnattendedStoreIO = filesystem) {
    if (typeof directory !== "string" || !isAbsolute(directory) || directory.includes("\0")) refuse(UNAVAILABLE);
    this.directory = resolve(directory);
    this.io = io;
    this.retained = new RetainedEvidence(this.directory);
  }

  private path(name: string) {
    if (typeof name !== "string" || !NAME.test(name)) refuse(INTEGRITY);
    return join(this.directory,name);
  }

  private async ancestors(): Promise<Stats | null> {
    let ancestor = this.directory;
    let directory: Stats | null = null;
    while (true) {
      try {
        const info = await this.io.lstat(ancestor);
        if (!info.isDirectory() || info.isSymbolicLink()) refuse(UNAVAILABLE);
        if (ancestor === this.directory) directory = info;
      } catch (error) {
        if (ancestor !== this.directory || !missing(error)) throw error;
      }
      const parent = dirname(ancestor);
      if (ancestor === parent) break;
      ancestor = parent;
    }
    return directory;
  }

  private async directoryMatches(expected: Stats) {
    const current = await this.ancestors();
    if (current === null) refuse(UNAVAILABLE);
    privateDirectory(current);
    if (!sameNode(expected,current)) refuse(UNAVAILABLE);
  }

  private async syncDirectory(path: string, expected: Stats) {
    let directory: filesystem.FileHandle | undefined;
    try {
      directory = await this.io.open(path,constants.O_RDONLY | constants.O_DIRECTORY | constants.O_NOFOLLOW);
      const before = await directory.stat();
      privateDirectory(before);
      if (!sameNode(expected,before)) refuse(UNAVAILABLE);
      await directory.sync();
      const after = await directory.stat();
      privateDirectory(after);
      if (!sameNode(before,after) || !sameNode(after,await this.io.lstat(path))) refuse(UNAVAILABLE);
      await directory.close();
      directory = undefined;
    } finally {await directory?.close().catch(() => {});}
  }

  private async directoryReady(): Promise<Stats> {
    try {
      const existing = await this.ancestors();
      if (existing === null) {
        const parentPath = dirname(this.directory);
        const parent = await this.io.lstat(parentPath);
        privateDirectory(parent);
        let created = false;
        try {await this.io.mkdir(this.directory,{mode:0o700}); created = true;}
        catch (error) {if ((error as NodeJS.ErrnoException).code !== "EEXIST") throw error;}
        // A successful first publish must also survive the directory's creation.
        if (created) await this.syncDirectory(parentPath,parent);
      }
      const info = await this.ancestors();
      if (info === null) refuse(UNAVAILABLE);
      privateDirectory(info);
      return info;
    } catch {refuse(UNAVAILABLE);}
  }

  private async readHot(name: string, optional = false): Promise<unknown | null> {
    const path = this.path(name);
    if (typeof optional !== "boolean") refuse(INTEGRITY);
    const directory = await this.directoryReady();
    let file: filesystem.FileHandle | undefined;
    try {
      try {file = await this.io.open(path,constants.O_RDONLY | constants.O_NOFOLLOW);}
      catch (error) {if (optional && missing(error)) {await this.directoryMatches(directory); return null;} throw error;}
      const before = await file.stat();
      privateFile(before);
      const data = await boundedRead(file);
      const after = await file.stat();
      stableFile(before,after);
      if (data.length !== before.size) refuse(INTEGRITY);
      const value: unknown = JSON.parse(data.toString("utf8"));
      if (!encoded(value).equals(data)) refuse(INTEGRITY);
      stableFile(after,await this.io.lstat(path));
      await this.directoryMatches(directory);
      await file.close();
      file = undefined;
      return value;
    } catch (error) {refuse(failureCode(error,INTEGRITY));}
    finally {await file?.close().catch(() => {});}
  }

  async read(name: string, optional = false): Promise<unknown | null> {
    this.path(name); if (typeof optional !== "boolean") refuse(INTEGRITY);
    try {
      const hot = await this.readHot(name, true), cold = await this.retained.read(name);
      if (hot !== null && cold !== null && !encoded(hot).equals(encoded(cold))) refuse(INTEGRITY);
      const value = hot ?? cold; if (value === null && !optional) refuse(INTEGRITY); return value;
    } catch (error) {refuse(failureCode(error, INTEGRITY));}
  }

  /** Called only for consumer-validated completed evidence. Cold identity is
   * committed and reread before removal; unchanged hot bytes are required. */
  async archive(name: string, value: unknown, hook?: (stage: RetentionStage) => Promise<void>): Promise<void> {
    const path = this.path(name), bytes = encoded(value);
    try {
      const directory = await this.directoryReady(), hot = await this.readHot(name, true);
      if (hot !== null && !encoded(hot).equals(bytes)) refuse(INTEGRITY);
      if (hot === null && await this.retained.read(name) === null) refuse(INTEGRITY);
      await this.retained.retain(name, value, hook);
      if (!encoded(await this.retained.read(name)).equals(bytes)) refuse(INTEGRITY);
      if (hot === null) return;
      const before = await this.io.lstat(path); privateFile(before);
      if (!encoded(await this.readHot(name)).equals(bytes)) refuse(INTEGRITY);
      stableFile(before, await this.io.lstat(path)); await this.directoryMatches(directory);
      await this.io.unlink(path); await this.syncDirectory(this.directory, directory);
      if (!encoded(await this.read(name)).equals(bytes)) refuse(INTEGRITY);
    } catch (error) {refuse(failureCode(error, INTEGRITY));}
  }

  async publish(name: string, value: unknown): Promise<void> {
    return this.publishEvidence(name, value, false);
  }

  async publishEmergencyDisable(name: string, value: unknown): Promise<void> {
    if (!await boundEmergencyDisableEvidence(name, value, name => this.read(name, true))) refuse(INTEGRITY);
    return this.publishEvidence(name, value, true);
  }

  private async publishEvidence(name: string, value: unknown, emergencyDisable: boolean): Promise<void> {
    const path = this.path(name);
    const data = encoded(value);
    if (this.publishingFailed) refuse(UNAVAILABLE);
    let temporary = "";
    let file: filesystem.FileHandle | undefined;
    let temporaryMayExist = false;
    try {
      const directory = await this.directoryReady();
      if (await this.retained.read(name) !== null) refuse(RECONCILE);
      if (!emergencyDisable && await this.retained.inactive()) refuse(UNAVAILABLE);
      temporary = join(this.directory,`.${name}.${randomBytes(16).toString("hex")}.tmp`);
      temporaryMayExist = true;
      file = await this.io.open(temporary,constants.O_RDWR | constants.O_CREAT | constants.O_EXCL | constants.O_NOFOLLOW,0o600);
      const created = await file.stat();
      privateFile(created);
      if (created.size !== 0) refuse(INTEGRITY);
      await file.writeFile(data);
      await file.sync();
      const before = await file.stat();
      privateFile(before);
      if (!sameNode(created,before) || before.size !== data.length) refuse(INTEGRITY);
      const readback = await boundedRead(file);
      stableFile(before,await file.stat());
      if (!readback.equals(data)) refuse(INTEGRITY);
      stableFile(before,await this.io.lstat(temporary));
      await file.close();
      file = undefined;
      await this.directoryMatches(directory);
      try {await this.io.link(temporary,path);}
      catch (error) {
        if ((error as NodeJS.ErrnoException).code === "EEXIST") refuse(RECONCILE);
        throw error;
      }
      await this.io.unlink(temporary);
      temporaryMayExist = false;
      await this.syncDirectory(this.directory,directory);
      // Archive publication may race our first lookup. The original claim
      // remains reserved even if its old hot link was removed meanwhile.
      if (await this.retained.read(name) !== null) refuse(RECONCILE);
      if (!emergencyDisable && await this.retained.inactive()) refuse(UNAVAILABLE);
      if (!encoded(await this.read(name)).equals(data)) refuse(INTEGRITY);
      await this.directoryMatches(directory);
      if (this.publishingFailed) refuse(UNAVAILABLE);
    } catch (error) {
      let code = failureCode(error,UNAVAILABLE);
      if (file !== undefined) {
        try {await file.close();} catch {code = UNAVAILABLE;}
        file = undefined;
      }
      if (temporaryMayExist) {
        try {await this.io.unlink(temporary);} catch (cleanupError) {if (!missing(cleanupError)) code = UNAVAILABLE;}
      }
      if (code !== RECONCILE) this.publishingFailed = true;
      refuse(code);
    }
  }
}
