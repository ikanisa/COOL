"use strict";

// Local engineering checks must not reach hosted services or other local ports.
function requireLoopbackOrigin(baseUrl) {
  const parsed = new URL(baseUrl);
  if (parsed.protocol !== "http:" || !["127.0.0.1", "[::1]"].includes(parsed.hostname) ||
      parsed.username || parsed.password) {
    throw new Error("Public browser QA requires an unauthenticated HTTP loopback origin");
  }
  return parsed.origin;
}

async function installLocalNetworkFence(page, baseUrl, denied) {
  const origin = requireLoopbackOrigin(baseUrl);
  await page.context().route("**/*", async (route) => {
    const url = new URL(route.request().url());
    if (url.origin === origin && url.protocol === "http:") {
      await route.continue();
      return;
    }
    // Do not retain query parameters, fragments, body, credentials or tokens.
    denied.push({ protocol: url.protocol, origin: url.origin,
      resourceType: route.request().resourceType() });
    await route.abort("blockedbyclient");
  });
}

module.exports = { requireLoopbackOrigin, installLocalNetworkFence };
