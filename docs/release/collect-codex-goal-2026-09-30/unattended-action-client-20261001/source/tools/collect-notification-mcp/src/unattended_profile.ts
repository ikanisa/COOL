import {constants} from "node:fs";
import {open, lstat} from "node:fs/promises";
import type {FileHandle} from "node:fs/promises";
import {dirname, isAbsolute} from "node:path";
import {keys, uuid, hash, utc, unattendedScope} from "./unattended_contract.ts";
import type {UnattendedIdentity} from "./unattended_contract.ts";
export interface UnattendedProfile {contract_version: 2; scope: typeof unattendedScope; identity: UnattendedIdentity;
  helper_path: string; helper_sha256: string; journal_directory: string}
export interface UnattendedProfileIO {open: typeof open; lstat: typeof lstat}
const MAX_BYTES = 8192;
async function boundedRead(file: FileHandle): Promise<Buffer> {
  const bytes = Buffer.alloc(MAX_BYTES + 1);
  let length = 0;
  while (length < bytes.length) {
    const {bytesRead} = await file.read(bytes,length,bytes.length - length,length);
    if (bytesRead === 0) break;
    length += bytesRead;
  }
  if (length > MAX_BYTES) throw Error();
  return bytes.subarray(0,length);
}
/** Public identity metadata only, owner-private and explicitly selected. No
 * endpoint, bearer credential, auth loader or arbitrary profile environment. */
export async function loadUnattendedProfile(path: string, io: UnattendedProfileIO = {open,lstat}): Promise<UnattendedProfile> {
  let file;
  try {
    if (!isAbsolute(path) || !process.getuid) throw Error();
    let ancestor = path;
    for (;;) {if ((await io.lstat(ancestor)).isSymbolicLink()) throw Error(); const parent = dirname(ancestor); if (parent === ancestor) break; ancestor = parent;}
    file = await io.open(path, constants.O_RDONLY | constants.O_NOFOLLOW);
    const stat = await file.stat();
    if (!stat.isFile() || stat.uid !== process.getuid() || (stat.mode & 0o777) !== 0o600 || stat.nlink !== 1 || stat.size > MAX_BYTES) throw Error();
    const bytes = await boundedRead(file), after = await file.stat();
    if (!after.isFile() || bytes.length !== stat.size || after.size !== stat.size || after.dev !== stat.dev || after.ino !== stat.ino ||
        after.uid !== stat.uid || after.mode !== stat.mode || after.nlink !== stat.nlink || after.mtimeMs !== stat.mtimeMs || after.ctimeMs !== stat.ctimeMs) throw Error();
    const value: unknown = JSON.parse(bytes.toString("utf8"));
    if (!keys(value, ["contract_version", "scope", "identity", "helper_path", "helper_sha256", "journal_directory"]) ||
        value.contract_version !== 2 || value.scope !== unattendedScope || !keys(value.identity, ["principalId", "keySha256", "expiresAt"]) ||
        !uuid(value.identity.principalId) || !hash(value.identity.keySha256) || !utc(value.identity.expiresAt) ||
        typeof value.helper_path !== "string" || !isAbsolute(value.helper_path) || !hash(value.helper_sha256) ||
        typeof value.journal_directory !== "string" || !isAbsolute(value.journal_directory)) throw Error();
    const canonical = JSON.stringify(value) + "\n";
    if (Buffer.byteLength(canonical) > MAX_BYTES || !Buffer.from(canonical).equals(bytes)) throw Error();
    const pathname = await io.lstat(path);
    if (!pathname.isFile() || pathname.dev !== after.dev || pathname.ino !== after.ino || pathname.uid !== after.uid ||
        pathname.mode !== after.mode || pathname.nlink !== after.nlink || pathname.size !== after.size ||
        pathname.mtimeMs !== after.mtimeMs || pathname.ctimeMs !== after.ctimeMs) throw Error();
    const parent = await io.lstat(dirname(path));
    if (!parent.isDirectory() || parent.uid !== process.getuid() || (parent.mode & 0o777) !== 0o700) throw Error();
    return value as unknown as UnattendedProfile;
  } catch {throw new Error("UNATTENDED_PROFILE_UNAVAILABLE");}
  finally {await file?.close().catch(() => {});}
}
