import {constants} from "node:fs";
import * as fs from "node:fs/promises";
import {createHash} from "node:crypto";
import {dirname, isAbsolute, join} from "node:path";
import {fileURLToPath} from "node:url";
import {keys, hash, integer, uuid, utc, unattendedScope} from "./unattended_contract.ts";
import {sha256, enrollmentOrigin} from "./unattended_enrollment_contract.ts";
import {loadUnattendedProfile, type UnattendedProfile} from "./unattended_profile.ts";
import {verifyHelper} from "./unattended_profile_preparation.ts";
import {retentionPolicySha256} from "./unattended_retained.ts";

export const schedulerLabel = "com.ikanisa.collect.receipt-operations";
export interface PreparedDeployment {
  contract_version: 2; kind: "prepared_launchd_job"; installed: false; started: false;
  credentials_created: false; profile_verified: false; uid: number; label: typeof schedulerLabel;
  origin: typeof enrollmentOrigin; scope: typeof unattendedScope; interval_seconds: number; max_events: number;
  profile_path: string; profile_sha256: string; identity: UnattendedProfile["identity"];
  helper_path: string; helper_sha256: string; key_tag_id: string | null; journal_directory: string;
  node_path: string; source_directory: string; runtime_inputs: Record<string, string>; artifacts: Record<string, string>;
  dependency_links: Record<string, string>;
  retention_policy_sha256?: string;
}
export interface Deployment {directory: string; manifest: PreparedDeployment; manifestSha: string; profile?: UnattendedProfile}
export async function assertSchedulerExecutionBinding(deployment: Deployment) {
  const source = await fs.realpath(fileURLToPath(new URL("../", import.meta.url))), node = await fs.realpath(process.execPath);
  if (deployment.manifest.source_directory !== source || deployment.manifest.node_path !== node) throw Error("SCHEDULER_EXECUTION_BINDING_REQUIRED");
}
export function selectedSchedulerPath(value: unknown): value is string {
  return typeof value === "string" && value.length <= 4096 && isAbsolute(value) && !/[\r\n\0\\]/.test(value);
}
export async function schedulerDirectory(path: string) {
  if (!selectedSchedulerPath(path) || !process.getuid) throw Error("SCHEDULER_DEPLOYMENT_UNVERIFIED");
  let item = path;
  for (;;) {
    const stat = await fs.lstat(item);
    if (!stat.isDirectory() || stat.isSymbolicLink()) throw Error("SCHEDULER_DEPLOYMENT_UNVERIFIED");
    const parent = dirname(item); if (parent === item) break; item = parent;
  }
  const stat = await fs.lstat(path);
  if (stat.uid !== process.getuid() || (stat.mode & 0o7777) !== 0o700) throw Error("SCHEDULER_DEPLOYMENT_UNVERIFIED");
}
/** Bounded descriptor read/hash with pathname identity readback. No contents
 * or native errors are returned to the operating CLI. */
