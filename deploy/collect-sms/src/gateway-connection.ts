import postgres from "npm:postgres@3.4.7";
import {
  COLLECT_PROJECT_REF,
  normalizeDatabaseTarget,
} from "../../../supabase/functions/_shared/runtime-env.js";

const gatewayLogin = "collect_sms_edge_login";
const gatewayPooler = "aws-0-eu-north-1.pooler.supabase.com";

// Start with the shared project's validated TLS/DSN policy. The SMS Edge
// function never falls back to the database credentials injected by Supabase
// or to the credential used by Collect's application functions.
export function managedGatewayDatabaseUrl(
  settings: Record<string, string | undefined>,
): string {
  const configured = settings.COLLECT_SMS_DATABASE_URL;
  if (!configured) throw Error("gateway_database_configuration");
  const checked = new URL(
    normalizeDatabaseTarget({ ...settings, COLLECT_DATABASE_URL: configured }),
  );
  const direct = checked.hostname === `db.${COLLECT_PROJECT_REF}.supabase.co`;
  const expectedLogin = direct
    ? gatewayLogin
    : `${gatewayLogin}.${COLLECT_PROJECT_REF}`;
  if (
    (!direct && checked.hostname !== gatewayPooler) ||
    checked.username !== expectedLogin ||
    checked.pathname !== "/postgres" || !["", "5432"].includes(checked.port)
  ) {
    throw Error("gateway_database_identity");
  }
  checked.port = "5432";
  return checked.href;
}

// This reads only system catalogs and privilege metadata under the original
// gateway admission. It never queries messages, applications, or devices.
export const gatewayDatabaseReadiness = `
 SELECT (
  current_database() = 'postgres'
  AND edge.rolcanlogin AND NOT (edge.rolsuper OR edge.rolinherit OR edge.rolcreatedb OR
    edge.rolcreaterole OR edge.rolreplication OR edge.rolbypassrls)
  AND NOT (runtime.rolcanlogin OR runtime.rolsuper OR runtime.rolinherit OR runtime.rolcreatedb OR
    runtime.rolcreaterole OR runtime.rolreplication OR runtime.rolbypassrls)
  AND (SELECT count(*) = 1 AND bool_and(m.roleid = runtime.oid AND m.set_option
       AND NOT m.admin_option AND NOT m.inherit_option)
       FROM pg_catalog.pg_auth_members m WHERE m.member = edge.oid)
  AND NOT EXISTS (SELECT 1 FROM pg_catalog.pg_auth_members m WHERE m.member = runtime.oid)
  AND NOT pg_catalog.has_schema_privilege(edge.oid, 'collect_sms', 'USAGE')
  AND NOT pg_catalog.has_schema_privilege(edge.oid, 'app', 'USAGE')
  AND NOT pg_catalog.has_schema_privilege(edge.oid, 'private', 'USAGE')
  AND NOT pg_catalog.has_schema_privilege(runtime.oid, 'app', 'USAGE')
  AND NOT pg_catalog.has_schema_privilege(runtime.oid, 'private', 'USAGE')
  AND pg_catalog.has_schema_privilege(runtime.oid, 'collect_sms', 'USAGE')
  AND NOT EXISTS (
   SELECT 1 FROM (VALUES
    ('applications', 'SELECT'), ('devices', 'SELECT'), ('devices', 'UPDATE'),
    ('messages', 'SELECT'), ('messages', 'INSERT'), ('messages', 'UPDATE'),
    ('attempts', 'SELECT'), ('attempts', 'INSERT'), ('attempts', 'UPDATE'),
    ('message_parts', 'SELECT'), ('message_parts', 'INSERT'), ('message_parts', 'UPDATE'),
    ('acceptances', 'SELECT'), ('acceptances', 'INSERT'),
    ('dispatch_permits', 'SELECT'), ('dispatch_permits', 'INSERT'),
    ('device_events', 'SELECT'), ('device_events', 'INSERT'),
    ('audit_events', 'SELECT'), ('audit_events', 'INSERT')
   ) AS needed(relation, permission)
   LEFT JOIN pg_catalog.pg_class c ON c.oid = pg_catalog.to_regclass('collect_sms.' || needed.relation)
   WHERE c.relkind IS DISTINCT FROM 'r' OR NOT c.relrowsecurity OR NOT c.relforcerowsecurity
     OR pg_catalog.has_table_privilege(runtime.oid, c.oid, needed.permission) IS NOT TRUE
  )
 ) AS ready
 FROM pg_catalog.pg_roles edge
 JOIN pg_catalog.pg_roles runtime ON runtime.rolname = current_user
 WHERE edge.rolname = session_user AND edge.rolname = 'collect_sms_edge_login'
 AND runtime.rolname = 'collect_sms_runtime'`;

export function gatewayConnection(
  url: string,
  env: Record<string, string | undefined> = {},
) {
  const target = new URL(url),
    local = ["localhost", "127.0.0.1", "[::1]"].includes(target.hostname);
  if (
    !["postgres:", "postgresql:"].includes(target.protocol) ||
    !target.username || !target.pathname.slice(1)
  ) throw Error("gateway_database_configuration");
  const ca = env.COLLECT_SMS_DATABASE_CA_PEM ?? env.COLLECT_DB_CA_PEM;
  if (
    ca !== undefined &&
    (!ca.startsWith("-----BEGIN CERTIFICATE-----\n") || ca.length > 32768)
  ) throw Error("gateway_database_ca");
  if (local && env.COLLECT_SMS_FIXTURE !== "true") {
    throw Error("gateway_fixture_required");
  }
  return postgres(url, {
    max: 4,
    prepare: false,
    connect_timeout: 10,
    idle_timeout: 20,
    ssl: local ? false : {
      rejectUnauthorized: true,
      servername: target.hostname,
      ...(ca ? { ca } : {}),
    },
    types: {
      bigint: {
        to: 20,
        from: [20],
        serialize: String,
        parse: (value: string) => {
          const n = Number(value);
          if (!Number.isSafeInteger(n)) throw Error("gateway_integer_range");
          return n;
        },
      },
    },
    onnotice: () => {},
  });
}
