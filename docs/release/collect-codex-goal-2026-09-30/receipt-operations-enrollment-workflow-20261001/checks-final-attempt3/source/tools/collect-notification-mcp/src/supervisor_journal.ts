import {createHash, randomBytes} from "node:crypto";
import * as filesystem from "node:fs/promises";
import {constants} from "node:fs";
import {basename, dirname, isAbsolute, join, resolve} from "node:path";
import {callSupervisor, supervisorAudience} from "./supervisor_client.ts";
import type {SupervisorIdentity, SupervisorSigner} from "./supervisor_client.ts";

export const supervisorJournalScope = "rw_receipt_shadow";
export const supervisorNegativeLookupHorizonMs = 120_000;
type Action = "prove_key" | "shadow_health";
type Json = Record<string, unknown>;
type JournalIO = Pick<typeof filesystem, "lstat" | "mkdir" | "open" | "link" | "unlink">;
export interface SupervisorJournalRequest {action: Action; requestId: string}
export interface SupervisorJournalOutcome {
  contract_version: 1; scope: typeof supervisorJournalScope; principal_id: string;
  request_id: string; action: Action; outcome: "recorded" | "not_recorded" | "unknown";
  reason_code: string; envelope_sha256: string | null; issued_at: string | null;
  observed_at: string | null; lookup_request_id: string | null;
  business_handled: false; financial_action: false; send_action: false;
}
interface Checkpoint {
  contract_version: 1; scope: typeof supervisorJournalScope; audience: string;
  principal_id: string; key_sha256: string; expires_at: string; request_id: string;
  action: Action | "reconcile"; target_request_id: string | null; created_at: string;
}
interface Armed {
  contract_version: 1; request_id: string; envelope_sha256: string; issued_at: string;
  not_recorded_before: string;
}
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const HASH = /^[0-9a-f]{64}$/;
const safeReasons = new Set([
  "SUPERVISOR_METHOD_REFUSED", "SUPERVISOR_REQUEST_INVALID", "SUPERVISOR_KEY_REFUSED",
  "SUPERVISOR_BODY_TOO_LARGE", "SUPERVISOR_SIGNATURE_REFUSED", "SUPERVISOR_AUTHORITY_REFUSED",
  "SUPERVISOR_PRINCIPAL_PENDING", "SUPERVISOR_AUTHORITY_BUSY", "SUPERVISOR_REQUEST_REFUSED",
  "SUPERVISOR_AUTH_UNAVAILABLE", "SUPERVISOR_OUTCOME_UNKNOWN", "SUPERVISOR_SIGNING_UNAVAILABLE",
  "SUPERVISOR_LOOKUP_UNAVAILABLE", "SUPERVISOR_JOURNAL_UNAVAILABLE",
  "SUPERVISOR_JOURNAL_INTEGRITY_REQUIRED", "SUPERVISOR_REQUEST_RECONCILIATION_REQUIRED",
  "SUPERVISOR_SHADOW_OBSERVATION_RECORDED", "SUPERVISOR_ORIGINAL_REQUEST_NOT_RECORDED",
  "SUPERVISOR_ORIGINAL_REQUEST_IN_PROGRESS", "SUPERVISOR_ORIGINAL_REQUEST_WINDOW_OPEN",
]);
class JournalError extends Error {}
function refuse(code: string): never {throw new JournalError(code);}
function object(value: unknown): value is Json {return value !== null && typeof value === "object" && !Array.isArray(value);}
function keys(value: unknown, names: string[]): value is Json {
  return object(value) && Object.keys(value).length === names.length && names.every(name => Object.hasOwn(value,name));
}
function utc(value: unknown): value is string {
  return typeof value === "string" && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?Z$/.test(value) &&
    Number.isFinite(Date.parse(value)) && new Date(Date.parse(value)).toISOString().slice(0,19) === value.slice(0,19);
}
function clock(now: () => number): number {
  const at = now();
  if (!Number.isSafeInteger(at) || at < 0 || at > 253402300799999) refuse("SUPERVISOR_ARGUMENTS_INVALID");
  return at;
}
function validIdentity(identity: SupervisorIdentity, now: () => number) {
  if (!keys(identity,["principalId","keySha256","expiresAt"]) ||
      typeof identity.principalId !== "string" || !UUID.test(identity.principalId) ||
      typeof identity.keySha256 !== "string" || !HASH.test(identity.keySha256) ||
      !utc(identity.expiresAt) || Date.parse(identity.expiresAt) <= clock(now) + 5000) refuse("SUPERVISOR_ARGUMENTS_INVALID");
}
function digest(data: Uint8Array) {return createHash("sha256").update(data).digest("hex");}
function ownerUid() {
  if (typeof process.getuid !== "function") refuse("SUPERVISOR_JOURNAL_UNAVAILABLE");
  return process.getuid();
}
function encoded(value: unknown) {return Buffer.from(JSON.stringify(value) + "\n");}
function reason(error: unknown, fallback = "SUPERVISOR_OUTCOME_UNKNOWN") {
  return error instanceof Error && safeReasons.has(error.message) ? error.message : fallback;
}
function checkpoint(value: unknown): value is Checkpoint {
  return keys(value,["contract_version","scope","audience","principal_id","key_sha256","expires_at","request_id","action","target_request_id","created_at"]) &&
    value.contract_version === 1 && value.scope === supervisorJournalScope && value.audience === supervisorAudience &&
    typeof value.principal_id === "string" && UUID.test(value.principal_id) && typeof value.key_sha256 === "string" && HASH.test(value.key_sha256) &&
    utc(value.expires_at) && utc(value.created_at) && Date.parse(value.created_at) < Date.parse(value.expires_at) &&
    typeof value.request_id === "string" && UUID.test(value.request_id) &&
    ((["prove_key","shadow_health"].includes(value.action as string) && value.target_request_id === null) ||
     (value.action === "reconcile" && typeof value.target_request_id === "string" && UUID.test(value.target_request_id) && value.request_id !== value.target_request_id));
}
function armed(value: unknown, original: Checkpoint): value is Armed {
  return keys(value,["contract_version","request_id","envelope_sha256","issued_at","not_recorded_before"]) &&
    value.contract_version === 1 && value.request_id === original.request_id && typeof value.envelope_sha256 === "string" && HASH.test(value.envelope_sha256) &&
    utc(value.issued_at) && utc(value.not_recorded_before) && Date.parse(value.issued_at) >= Date.parse(original.created_at) &&
    Date.parse(value.issued_at) < Date.parse(original.expires_at) &&
    Date.parse(value.not_recorded_before) === Date.parse(value.issued_at) + supervisorNegativeLookupHorizonMs;
}

