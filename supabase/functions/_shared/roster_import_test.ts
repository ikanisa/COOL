import { assertEquals } from "./test_assert.ts";
import {
  canonicalRwandaMomoNumber,
  normalizeRosterCandidates,
  parseRosterText,
} from "./roster_import.ts";

Deno.test("parses a quoted reviewed CSV roster", () => {
  const rows = parseRosterText([
    "member_name,momo_name,momo_number",
    '"Alice A.","ALICE UWASE","0788 000 456"',
    "Bob,BOSCO BOB,+250788000457",
  ].join("\n"));
  const preview = normalizeRosterCandidates(rows);
  assertEquals(preview.can_submit, true);
  assertEquals(preview.normalized_rows, [
    {
      member_name: "Alice A.",
      momo_name: "ALICE UWASE",
      momo_number: "+250788000456",
    },
    {
      member_name: "Bob",
      momo_name: "BOSCO BOB",
      momo_number: "+250788000457",
    },
  ]);
});

Deno.test("parses headerless tab-separated rows", () => {
  const rows = parseRosterText(
    "Alice\tALICE UWASE\t0788000456\nBob\tBOB MUGISHA\t0788000457",
  );
  assertEquals(normalizeRosterCandidates(rows).ready_count, 2);
});

Deno.test("invalid, low-confidence and duplicate numbers remain review-only", () => {
  const preview = normalizeRosterCandidates([
    {
      source_row: 3,
      member_name: "Alice",
      momo_name: "ALICE UWASE",
      momo_number: "0788000456",
      confidence: 0.95,
    },
    {
      source_row: 4,
      member_name: "Bob",
      momo_name: "BOB MUGISHA",
      momo_number: "+250788000456",
      confidence: 0.6,
    },
  ]);
  assertEquals(preview.can_submit, false);
  assertEquals(preview.error_count, 1);
  assertEquals(preview.rows[1].issues.length, 2);
});

Deno.test("spreadsheet formula-like names remain review-only", () => {
  const preview = normalizeRosterCandidates([{
    source_row: 1,
    member_name: '=HYPERLINK("https://example.test")',
    momo_name: "SAFE NAME",
    momo_number: "0788123456",
    confidence: 1,
  }]);
  assertEquals(preview.can_submit, false);
  assertEquals(
    preview.rows[0].issues.includes(
      "Names cannot begin with spreadsheet formula characters",
    ),
    true,
  );
});

Deno.test("Rwanda MoMo normalization rejects masked or foreign numbers", () => {
  assertEquals(canonicalRwandaMomoNumber("0788-000-456"), "+250788000456");
  assertEquals(canonicalRwandaMomoNumber("***456"), null);
  assertEquals(canonicalRwandaMomoNumber("+35699123456"), null);
});
