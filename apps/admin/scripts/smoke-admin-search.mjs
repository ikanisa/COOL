import { createClient } from "@supabase/supabase-js";
import { existsSync, readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

const scriptDir = dirname(fileURLToPath(import.meta.url));
const appRoot = resolve(scriptDir, "..");
const repoRoot = resolve(appRoot, "../..");

function loadEnvFile(path) {
  if (!existsSync(path)) return;

  for (const line of readFileSync(path, "utf8").split(/\r?\n/)) {
    const match = /^\s*([A-Za-z_][A-Za-z0-9_]*)=(.*)\s*$/.exec(line);
    if (!match || process.env[match[1]] != null) continue;

    let value = match[2].trim();
    if (
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1);
    }
    process.env[match[1]] = value;
  }
}

loadEnvFile(resolve(repoRoot, ".env"));
loadEnvFile(resolve(appRoot, ".env"));

const supabaseUrl = process.env.SUPABASE_URL ?? process.env.VITE_SUPABASE_URL;
const supabaseAnonKey = process.env.SUPABASE_ANON_KEY ??
  process.env.VITE_SUPABASE_ANON_KEY;
const accessToken = process.env.SUPABASE_ACCESS_TOKEN;
const COLUMN_PATTERN = /^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)*$/;

function normalizeSearchTerm(search, { minLength = 1, maxLength = 64 } = {}) {
  const normalized = search
    .normalize("NFKC")
    .trim()
    .replace(/[^\p{L}\p{N}\s+-]/gu, " ")
    .replace(/\s+/g, " ")
    .slice(0, maxLength);
  return normalized.length >= minLength ? normalized : null;
}

const term = normalizeSearchTerm(process.env.ADMIN_SEARCH_SMOKE_TERM ?? "250");

if (!supabaseUrl || !supabaseAnonKey) {
  console.error(
    "Missing SUPABASE_URL/VITE_SUPABASE_URL or SUPABASE_ANON_KEY/VITE_SUPABASE_ANON_KEY.",
  );
  process.exit(1);
}

if (!term) {
  console.error("ADMIN_SEARCH_SMOKE_TERM does not contain searchable text.");
  process.exit(1);
}

const supabase = createClient(supabaseUrl, supabaseAnonKey, {
  global: {
    headers: accessToken ? { Authorization: `Bearer ${accessToken}` } : {},
  },
});

const ilike = (column) => {
  if (!COLUMN_PATTERN.test(column)) {
    throw new Error(`Unsupported admin search column: ${column}`);
  }
  return `${column}.ilike.%${term}%`;
};
const filter = (columns) => columns.map(ilike).join(",");

const cases = [
  {
    name: "users direct search",
    run: () =>
      supabase
        .from("users")
        .select("id, full_name, phone", { count: "exact" })
        .or(filter(["full_name", "phone"]))
        .range(0, 0),
  },
  {
    name: "group members embedded search",
    run: () =>
      supabase
        .from("group_members")
        .select(
          `
            id, display_name,
            groups!group_members_group_id_fkey ( name ),
            users!group_members_user_id_fkey ( phone )
          `,
          { count: "exact" },
        )
        .or(filter(["display_name"]))
        .range(0, 0),
  },
  {
    name: "loans embedded search",
    run: () =>
      supabase
        .from("loans")
        .select(
          `
            id, loan_code,
            users!loans_member_id_fkey ( full_name, phone ),
            groups!loans_group_id_fkey ( name )
          `,
          { count: "exact" },
        )
        .or(
          filter(["loan_code"]),
        )
        .range(0, 0),
  },
  {
    name: "contributions embedded search",
    run: () =>
      supabase
        .from("group_contributions")
        .select(
          `
            id, momo_reference,
            users!group_contributions_user_id_fkey ( full_name, phone ),
            groups!group_contributions_group_id_fkey ( name )
          `,
          { count: "exact" },
        )
        .or(filter(["momo_reference"]))
        .range(0, 0),
  },
  {
    name: "ledger embedded search",
    run: () =>
      supabase
        .from("momo_ledger_entries")
        .select(
          `
            id, statement_label, counterparty_name, external_reference,
            users!momo_ledger_entries_user_id_fkey ( full_name, phone )
          `,
          { count: "exact" },
        )
        .or(
          filter([
            "statement_label",
            "counterparty_name",
            "external_reference",
          ]),
        )
        .range(0, 0),
  },
];

for (const testCase of cases) {
  const { error, count } = await testCase.run();
  if (error) {
    console.error(`FAILED: ${testCase.name}: ${error.message}`);
    process.exitCode = 1;
  } else {
    console.log(`ok: ${testCase.name} (count=${count ?? "unknown"})`);
  }
}

if (process.exitCode) {
  console.error("Admin search smoke failed.");
} else {
  console.log("Admin search smoke passed.");
}
