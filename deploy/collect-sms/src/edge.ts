import {
  guardedFetch,
  openApplicationWork,
} from "../../../supabase/functions/_shared/application-fence.js";
import type { smsFenceBackend } from "./fence.ts";
import { app, maintenance } from "./index.ts";
import { gatewayDatabaseReadiness } from "./gateway-connection.ts";
import {
  createGatewayRuntime,
  type GatewayHandlerOptions,
  type GatewaySettings,
} from "./gateway-runtime.ts";
import type { Env } from "./types.ts";
import { safeEqual, sha256 } from "./util.ts";

const openGatewayWork = openApplicationWork as (input: {
  backend: ReturnType<typeof smsFenceBackend>;
  sourceSha256: string;
  kind: "jobs" | "http_collect";
  signal: AbortSignal;
}) => ReturnType<typeof openApplicationWork>;
const noStore = { "cache-control": "no-store" };
const maintenancePath = "/internal/maintenance";
const readinessPath = "/internal/readiness";
const prefixes = ["/functions/v1/collect-sms", "/collect-sms"];

function unavailable() {
  return Response.json({
    error: {
      code: "gateway_unavailable",
      message: "The SMS gateway is unavailable.",
    },
  }, { status: 503, headers: noStore });
}

async function hasBearer(request: Request, expected: string | undefined) {
  const authorization = request.headers.get("authorization");
  if (
    !expected || !authorization?.startsWith("Bearer ") ||
    authorization.length > 519
  ) return false;
  return safeEqual(
    await sha256(authorization.slice(7)),
    await sha256(expected),
  );
}

export function createSmsGatewayHandler(
  settings: GatewaySettings,
  options: GatewayHandlerOptions = {},
) {
  let startup: ReturnType<typeof createGatewayRuntime> | undefined;
  return async (request: Request): Promise<Response> => {
    let runtime: Awaited<ReturnType<typeof createGatewayRuntime>>;
    try {
      startup ??= createGatewayRuntime(settings, options);
      runtime = await startup;
    } catch {
      return unavailable();
    }

    const url = new URL(request.url);
    const publicOrigin = runtime.profile.supabase_origin;
    const authority = new URL(publicOrigin);
    // Hosted ingress can terminate TLS before invoking the function. Restore
    // the public scheme only for the fixed project authority.
    if (
      url.protocol === "http:" && url.hostname === authority.hostname &&
      !url.port
    ) url.protocol = "https:";
    if (
      url.origin !== publicOrigin || url.username || url.password || url.hash
    ) {
      return new Response(null, { status: 403, headers: noStore });
    }
    const prefix = prefixes.find((value) =>
      url.pathname === value || url.pathname.startsWith(value + "/")
    );
    if (!prefix || /\/\/|%2f|%5c/i.test(url.pathname)) {
      return new Response(null, { status: 404, headers: noStore });
    }
    url.pathname = url.pathname.slice(prefix.length) || "/";

    const forMaintenance = url.pathname === maintenancePath;
    const forReadiness = url.pathname === readinessPath;
    if (forMaintenance || forReadiness) {
      const browserOrigin = request.headers.get("origin");
      const token = forReadiness
        ? runtime.env.ROOT_ADMIN_TOKEN
        : runtime.maintenanceToken;
      const method = forReadiness ? "GET" : "POST";
      if (
        request.method !== method || (forReadiness && url.search) ||
        (browserOrigin &&
          ![publicOrigin, runtime.profile.admin_origin].includes(
            browserOrigin,
          )) ||
        !await hasBearer(request, token)
      ) {
        return new Response(null, { status: 404, headers: noStore });
      }
    }

    let work: Awaited<ReturnType<typeof openApplicationWork>>;
    try {
      work = await openGatewayWork({
        backend: runtime.backend,
        sourceSha256: runtime.sourceSha256,
        kind: forMaintenance ? "jobs" : "http_collect",
        signal: request.signal,
      });
    } catch {
      return unavailable();
    }
    let response: Response;
    try {
      const env: Env = {
        ...runtime.env,
        DB: runtime.database.withApplicationWork(work),
        COLLECT_FENCE_WORK: work,
      };
      env.FETCH = (input, init) =>
        guardedFetch(env, "gateway_http", input, init);
      const context = {
        props: {},
        waitUntil(promise: Promise<unknown>) {
          const owned = work.waitUntil(promise);
          options.waitUntil?.(owned);
        },
        passThroughOnException() {},
      };
      if (forReadiness) {
        const proof = await env.DB.prepare(gatewayDatabaseReadiness).first<
          { ready: boolean }
        >();
        response = proof?.ready === true
          ? Response.json({
            status: "ready",
            service: "collect-sms",
            core_source_sha256: runtime.sourceSha256,
            release_sha256: runtime.releaseSha256,
            profile_sha256: runtime.profileSha256,
            dispatch_paused: env.DISPATCH_PAUSED === "true",
            fcm_enabled: env.FCM_ENABLED === "true",
            retention_auto_purge: env.RETENTION_AUTO_PURGE === "true",
            capabilities: { application_messages: true, device_dispatch: true },
          }, { headers: noStore })
          : unavailable();
      } else if (forMaintenance) {
        await maintenance(env);
        response = Response.json({ ok: true }, { headers: noStore });
      } else {
        const headers = new Headers(request.headers);
        headers.delete("X-Collect-Original-Path");
        headers.delete("X-Collect-Actor");
        const logicalRequest = new Request(url, {
          method: request.method,
          headers,
          body: request.body,
          signal: request.signal,
        });
        response = await app.fetch(logicalRequest, env, context);
      }
    } catch {
      response = unavailable();
    }
    try {
      // The original lease owns all deferred database and external work.
      const outcome = await work.finish({ failed: response.status >= 500 });
      if (
        forReadiness && (!outcome.applicationWorkFinished ||
          outcome.externalDispatches !== 0 || outcome.uncertainDispatches !== 0)
      ) {
        return unavailable();
      }
    } catch {
      // Durable unresolved admission blocks drain.
      if (forReadiness) return unavailable();
    }
    return response;
  };
}