export async function schedulerFile(path: string, maximum: number, privateFile = false): Promise<{bytes: Buffer; sha: string}> {
  let file;
  try {
    if (!selectedSchedulerPath(path) || !process.getuid) throw Error();
    let item = path;
    for (;;) {if ((await fs.lstat(item)).isSymbolicLink()) throw Error(); const parent = dirname(item); if (parent === item) break; item = parent;}
    file = await fs.open(path, constants.O_RDONLY | constants.O_NOFOLLOW);
    const before = await file.stat();
    if (!before.isFile() || before.uid !== process.getuid() || before.nlink !== 1 || before.size > maximum ||
        (before.mode & 0o022) !== 0 || privateFile && (before.mode & 0o7777) !== 0o600) throw Error();
    const chunks: Buffer[] = [], checksum = createHash("sha256"); let size = 0;
    while (size <= maximum) {
      const data = Buffer.alloc(Math.min(65536, maximum + 1 - size));
      const {bytesRead} = await file.read(data, 0, data.length, size);
      if (bytesRead === 0) break; const part = data.subarray(0, bytesRead); size += bytesRead; checksum.update(part); chunks.push(part);
    }
    if (size !== before.size || size > maximum) throw Error();
    for (const stat of [await file.stat(), await fs.lstat(path)]) if (stat.dev !== before.dev || stat.ino !== before.ino ||
      stat.uid !== before.uid || stat.mode !== before.mode || stat.nlink !== before.nlink || stat.size !== before.size ||
      stat.mtimeMs !== before.mtimeMs || stat.ctimeMs !== before.ctimeMs) throw Error();
    return {bytes: Buffer.concat(chunks), sha: checksum.digest("hex")};
  } catch {throw Error("SCHEDULER_DEPLOYMENT_UNVERIFIED");}
  finally {await file?.close().catch(() => {});}
}
const quote = (text: string) => /^[A-Za-z0-9_@%+=:,./-]+$/.test(text) ? text : `'${text.replaceAll("'", "'\"'\"'")}'`;
const escape = (value: string) => value.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;");
function xml(value: unknown, depth: number): string {
  const indent = "\t".repeat(depth);
  if (typeof value === "string") return `${indent}<string>${escape(value)}</string>\n`;
  if (typeof value === "number") return `${indent}<integer>${value}</integer>\n`;
  if (typeof value === "boolean") return `${indent}<${value ? "true" : "false"}/>\n`;
  if (Array.isArray(value)) return `${indent}<array>\n${value.map(row => xml(row, depth + 1)).join("")}${indent}</array>\n`;
  if (value && typeof value === "object") return `${indent}<dict>\n${Object.entries(value).sort(([a], [b]) => a < b ? -1 : 1).map(([name, row]) => `${indent}\t<key>${escape(name)}</key>\n${xml(row, depth + 1)}`).join("")}${indent}</dict>\n`;
  throw Error("SCHEDULER_DEPLOYMENT_UNVERIFIED");
}
export function expectedSchedulerPlist(directory: string, interval: number) {
  const job = {Label: schedulerLabel, ProgramArguments: ["/bin/sh", join(directory, "tick.sh")], StartInterval: interval,
    RunAtLoad: false, KeepAlive: false, ProcessType: "Background", ThrottleInterval: interval, Umask: 63,
    EnvironmentVariables: {PATH: "/usr/bin:/bin", LANG: "C"}, StandardOutPath: "/dev/null", StandardErrorPath: "/dev/null"};
  return '<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0">\n' + xml(job, 0) + '</plist>\n';
}
function validManifest(value: unknown, historicalUid = process.getuid?.()): value is PreparedDeployment {
  return keys(value, ["contract_version", "kind", "installed", "started", "credentials_created", "profile_verified", "interval_seconds", "max_events", "uid", "label", "origin", "scope", "profile_path", "profile_sha256", "identity", "helper_path", "helper_sha256", "key_tag_id", "journal_directory", "node_path", "source_directory", "runtime_inputs", "dependency_links", "artifacts", ...(value && typeof value === "object" && Object.hasOwn(value, "retention_policy_sha256") ? ["retention_policy_sha256"] : [])]) &&
    value.contract_version === 2 && value.kind === "prepared_launchd_job" && value.installed === false && value.started === false &&
    value.credentials_created === false && value.profile_verified === false && value.uid === historicalUid && value.label === schedulerLabel &&
    value.origin === enrollmentOrigin && value.scope === unattendedScope && integer(value.interval_seconds, 60, 3600) && integer(value.max_events, 1, 10) &&
    selectedSchedulerPath(value.profile_path) && selectedSchedulerPath(value.helper_path) && selectedSchedulerPath(value.journal_directory) &&
    selectedSchedulerPath(value.node_path) && selectedSchedulerPath(value.source_directory) && hash(value.profile_sha256) && hash(value.helper_sha256) &&
    (value.key_tag_id === null || uuid(value.key_tag_id)) && keys(value.identity, ["principalId", "keySha256", "expiresAt"]) &&
    uuid(value.identity.principalId) && hash(value.identity.keySha256) && utc(value.identity.expiresAt) &&
    keys(value.artifacts, ["runtime.sha256", "tick.sh", `${schedulerLabel}.plist`]) && Object.values(value.artifacts).every(hash) &&
    value.runtime_inputs !== null && typeof value.runtime_inputs === "object" && !Array.isArray(value.runtime_inputs) &&
    Object.keys(value.runtime_inputs).length >= 6 && Object.keys(value.runtime_inputs).length <= 20000 && Object.values(value.runtime_inputs).every(hash) &&
    value.dependency_links !== null && typeof value.dependency_links === "object" && !Array.isArray(value.dependency_links) && Object.keys(value.dependency_links).length <= 20000 &&
    Object.values(value.dependency_links).every(target => typeof target === "string" && target.length <= 4096 && !isAbsolute(target) && !/[\r\n\0\\]/.test(target));
}
function schedulerMetadataBindings(value: PreparedDeployment): void {
  if (value.retention_policy_sha256 !== undefined && (value.retention_policy_sha256 !== retentionPolicySha256 ||
    ["unattended_retained.ts", "unattended_retention.ts"].some(name => !hash(value.runtime_inputs[join(value.source_directory, "src", name)])))) throw Error();
  const entries = Object.entries(value.runtime_inputs);
  const dependencyLinks = Object.entries(value.dependency_links);
  for (const [path] of dependencyLinks) if (!selectedSchedulerPath(path) || !path.startsWith(`${value.source_directory}/node_modules/`) ||
    path.split("/").includes(".bin") || Object.hasOwn(value.runtime_inputs, path)) throw Error();
  for (const [path] of entries) if (!selectedSchedulerPath(path) || ![value.node_path, value.profile_path, value.helper_path, join(value.source_directory, "package.json"), join(value.source_directory, "pnpm-lock.yaml")].includes(path) &&
    !path.startsWith(`${value.source_directory}/src/`) && !path.startsWith(`${value.source_directory}/node_modules/`)) throw Error();
  for (const path of [value.node_path, value.profile_path, value.helper_path, join(value.source_directory, "package.json"), join(value.source_directory, "pnpm-lock.yaml"), join(value.source_directory, "src/unattended_host_tick.ts")]) if (!hash(value.runtime_inputs[path])) throw Error();
  if (value.runtime_inputs[value.profile_path] !== value.profile_sha256 || value.runtime_inputs[value.helper_path] !== value.helper_sha256) throw Error();
}
function schedulerArtifacts(directory: string, value: PreparedDeployment): [string, string][] {
  const entries = Object.entries(value.runtime_inputs), dependencyLinks = Object.entries(value.dependency_links);
  const sums = entries.map(([path, digest]) => `${digest}  ${path}\n`).join("");
  const command = [value.node_path, "--experimental-strip-types", join(value.source_directory, "src/unattended_host_tick.ts"), "--deployment", directory];
  const wrapper = '#!/bin/sh\nset -eu\n/usr/bin/env -i PATH=/usr/bin:/bin LANG=C /usr/bin/shasum -a 256 -c ' + quote(join(directory, "runtime.sha256")) + ' >/dev/null 2>&1 || exit 78\n' +
    dependencyLinks.map(([path, target]) => `[ "$(/usr/bin/env -i PATH=/usr/bin:/bin LANG=C /usr/bin/readlink ${quote(path)})" = ${quote(target)} ] || exit 78\n`).join("") +
    'exec /usr/bin/env -i PATH=/usr/bin:/bin LANG=C ' + command.map(quote).join(" ") + '\n';
  return [["runtime.sha256", sums], ["tick.sh", wrapper], [`${schedulerLabel}.plist`, expectedSchedulerPlist(directory, value.interval_seconds)]];
}
/** Historical configuration only. Deliberately lacks live Deployment.directory
 * and never checks/loads the helper, credentials, runtime or host daemon. */
