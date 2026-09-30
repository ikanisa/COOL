import { assertEquals } from "../../supabase/functions/_shared/test_assert.ts";
import { evaluateRosterCandidates } from "./roster_extraction_evaluation.ts";
import { parseRosterText } from "../../supabase/functions/_shared/roster_import.ts";
const rows = [{
  member_name: "Élodie Niyonzima",
  momo_name: "ÉLODIE NIYONZIMA",
  momo_number: "0789969001",
}, {
  member_name: "Aline Uwase",
  momo_name: "ALINE UWASE",
  momo_number: "0789969002",
}];
const candidates = rows.map((row, index) => ({
  ...row,
  source_row: index + 1,
  confidence: 1,
}));
Deno.test("evaluation distinguishes exact ordered rows from missing/extra/reordered numbers", () => {
  assertEquals(evaluateRosterCandidates(rows, candidates).exact_order, true);
  assertEquals(evaluateRosterCandidates(rows, [candidates[0]]).recall, .5);
  assertEquals(
    evaluateRosterCandidates(rows, [candidates[1], candidates[0]]).exact_order,
    false,
  );
  assertEquals(
    evaluateRosterCandidates(rows, [{
      ...candidates[0],
      momo_number: "0789969999",
    }]).invented_ready_numbers,
    1,
  );
  assertEquals(evaluateRosterCandidates([], candidates).precision, 0);
});
Deno.test("evaluation blocks ambiguous/missing/formula/low-confidence data", () => {
  for (
    const patch of [{ momo_number: "078???????" }, { momo_name: "" }, {
      member_name: "=INVENT()",
    }, { confidence: .2 }]
  ) {
    const result = evaluateRosterCandidates(rows, [{
      ...candidates[0],
      ...patch,
    }]);
    assertEquals(result.ready_rows, 0);
    assertEquals(result.blocked_rows, 1);
  }
});
for (
  const header of [
    "Nom du membre,Nom MoMo,Numéro MoMo",
    "Izina ry'umunyamuryango,Izina rya MoMo,Nimero ya MoMo",
    "Jina la mwanachama,Jina la MoMo,Nambari ya MoMo",
  ]
) {
  Deno.test(`deterministic multilingual headers ${header}`, () => {
    const parsed = parseRosterText(
      header + "\nÉlodie Niyonzima,ÉLODIE NIYONZIMA,0789969001",
    );
    assertEquals(evaluateRosterCandidates([rows[0]], parsed).exact_order, true);
  });
}
Deno.test("duplicate multilingual phone headers are rejected as ambiguous", () => {
  let rejected = false;
  try {
    parseRosterText(
      "Member name,MoMo number,Numéro MoMo\nAline,0789969001,0789969999",
    );
  } catch {
    rejected = true;
  }
  assertEquals(rejected, true);
});
