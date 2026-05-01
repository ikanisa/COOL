import { createServer } from "node:http";
import { readFile, stat } from "node:fs/promises";
import { extname, join, normalize, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";

const root = resolve(fileURLToPath(new URL("..", import.meta.url)));
const dist = join(root, "dist");
const contentTypes = new Map([
  [".css", "text/css; charset=utf-8"],
  [".html", "text/html; charset=utf-8"],
  [".ico", "image/x-icon"],
  [".js", "text/javascript; charset=utf-8"],
  [".json", "application/json; charset=utf-8"],
  [".png", "image/png"],
  [".svg", "image/svg+xml"],
  [".webmanifest", "application/manifest+json"],
]);

const adminAccess = {
  has_platform_access: true,
  has_bank_access: true,
  has_partner_access: true,
  has_legacy_admin_flag: false,
  bank_partner_ids: [],
  partner_admin_ids: [],
  role_assignments: [],
  capabilities: {
    manage_platform: true,
    manage_users: true,
    manage_roles: true,
    manage_config: true,
    view_analytics: true,
    view_audit_log: true,
    view_groups: true,
    view_savings: true,
  },
};

const session = {
  access_token: "admin-smoke-token",
  refresh_token: "admin-smoke-refresh",
  expires_in: 3600,
  expires_at: Math.floor(Date.now() / 1000) + 3600,
  token_type: "bearer",
  user: {
    id: "00000000-0000-4000-8000-000000000001",
    aud: "authenticated",
    role: "authenticated",
    email: "admin-smoke@example.com",
    app_metadata: {},
    user_metadata: { full_name: "Admin Smoke" },
    created_at: new Date().toISOString(),
  },
};

function isInsideDist(filePath) {
  const relative = normalize(filePath).replace(dist, "");
  return !relative.startsWith("..");
}

async function fileExists(filePath) {
  try {
    const info = await stat(filePath);
    return info.isFile();
  } catch {
    return false;
  }
}

async function serveDist() {
  const server = createServer(async (request, response) => {
    const requestUrl = new URL(request.url ?? "/", "http://127.0.0.1");
    const requestedPath = decodeURIComponent(requestUrl.pathname);
    const candidate = join(dist, requestedPath === "/" ? "index.html" : requestedPath);
    const filePath =
      isInsideDist(candidate) && (await fileExists(candidate))
        ? candidate
        : join(dist, "index.html");

    try {
      const body = await readFile(filePath);
      response.writeHead(200, {
        "content-type":
          contentTypes.get(extname(filePath)) ?? "application/octet-stream",
      });
      response.end(body);
    } catch (error) {
      response.writeHead(500, { "content-type": "text/plain; charset=utf-8" });
      response.end(error instanceof Error ? error.message : "server error");
    }
  });

  await new Promise((resolveListen) => server.listen(0, "127.0.0.1", resolveListen));
  const address = server.address();
  if (!address || typeof address === "string") {
    throw new Error("Failed to start admin smoke server.");
  }

  return {
    baseUrl: `http://127.0.0.1:${address.port}`,
    close: () => new Promise((resolveClose) => server.close(resolveClose)),
  };
}

function emptyRestResponse(route) {
  const request = route.request();
  const isHead = request.method() === "HEAD";

  return route.fulfill({
    status: 200,
    headers: {
      "access-control-expose-headers": "content-range",
      "content-range": "0-0/0",
      "content-type": "application/json; charset=utf-8",
    },
    body: isHead ? "" : "[]",
  });
}

async function installSupabaseMocks(page) {
  await page.addInitScript((storedSession) => {
    window.localStorage.setItem("cool-admin-auth", JSON.stringify(storedSession));
  }, session);

  await page.route("**/auth/v1/**", (route) =>
    route.fulfill({ status: 200, json: { user: session.user } }),
  );

  await page.route("**/rest/v1/**", emptyRestResponse);

  await page.route("**/rest/v1/rpc/get_admin_access_for_user", (route) =>
    route.fulfill({ status: 200, json: adminAccess }),
  );

  await page.route("**/rest/v1/rpc/list_admin_role_assignments", (route) =>
    route.fulfill({ status: 200, json: [] }),
  );

  await page.route("**/rest/v1/rpc/get_admin_audit_log", (route) =>
    route.fulfill({ status: 200, json: [] }),
  );
}

async function assertVisible(page, name, locator) {
  try {
    await locator.waitFor({ state: "visible", timeout: 8000 });
  } catch (error) {
    const bodyText = await page.locator("body").innerText({ timeout: 1000 }).catch(
      () => "",
    );
    throw new Error(
      `${name} was not visible. Current URL: ${page.url()}\n` +
        `Body:\n${bodyText.slice(0, 1200)}`,
      { cause: error },
    );
  }
  console.log(`ok: ${name}`);
}

async function smokePage(page, baseUrl, path, heading, placeholder) {
  await page.goto(`${baseUrl}${path}`, { waitUntil: "domcontentloaded" });
  await assertVisible(
    page,
    `${path} heading`,
    page.getByRole("heading", { name: heading }),
  );
  await assertVisible(
    page,
    `${path} search`,
    page.getByPlaceholder(placeholder),
  );
}

const server = process.env.ADMIN_SMOKE_BASE_URL
  ? { baseUrl: process.env.ADMIN_SMOKE_BASE_URL, close: async () => {} }
  : await serveDist();

const browser = await chromium.launch({ headless: true });
const context = await browser.newContext();
const page = await context.newPage();
const browserErrors = [];

page.on("pageerror", (error) => browserErrors.push(error.message));
page.on("console", (message) => {
  if (message.type() === "error") {
    browserErrors.push(message.text());
  }
});

try {
  await installSupabaseMocks(page);

  await smokePage(page, server.baseUrl, "/users", "User Management", "Search by name or phone...");
  await smokePage(page, server.baseUrl, "/health", "System Health", "Search service, component, severity...");
  await smokePage(page, server.baseUrl, "/settings", "Platform Settings", "Search configuration...");
  await smokePage(page, server.baseUrl, "/approvals", "Admin Audit Log", "Search audit log...");

  if (browserErrors.length > 0) {
    throw new Error(`Browser errors:\n${browserErrors.join("\n")}`);
  }

  console.log("Admin browser smoke passed.");
} finally {
  await browser.close();
  await server.close();
}