export interface CapturedSchedulerConfiguration {
  kind: "inert_scheduler_configuration"; source_deployment_directory: string;
  manifest: PreparedDeployment; manifest_sha256: string; profile: UnattendedProfile;
}
export function capturedSchedulerConfiguration(directory: string, manifestBytes: Buffer, profileBytes: Buffer,
  artifacts: Record<string, Buffer>): CapturedSchedulerConfiguration {
  try {
    const value: unknown = JSON.parse(manifestBytes.toString("utf8"));
    if (!selectedSchedulerPath(directory) || manifestBytes.length > 4 * 1024 * 1024 ||
        !value || typeof value !== "object" || !integer((value as {uid?: unknown}).uid, 0, 2147483647) ||
        !validManifest(value, (value as {uid: number}).uid)) throw Error();
    schedulerMetadataBindings(value);
    const profile: unknown = JSON.parse(profileBytes.toString("utf8"));
    const tagged = profile !== null && typeof profile === "object" && Object.hasOwn(profile, "key_tag_id");
    if (profileBytes.length > 8192 || !keys(profile, ["contract_version", "scope", "identity", "helper_path", "helper_sha256", "journal_directory", ...(tagged ? ["key_tag_id"] : [])]) || tagged && !uuid(profile.key_tag_id) ||
        profile.contract_version !== 2 || profile.scope !== unattendedScope || !keys(profile.identity, ["principalId", "keySha256", "expiresAt"]) ||
        profile.identity.principalId !== value.identity.principalId || profile.identity.keySha256 !== value.identity.keySha256 || profile.identity.expiresAt !== value.identity.expiresAt || profile.helper_path !== value.helper_path || profile.helper_sha256 !== value.helper_sha256 ||
        profile.journal_directory !== value.journal_directory || (profile.key_tag_id ?? null) !== value.key_tag_id ||
        sha256(profileBytes) !== value.profile_sha256 || JSON.stringify(profile) + "\n" !== profileBytes.toString("utf8")) throw Error();
    if (Object.keys(artifacts).sort().join() !== Object.keys(value.artifacts).sort().join()) throw Error();
    for (const [name, expected] of schedulerArtifacts(directory, value)) {
      const bytes = artifacts[name];
      if (!bytes || bytes.length > 4 * 1024 * 1024 || sha256(bytes) !== value.artifacts[name] || bytes.toString("utf8") !== expected) throw Error();
    }
    return {kind: "inert_scheduler_configuration", source_deployment_directory: directory,
      manifest: value, manifest_sha256: sha256(manifestBytes), profile: profile as unknown as UnattendedProfile};
  } catch {throw Error("SCHEDULER_RECOVERY_CONFIGURATION_UNVERIFIED");}
}
export async function loadSchedulerDeployment(directory: string, verifyRuntime = false): Promise<Deployment> {
  try {
    await schedulerDirectory(directory); await schedulerDirectory(join(directory, "control"));
    const manifest = await schedulerFile(join(directory, "PREPARATION.json"), 4 * 1024 * 1024, true);
    const value: unknown = JSON.parse(manifest.bytes.toString("utf8")); if (!validManifest(value)) throw Error();
    schedulerMetadataBindings(value);
    const entries = Object.entries(value.runtime_inputs), dependencyLinks = Object.entries(value.dependency_links);
    for (const [name, expected] of schedulerArtifacts(directory, value)) {
      const file = await schedulerFile(join(directory, name), 4 * 1024 * 1024, true);
      if (file.sha !== value.artifacts[name] || file.bytes.toString("utf8") !== expected) throw Error();
    }
    const result: Deployment = {directory, manifest: value, manifestSha: manifest.sha};
    if (verifyRuntime) {
      for (const [path, target] of dependencyLinks) {
        const resolved = await fs.realpath(path);
        if (!resolved.startsWith(`${value.source_directory}/node_modules/`) || await fs.readlink(path) !== target) throw Error();
      }
      let total = 0;
      for (const [path, digest] of entries) {const file = await schedulerFile(path, 256 * 1024 * 1024); total += file.bytes.length; if (file.sha !== digest || total > 512 * 1024 * 1024) throw Error();}
      const profile = await loadUnattendedProfile(value.profile_path);
      if (sha256(JSON.stringify(profile) + "\n") !== value.profile_sha256 || profile.identity.principalId !== value.identity.principalId ||
          profile.identity.keySha256 !== value.identity.keySha256 || profile.identity.expiresAt !== value.identity.expiresAt ||
          profile.helper_path !== value.helper_path || profile.helper_sha256 !== value.helper_sha256 || profile.journal_directory !== value.journal_directory ||
          (profile.key_tag_id ?? null) !== value.key_tag_id) throw Error();
      await verifyHelper({helper_path: profile.helper_path, helper_sha256: profile.helper_sha256, ...(profile.key_tag_id ? {key_tag_id: profile.key_tag_id} : {})});
      result.profile = profile;
    }
    if ((await schedulerFile(join(directory, "PREPARATION.json"), 4 * 1024 * 1024, true)).sha !== manifest.sha) throw Error();
    return result;
  } catch {throw Error("SCHEDULER_DEPLOYMENT_UNVERIFIED");}
}