/** Append-only owner-private evidence. UUID reservation is atomic across processes
 * and survives restart. No mutation is ever reissued from a checkpoint. */
export class SupervisorJournal {
  readonly directory: string;
  private readonly io: JournalIO;
  constructor(directory: string, io: JournalIO = filesystem) {
    if (typeof directory !== "string" || !isAbsolute(directory)) refuse("SUPERVISOR_ARGUMENTS_INVALID");
    this.directory = resolve(directory);
    this.io = io;
  }
  private async directoryReady() {
    try {
      let ancestor = this.directory;
      while (true) {
        try {if ((await this.io.lstat(ancestor)).isSymbolicLink()) refuse("SUPERVISOR_JOURNAL_UNAVAILABLE");}
        catch (error) {if ((error as NodeJS.ErrnoException).code !== "ENOENT" || ancestor !== this.directory) throw error;}
        if (dirname(ancestor) === ancestor) break;
        ancestor = dirname(ancestor);
      }
      if (typeof process.getuid !== "function") refuse("SUPERVISOR_JOURNAL_UNAVAILABLE");
      try {await this.io.lstat(this.directory);}
      catch (error) {
        if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
        const parent = await this.io.lstat(dirname(this.directory));
        if (!parent.isDirectory() || parent.uid !== ownerUid() || (parent.mode & 0o777) !== 0o700) refuse("SUPERVISOR_JOURNAL_UNAVAILABLE");
        try {await this.io.mkdir(this.directory,{mode:0o700});}
        catch (createError) {if ((createError as NodeJS.ErrnoException).code !== "EEXIST") throw createError;}
      }
      const info = await this.io.lstat(this.directory);
      if (!info.isDirectory() || info.isSymbolicLink() || info.uid !== ownerUid() || (info.mode & 0o777) !== 0o700) refuse("SUPERVISOR_JOURNAL_UNAVAILABLE");
    } catch {refuse("SUPERVISOR_JOURNAL_UNAVAILABLE");}
  }
  private path(requestId: string, kind: "checkpoint" | "armed" | "outcome" | "observation") {
    if (!UUID.test(requestId)) refuse("SUPERVISOR_ARGUMENTS_INVALID");
    return join(this.directory,`${requestId}.${kind}.json`);
  }
  private async read(path: string, optional = false): Promise<unknown | null> {
    await this.directoryReady();
    let file: filesystem.FileHandle | undefined;
    try {
      file = await this.io.open(path,constants.O_RDONLY | constants.O_NOFOLLOW);
      const info = await file.stat();
      if (!info.isFile() || info.uid !== ownerUid() || (info.mode & 0o777) !== 0o600 || info.nlink !== 1 || info.size > 8192) refuse("SUPERVISOR_JOURNAL_INTEGRITY_REQUIRED");
      const data = await file.readFile();
      const after = await file.stat();
      if (data.length !== info.size || info.size !== after.size || info.mtimeMs !== after.mtimeMs || info.ctimeMs !== after.ctimeMs) refuse("SUPERVISOR_JOURNAL_INTEGRITY_REQUIRED");
      const value: unknown = JSON.parse(data.toString("utf8"));
      if (!encoded(value).equals(data)) refuse("SUPERVISOR_JOURNAL_INTEGRITY_REQUIRED");
      return value;
    } catch (error) {
      if (optional && (error as NodeJS.ErrnoException).code === "ENOENT") return null;
      refuse("SUPERVISOR_JOURNAL_INTEGRITY_REQUIRED");
    } finally {await file?.close().catch(() => {});}
  }
  private async publish(path: string, value: unknown) {
    await this.directoryReady();
    const data = encoded(value);
    if (data.length > 8192) refuse("SUPERVISOR_JOURNAL_UNAVAILABLE");
    const temporary = join(this.directory,`.${basename(path)}.${randomBytes(12).toString("hex")}.tmp`);
    let file: filesystem.FileHandle | undefined;
    let directory: filesystem.FileHandle | undefined;
    try {
      file = await this.io.open(temporary,constants.O_WRONLY | constants.O_CREAT | constants.O_EXCL | constants.O_NOFOLLOW,0o600);
      await file.writeFile(data); await file.sync(); await file.close(); file = undefined;
      try {await this.io.link(temporary,path);}
      catch (error) {
        if ((error as NodeJS.ErrnoException).code === "EEXIST") refuse("SUPERVISOR_REQUEST_RECONCILIATION_REQUIRED");
        throw error;
      }
      await this.io.unlink(temporary);
      directory = await this.io.open(this.directory,constants.O_RDONLY);
      await directory.sync(); await directory.close(); directory = undefined;
      if (!encoded(await this.read(path)).equals(data)) refuse("SUPERVISOR_JOURNAL_INTEGRITY_REQUIRED");
    } catch (error) {refuse(reason(error,"SUPERVISOR_JOURNAL_UNAVAILABLE"));}
    finally {
      await file?.close().catch(() => {}); await directory?.close().catch(() => {});
      await this.io.unlink(temporary).catch(() => {});
    }
  }
  private summary(original: Checkpoint, record: Armed | null, outcome: SupervisorJournalOutcome["outcome"], code: string,
                  observed: string | null = null, lookup: string | null = null): SupervisorJournalOutcome {
    return {contract_version:1,scope:supervisorJournalScope,principal_id:original.principal_id,request_id:original.request_id,
      action:original.action as Action,outcome,reason_code:code,envelope_sha256:record?.envelope_sha256 ?? null,
      issued_at:record?.issued_at ?? null,observed_at:observed,lookup_request_id:lookup,
      business_handled:false,financial_action:false,send_action:false};
  }
  private async original(requestId: string) {
    const value = await this.read(this.path(requestId,"checkpoint"));
    if (!checkpoint(value) || value.request_id !== requestId || value.action === "reconcile") refuse("SUPERVISOR_JOURNAL_INTEGRITY_REQUIRED");
    const record = await this.read(this.path(requestId,"armed"),true);
    if (record !== null && !armed(record,value)) refuse("SUPERVISOR_JOURNAL_INTEGRITY_REQUIRED");
    return {value,record:record as Armed | null};
  }
  private boundCall(item: Checkpoint, signer: SupervisorSigner, fetcher: typeof fetch, now: () => number, timeout: number) {
    let used = false;
    const identity = {principalId:item.principal_id,keySha256:item.key_sha256,expiresAt:item.expires_at};
    const signing: SupervisorSigner = async (bytes,signal) => {
      signal.throwIfAborted();
      const envelope = JSON.parse(new TextDecoder().decode(bytes)) as Json;
      const expected = {action:item.action,audience:supervisorAudience,contract_version:1,issued_at:envelope.issued_at,
        payload:item.action === "reconcile" ? {target_request_id:item.target_request_id} : {},principal_id:item.principal_id,request_id:item.request_id};
      if (!utc(envelope.issued_at) || Date.parse(envelope.issued_at) < Date.parse(item.created_at) ||
          !Buffer.from(JSON.stringify(expected)).equals(Buffer.from(bytes))) refuse("SUPERVISOR_JOURNAL_INTEGRITY_REQUIRED");
      const signature = await signer(bytes,signal);
      signal.throwIfAborted();
      if (!keys(signature,["keySha256","signature"]) || signature.keySha256 !== item.key_sha256 ||
          typeof signature.signature !== "string" || signature.signature.length > 100 ||
          !/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(signature.signature) ||
          Buffer.from(signature.signature,"base64").toString("base64") !== signature.signature ||
          Buffer.from(signature.signature,"base64").length < 8) refuse("SUPERVISOR_SIGNING_UNAVAILABLE");
      const record: Armed = {contract_version:1,request_id:item.request_id,envelope_sha256:digest(bytes),issued_at:envelope.issued_at,
        not_recorded_before:new Date(Date.parse(envelope.issued_at) + supervisorNegativeLookupHorizonMs).toISOString()};
      await this.publish(this.path(item.request_id,"armed"),record);
      signal.throwIfAborted();
      return signature;
    };
    const transport: typeof fetch = async (url,options) => {
      if (used) refuse("SUPERVISOR_REQUEST_RECONCILIATION_REQUIRED");
      used = true; options?.signal?.throwIfAborted();
      const record = await this.read(this.path(item.request_id,"armed"));
      const request = await this.read(this.path(item.request_id,"checkpoint"));
      if (!armed(record,item) || !encoded(request).equals(encoded(item)) || typeof options?.body !== "string" ||
          digest(Buffer.from(options.body)) !== record.envelope_sha256) refuse("SUPERVISOR_JOURNAL_INTEGRITY_REQUIRED");
      options?.signal?.throwIfAborted();
      return await fetcher(url,options);
    };
    return callSupervisor(identity,item.action === "reconcile"
      ? {action:"reconcile",requestId:item.request_id,targetRequestId:item.target_request_id!}
      : {action:item.action,requestId:item.request_id},signing,transport,now,timeout);
  }
  /** Valid arguments may still fail closed before HTTP. The supplied UUID is
   * always returned; existing reservations require manual lookup, never replay. */
  async once(identity: SupervisorIdentity, input: SupervisorJournalRequest, signer: SupervisorSigner,
             fetcher: typeof fetch = fetch, now: () => number = Date.now, timeoutMs = 5000): Promise<SupervisorJournalOutcome> {
    validIdentity(identity,now);
    if (!keys(input,["action","requestId"]) || !["prove_key","shadow_health"].includes(input.action) ||
        typeof input.requestId !== "string" || !UUID.test(input.requestId) || typeof signer !== "function" ||
        typeof fetcher !== "function" || !Number.isSafeInteger(timeoutMs) || timeoutMs < 1 || timeoutMs > 15000) refuse("SUPERVISOR_ARGUMENTS_INVALID");
    const item: Checkpoint = {contract_version:1,scope:supervisorJournalScope,audience:supervisorAudience,
      principal_id:identity.principalId,key_sha256:identity.keySha256,expires_at:identity.expiresAt,
      request_id:input.requestId,action:input.action,target_request_id:null,created_at:new Date(clock(now)).toISOString()};
    let record: Armed | null = null;
    try {
      await this.publish(this.path(item.request_id,"checkpoint"),item);
      let outcome: SupervisorJournalOutcome;
      try {
        const response = await this.boundCall(item,signer,fetcher,now,timeoutMs);
        const value = await this.read(this.path(item.request_id,"armed"));
        if (!armed(value,item)) refuse("SUPERVISOR_JOURNAL_INTEGRITY_REQUIRED");
        record = value;
        outcome = this.summary(item,record,"recorded","SUPERVISOR_SHADOW_OBSERVATION_RECORDED",response.result.observed_at as string);
      } catch (error) {
        const value = await this.read(this.path(item.request_id,"armed"),true);
        if (value !== null && !armed(value,item)) refuse("SUPERVISOR_JOURNAL_INTEGRITY_REQUIRED");
        record = value as Armed | null;
        outcome = this.summary(item,record,"unknown",reason(error));
      }
      await this.publish(this.path(item.request_id,"outcome"),outcome);
      return outcome;
    } catch (error) {return this.summary(item,record,"unknown",reason(error,"SUPERVISOR_JOURNAL_UNAVAILABLE"));}
  }
  /** Local historical evidence only; this method cannot call the backend. */
  async readOriginal(requestId: string): Promise<SupervisorJournalOutcome> {
    if (typeof requestId !== "string" || !UUID.test(requestId)) refuse("SUPERVISOR_ARGUMENTS_INVALID");
    const {value,record} = await this.original(requestId);
    const result = await this.read(this.path(requestId,"outcome"),true);
    if (result !== null && (!keys(result,Object.keys(this.summary(value,record,"unknown","SUPERVISOR_OUTCOME_UNKNOWN"))) ||
        !["recorded","unknown"].includes(result.outcome as string) || typeof result.reason_code !== "string" || !safeReasons.has(result.reason_code) ||
        (result.outcome === "recorded" && (record === null || !utc(result.observed_at) ||
          result.reason_code !== "SUPERVISOR_SHADOW_OBSERVATION_RECORDED" || Date.parse(result.observed_at) < Date.parse(value.created_at) - 10000 ||
          Date.parse(result.observed_at) >= Date.parse(value.expires_at))) ||
        (result.outcome === "unknown" && (result.observed_at !== null || result.reason_code === "SUPERVISOR_SHADOW_OBSERVATION_RECORDED")) ||
        !encoded(this.summary(value,record,result.outcome as "recorded" | "unknown",result.reason_code,
          result.observed_at as string | null)).equals(encoded(result)))) refuse("SUPERVISOR_JOURNAL_INTEGRITY_REQUIRED");
    const observed = await this.read(this.path(requestId,"observation"),true);
    if (observed !== null) {
      if (!object(observed) || record === null || observed.outcome !== "recorded" || !utc(observed.observed_at) ||
          Date.parse(observed.observed_at) < Date.parse(value.created_at) - 10000 || Date.parse(observed.observed_at) >= Date.parse(value.expires_at) ||
          typeof observed.lookup_request_id !== "string" || !UUID.test(observed.lookup_request_id) || observed.lookup_request_id === requestId ||
          !encoded(this.summary(value,record,"recorded","SUPERVISOR_SHADOW_OBSERVATION_RECORDED",observed.observed_at,observed.lookup_request_id)).equals(encoded(observed)) ||
          (object(result) && result.outcome === "recorded" && result.observed_at !== observed.observed_at)) refuse("SUPERVISOR_JOURNAL_INTEGRITY_REQUIRED");
      return observed as unknown as SupervisorJournalOutcome;
    }
    return result === null ? this.summary(value,record,"unknown","SUPERVISOR_REQUEST_RECONCILIATION_REQUIRED") : result as unknown as SupervisorJournalOutcome;
  }
  /** A caller-supplied distinct UUID signs one fresh manual lookup. Its claim,
   * signature digest and result are append-only; original evidence is retained. */
  async reconcile(identity: SupervisorIdentity, originalRequestId: string, lookupRequestId: string, signer: SupervisorSigner,
                  fetcher: typeof fetch = fetch, now: () => number = Date.now, timeoutMs = 5000): Promise<SupervisorJournalOutcome> {
    validIdentity(identity,now);
    if (typeof originalRequestId !== "string" || !UUID.test(originalRequestId) || typeof lookupRequestId !== "string" || !UUID.test(lookupRequestId) ||
        originalRequestId === lookupRequestId || typeof signer !== "function" || typeof fetcher !== "function" ||
        !Number.isSafeInteger(timeoutMs) || timeoutMs < 1 || timeoutMs > 15000) refuse("SUPERVISOR_ARGUMENTS_INVALID");
    const {value:original,record} = await this.original(originalRequestId);
    if (identity.principalId !== original.principal_id || identity.keySha256 !== original.key_sha256 || identity.expiresAt !== original.expires_at ||
        Date.parse(original.created_at) > clock(now) + 10000 || (record && Date.parse(record.issued_at) > clock(now) + 10000)) refuse("SUPERVISOR_JOURNAL_INTEGRITY_REQUIRED");
    const item: Checkpoint = {...original,request_id:lookupRequestId,action:"reconcile",target_request_id:originalRequestId,created_at:new Date(clock(now)).toISOString()};
    let outcome: SupervisorJournalOutcome;
    let reserved = false;
    try {
      await this.publish(this.path(lookupRequestId,"checkpoint"),item);
      reserved = true;
      const response = await this.boundCall(item,signer,fetcher,now,timeoutMs);
      const result = response.result;
      if (result.status === "recorded") {
        if (record === null || !object(result.receipt) || result.receipt.action !== original.action ||
            !utc(result.receipt.observed_at) || Date.parse(result.receipt.observed_at) < Date.parse(original.created_at) - 10000) refuse("SUPERVISOR_LOOKUP_UNAVAILABLE");
        outcome = this.summary(original,record,"recorded","SUPERVISOR_SHADOW_OBSERVATION_RECORDED",result.receipt.observed_at,lookupRequestId);
      } else if (result.status === "not_recorded") {
        const prior = await this.readOriginal(originalRequestId);
        if (prior.outcome === "recorded") refuse("SUPERVISOR_LOOKUP_UNAVAILABLE");
        // Fresh reconcile was accepted by the server. Its own signing time must
        // also be beyond the original window; a local clock alone is insufficient.
        const lookup = await this.read(this.path(lookupRequestId,"armed"));
        if (!armed(lookup,item)) refuse("SUPERVISOR_JOURNAL_INTEGRITY_REQUIRED");
        if (record === null) refuse("SUPERVISOR_JOURNAL_INTEGRITY_REQUIRED");
        const horizon = record.not_recorded_before;
        const closed = Date.parse(lookup.issued_at) >= Date.parse(horizon) && clock(now) >= Date.parse(horizon);
        outcome = this.summary(original,record,closed ? "not_recorded" : "unknown",
          closed ? "SUPERVISOR_ORIGINAL_REQUEST_NOT_RECORDED" : "SUPERVISOR_ORIGINAL_REQUEST_WINDOW_OPEN",null,lookupRequestId);
      } else outcome = this.summary(original,record,"unknown","SUPERVISOR_ORIGINAL_REQUEST_IN_PROGRESS",null,lookupRequestId);
    } catch (error) {outcome = this.summary(original,record,"unknown",reason(error,"SUPERVISOR_LOOKUP_UNAVAILABLE"),null,lookupRequestId);}
    if (!reserved) return outcome;
    try {await this.publish(this.path(lookupRequestId,"outcome"),outcome);}
    catch (error) {return this.summary(original,record,"unknown",reason(error,"SUPERVISOR_JOURNAL_UNAVAILABLE"),null,lookupRequestId);}
    if (outcome.outcome === "recorded") {
      // Preserve the first reconciled observation for local restart readback;
      // subsequent manual lookups never overwrite it or the original attempt.
      try {
        const previous = await this.read(this.path(originalRequestId,"observation"),true);
        if (previous === null) await this.publish(this.path(originalRequestId,"observation"),outcome);
        else {
          const known = await this.readOriginal(originalRequestId);
          if (known.outcome !== "recorded" || known.observed_at !== outcome.observed_at) refuse("SUPERVISOR_JOURNAL_INTEGRITY_REQUIRED");
        }
      } catch (error) {return this.summary(original,record,"unknown",reason(error,"SUPERVISOR_JOURNAL_UNAVAILABLE"),null,lookupRequestId);}
    }
    return outcome;
  }
}
