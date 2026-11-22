"use strict";

const { setTimeout: delay } = require("node:timers/promises");

function withTimeout(promise, timeoutMs, label) {
  let timer;
  const expired = new Promise((_, reject) => {
    timer = setTimeout(() => reject(new Error(`${label} timed out after ${timeoutMs}ms`)), timeoutMs);
  });
  return Promise.race([promise, expired]).finally(() => clearTimeout(timer));
}

async function readDevTools(origin, target, { method = "GET", timeoutMs = 2000 } = {}) {
  const response = await fetch(new URL(target, origin), {
    method, redirect: "error", signal: AbortSignal.timeout(timeoutMs),
  });
  if (!response.ok) throw new Error(`DevTools ${target} returned HTTP ${response.status}`);
  return response.json();
}

function localSocketUrl(value, origin) {
  const address = new URL(value);
  const endpoint = new URL(origin);
  if (address.protocol !== "ws:" || address.host !== endpoint.host || address.username || address.password) {
    throw new Error("Chrome returned a DevTools socket outside its loopback endpoint");
  }
  return address.href;
}

async function waitForDevTools({ origin, process }, timeoutMs) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline && process.running) {
    let version;
    try {
      version = await readDevTools(origin, "/json/version", {
        timeoutMs: Math.max(1, Math.min(2000, deadline - Date.now())),
      });
    } catch {
      // Chromium has not opened its DevTools listener yet.
    }
    if (version?.webSocketDebuggerUrl) return localSocketUrl(version.webSocketDebuggerUrl, origin);
    await delay(100);
  }
  const message = process.running ? "Chrome DevTools endpoint did not become ready" : "Chrome exited before DevTools became ready";
  throw new Error(`${message}.\n${process.diagnostics()}`);
}

async function connectDevTools(url, { timeoutMs = 15000, onEvent } = {}) {
  const socket = new WebSocket(url);
  let nextId = 1;
  const pending = new Map();
  const events = new Map();
  let ready = false;
  let closed = false;

  function settleAll(error) {
    closed = true;
    for (const command of pending.values()) command.reject(error);
    for (const waiters of events.values()) {
      for (const waiter of waiters) waiter.reject(error);
    }
  }

  const connected = new Promise((resolve, reject) => {
    socket.addEventListener("open", () => { ready = true; resolve(); }, { once: true });
    socket.addEventListener("close", () => {
      const error = new Error("Chrome DevTools connection closed");
      if (!ready) reject(error);
      settleAll(error);
    }, { once: true });
    socket.addEventListener("error", () => {
      const error = new Error("Chrome DevTools connection failed");
      if (!ready) reject(error);
      settleAll(error);
    }, { once: true });
  });

  socket.addEventListener("message", ({ data }) => {
    let message;
    try {
      message = JSON.parse(String(data));
    } catch {
      settleAll(new Error("Chrome DevTools returned an invalid message"));
      socket.close();
      return;
    }
    const command = pending.get(message.id);
    if (command) {
      if (message.error) command.reject(new Error(message.error.message || JSON.stringify(message.error)));
      else command.resolve(message.result ?? {});
    }
    if (message.method) {
      onEvent?.(message);
      for (const waiter of events.get(message.method) ?? []) waiter.resolve(message.params ?? {});
    }
  });

  try {
    await withTimeout(connected, Math.min(timeoutMs, 15000), "Chrome DevTools connection");
  } catch (error) {
    socket.close();
    throw error;
  }

  return {
    send(method, params = {}, commandTimeout = timeoutMs) {
      if (closed) return Promise.reject(new Error("Chrome DevTools connection is closed"));
      const id = nextId++;
      const response = new Promise((resolve, reject) => {
        pending.set(id, { resolve, reject });
        socket.send(JSON.stringify({ id, method, params }));
      });
      return withTimeout(response, commandTimeout, method).finally(() => pending.delete(id));
    },
    waitFor(method, eventTimeout = timeoutMs) {
      if (closed) return Promise.reject(new Error("Chrome DevTools connection is closed"));
      const waiters = events.get(method) ?? new Set();
      events.set(method, waiters);
      let waiter;
      const response = new Promise((resolve, reject) => {
        waiter = { resolve, reject };
        waiters.add(waiter);
      });
      return withTimeout(response, eventTimeout, method).finally(() => {
        waiters.delete(waiter);
        if (!waiters.size) events.delete(method);
      });
    },
    close() {
      settleAll(new Error("Chrome DevTools connection closed"));
      socket.close();
    },
  };
}

async function openTarget(origin, { allowLegacyGet = false, ...connection } = {}) {
  const newTarget = `/json/new?${encodeURIComponent("about:blank")}`;
  let target;
  try {
    target = await readDevTools(origin, newTarget, { method: "PUT" });
  } catch (error) {
    if (!allowLegacyGet) throw error;
    target = await readDevTools(origin, newTarget);
  }
  const client = await connectDevTools(localSocketUrl(target.webSocketDebuggerUrl, origin), connection);
  return {
    ...client,
    async close() {
      client.close();
      const address = new URL(`/json/close/${encodeURIComponent(target.id)}`, origin);
      try {
        await fetch(address, { redirect: "error", signal: AbortSignal.timeout(1000) });
      } catch {
        // The browser may already have closed the target.
      }
    },
  };
}

async function navigate(client, url) {
  const result = await client.send("Page.navigate", { url });
  if (result.errorText) throw new Error(`Chrome could not load the requested page: ${result.errorText}`);
  return result;
}

async function prepareMobileCapture(client, { width, height }) {
  await client.send("Page.enable");
  await client.send("Runtime.enable");
  await client.send("Emulation.setDeviceMetricsOverride", {
    width, height, deviceScaleFactor: 1, mobile: true,
    screenWidth: width, screenHeight: height, positionX: 0, positionY: 0,
  });
  await client.send("Emulation.setTouchEmulationEnabled", { enabled: true });
  await client.send("Emulation.setEmulatedMedia", {
    features: [{ name: "prefers-reduced-motion", value: "reduce" }],
  });
}

module.exports = { waitForDevTools, connectDevTools, openTarget, withTimeout, navigate, prepareMobileCapture };
