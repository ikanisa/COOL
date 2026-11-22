"use strict";

const { spawn } = require("node:child_process");
const { createServer } = require("node:net");
const { setTimeout: delay } = require("node:timers/promises");

function reserveLoopbackPort() {
  return new Promise((resolve, reject) => {
    const server = createServer();
    server.unref();
    server.once("error", reject);
    server.listen(0, "127.0.0.1", () => {
      const port = server.address()?.port;
      server.close((error) => {
        if (error) reject(error);
        else if (!Number.isInteger(port)) reject(new Error("Unable to reserve a local DevTools port"));
        else resolve(port);
      });
    });
  });
}

function chromeArguments(profile, { headless = "--headless", viewport, extra = [] } = {}) {
  return [
    headless,
    "--force-device-scale-factor=1",
    "--disable-gpu",
    "--disable-background-networking",
    "--disable-component-update",
    "--disable-sync",
    "--disable-dev-shm-usage",
    "--no-sandbox",
    "--no-first-run",
    "--no-default-browser-check",
    `--user-data-dir=${profile}`,
    ...(viewport ? [`--window-size=${viewport.width},${viewport.height}`] : []),
    ...extra,
  ];
}

const mobileCaptureFlags = [
  "--disable-extensions",
  "--disable-crash-reporter",
  "--force-prefers-reduced-motion",
];

function startChrome(executable, args, log) {
  const child = spawn(executable, args, { stdio: ["ignore", "pipe", "pipe"] });
  let launchError;
  let exited = false;
  const stopped = new Promise((resolve) => {
    child.once("error", (error) => { launchError = error; });
    child.once("close", () => { exited = true; resolve(); });
  });
  let stdout = "";
  let stderr = "";
  child.stdout.setEncoding("utf8");
  child.stderr.setEncoding("utf8");
  child.stdout.on("data", (chunk) => { stdout = (stdout + chunk).slice(-4000); });
  child.stderr.on("data", (chunk) => { stderr = (stderr + chunk).slice(-4000); });
  if (log) {
    child.stdout.pipe(log, {end: false});
    child.stderr.pipe(log, {end: false});
    child.once("close", () => log.end());
  }
  return {
    get running() {
      return !launchError && !exited && child.exitCode === null && child.signalCode === null;
    },
    get stdout() { return stdout.trim(); },
    get stderr() { return stderr.trim(); },
    diagnostics() {
      return [
        `Chrome path: ${executable}`,
        `Chrome args: ${args.join(" ")}`,
        launchError && `Chrome launch: ${launchError.message}`,
        !this.running && `Chrome exit: code=${child.exitCode ?? "null"} signal=${child.signalCode ?? "null"}`,
        this.stdout && `Chrome stdout:\n${this.stdout}`,
        this.stderr && `Chrome stderr:\n${this.stderr}`,
      ].filter(Boolean).join("\n");
    },
    async stop({ graceMs = 0 } = {}) {
      if (graceMs && this.running) await Promise.race([stopped, delay(graceMs, null, { ref: false })]);
      for (const signal of ["SIGTERM", "SIGKILL"]) {
        if (!this.running) break;
        child.kill(signal);
        await Promise.race([stopped, delay(1000, null, { ref: false })]);
      }
    },
  };
}

async function startDebugChrome(executable, args, log) {
  const port = await reserveLoopbackPort();
  const origin = `http://127.0.0.1:${port}`;
  const process = startChrome(executable, [
    ...args,
    "--remote-debugging-address=127.0.0.1",
    `--remote-debugging-port=${port}`,
    "about:blank",
  ], log);
  return { origin, process };
}

function chromeProcessDeadline(chrome, timeoutMs, message) {
  const timer = setTimeout(async () => {
    console.error(message);
    await chrome.stop();
    process.exit(124);
  }, timeoutMs);
  timer.unref();
  return () => clearTimeout(timer);
}

module.exports = { chromeArguments, mobileCaptureFlags, startChrome, startDebugChrome, chromeProcessDeadline };
