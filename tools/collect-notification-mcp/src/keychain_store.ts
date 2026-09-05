import {execFile, spawn} from "node:child_process";
import {lstat, mkdir, rmdir} from "node:fs/promises";
import {dirname, isAbsolute} from "node:path";
import {setTimeout as delay} from "node:timers/promises";
import type {SessionStore} from "./session_renewal.ts";

export async function validateKeychainHelper(helper: string) {
  if (process.platform !== "darwin" || !isAbsolute(helper)) throw new Error("INVALID_OPERATOR_KEYCHAIN_HELPER");
  for (const [path, directory] of [[helper, false], [dirname(helper), true]] as const) {
    const stat = await lstat(path);
    if (stat.isSymbolicLink() || (directory ? !stat.isDirectory() : !stat.isFile()) ||
        stat.uid !== process.getuid?.() || (stat.mode & (directory ? 0o077 : 0o022))) {
      throw new Error("INVALID_OPERATOR_KEYCHAIN_HELPER");
    }
  }
}

export function keychainStore(helper: string): SessionStore {
  return {
    read: async () => {
      const raw = await new Promise<string>((resolve, reject) => {
        execFile(helper, ["read"], {timeout: 5000, maxBuffer: 16384}, (error, stdout) => {
          if (error) reject(new Error("OPERATOR_SESSION_REAUTHENTICATION_REQUIRED"));
          else resolve(stdout);
        });
      });
      try { return JSON.parse(raw) as unknown; }
      catch { throw new Error("OPERATOR_SESSION_REAUTHENTICATION_REQUIRED"); }
    },
    write: async value => {
      await new Promise<void>((resolve, reject) => {
        const child = spawn(helper, ["write"], {stdio: ["pipe", "ignore", "ignore"], timeout: 5000});
        const fail = () => reject(new Error("KEYCHAIN_SAVE_FAILED"));
        child.on("error", fail);
        child.stdin.on("error", fail);
        child.on("close", code => code === 0 ? resolve() : fail());
        child.stdin.end(JSON.stringify(value));
      });
    },
  };
}

export async function withSessionLock<T>(helper: string, action: () => Promise<T>): Promise<T> {
  // The private directory contains only an empty lock directory, never a secret.
  // Never steal or age-delete locks: after a crash, an operator must inspect it.
  const lock = `${helper}.session-lock`;
  const deadline = Date.now() + 5000;
  while (true) {
    try { await mkdir(lock, {mode: 0o700}); break; }
    catch (error) {
      if ((error as NodeJS.ErrnoException).code !== "EEXIST") throw new Error("OPERATOR_SESSION_LOCK_UNAVAILABLE");
      if (Date.now() >= deadline) throw new Error("OPERATOR_SESSION_BUSY_OR_LOCK_RECOVERY_REQUIRED");
      await delay(100);
    }
  }
  try { return await action(); }
  finally { await rmdir(lock); }
}
