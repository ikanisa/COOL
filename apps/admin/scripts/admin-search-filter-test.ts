import {
  buildAdminIlikeOrFilter,
  normalizeAdminSearchTerm,
} from "../../../packages/shared-utils/src/admin-search.ts";

function expectEquals<T>(actual: T, expected: T, message: string) {
  if (actual !== expected) {
    throw new Error(`${message}: expected ${expected}, got ${actual}`);
  }
}

function expect(condition: boolean, message: string) {
  if (!condition) {
    throw new Error(message);
  }
}

Deno.test("admin search normalizes hostile PostgREST filter punctuation", () => {
  const normalized = normalizeAdminSearchTerm(
    "  %(+250788),users.phone.ilike.%999%  ",
    { minLength: 3 },
  );

  expectEquals(
    normalized,
    "+250788 users phone ilike 999",
    "normalized admin search term",
  );
  expect(!/[,%()_.]/.test(normalized ?? ""), "filter punctuation is removed");
});

Deno.test("admin search builds filters only with approved column identifiers", () => {
  const filter = buildAdminIlikeOrFilter("Alpha 250", [
    "full_name",
    "users.phone",
  ]);

  expectEquals(
    filter,
    "full_name.ilike.%Alpha 250%,users.phone.ilike.%Alpha 250%",
    "admin filter",
  );
});

Deno.test("admin search rejects unsafe column fragments", () => {
  let rejected = false;
  try {
    buildAdminIlikeOrFilter("Alpha", [
      "full_name",
      "users.phone),id.ilike.%x%",
    ]);
  } catch {
    rejected = true;
  }

  expect(rejected, "unsafe columns must be rejected");
});
