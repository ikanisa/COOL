import { assertEquals } from "../../supabase/functions/_shared/test_assert.ts";
import { evaluateRosterCandidates } from "./roster_extraction_evaluation.ts";
import { parseRosterText } from "../../supabase/functions/_shared/roster_import.ts";
const rows = [
  {
    member_name: "Élodie Niyonzima",
    momo_name: "ÉLODIE NIYONZIMA",
    momo_number: "0789969001"
  },
  {
    member_name: "Aline Uwase",
    momo_name: "ALINE UWASE",
    momo_number: "0789969002"
  }
];
const candidates = rows.map((row, index)=>({
    ...row,
    source_row: index + 1,
    confidence: 1
  }));
Deno.test("evaluation distinguishes exact ordered rows from missing/extra/reordered numbers", ()=>{
  assertEquals(evaluateRosterCandidates(rows, candidates).exact_order, true);
  assertEquals(evaluateRosterCandidates(rows, [
    candidates[0]
  ]).recall, .5);
  assertEquals(evaluateRosterCandidates(rows, [
    candidates[1],
    candidates[0]
  ]).exact_order, false);
  assertEquals(evaluateRosterCandidates(rows, [
    {
      ...candidates[0],
      momo_number: "0789969999"
    }
  ]).invented_ready_numbers, 1);
  assertEquals(evaluateRosterCandidates([], candidates).precision, 0);
});
Deno.test("evaluation blocks ambiguous/missing/formula/low-confidence data", ()=>{
  for (const patch of [
    {
      momo_number: "078???????"
    },
    {
      momo_name: ""
    },
    {
      member_name: "=INVENT()"
    },
    {
      confidence: .2
    }
  ]){
    const result = evaluateRosterCandidates(rows, [
      {
        ...candidates[0],
        ...patch
      }
    ]);
    assertEquals(result.ready_rows, 0);
    assertEquals(result.blocked_rows, 1);
  }
});
for (const header of [
  "Nom du membre,Nom MoMo,Numéro MoMo",
  "Izina ry'umunyamuryango,Izina rya MoMo,Nimero ya MoMo",
  "Jina la mwanachama,Jina la MoMo,Nambari ya MoMo"
]){
  Deno.test(`deterministic multilingual headers ${header}`, ()=>{
    const parsed = parseRosterText(header + "\nÉlodie Niyonzima,ÉLODIE NIYONZIMA,0789969001");
    assertEquals(evaluateRosterCandidates([
      rows[0]
    ], parsed).exact_order, true);
  });
}
Deno.test("duplicate multilingual phone headers are rejected as ambiguous", ()=>{
  let rejected = false;
  try {
    parseRosterText("Member name,MoMo number,Numéro MoMo\nAline,0789969001,0789969999");
  } catch  {
    rejected = true;
  }
  assertEquals(rejected, true);
});
//# sourceMappingURL=data:application/json;base64,eyJ2ZXJzaW9uIjozLCJzb3VyY2VzIjpbImZpbGU6Ly8vVm9sdW1lcy9QUk8tRzQwL1Byb2plY3RzL1JlY292ZXJlZC1HLVBSTy9DT09ML2RvY3MvcmVsZWFzZS9jcml0aWNhbC1pbXBsZW1lbnRhdGlvbi0yMDI2LTEwLTAxL3N1Y2Nlc3Nvci1vYnNlcnZlZC1maXh0dXJlLWltcG9ydC1wcm9wb3NhbDEvY2FuZGlkYXRlLXN0YWdlMS9zb3VyY2Uvc2NyaXB0cy90ZXN0cy9yb3N0ZXJfZXh0cmFjdGlvbl9ldmFsdWF0aW9uX3Rlc3QudHMiXSwic291cmNlc0NvbnRlbnQiOlsiaW1wb3J0IHsgYXNzZXJ0RXF1YWxzIH0gZnJvbSBcIi4uLy4uL3N1cGFiYXNlL2Z1bmN0aW9ucy9fc2hhcmVkL3Rlc3RfYXNzZXJ0LnRzXCI7XG5pbXBvcnQgeyBldmFsdWF0ZVJvc3RlckNhbmRpZGF0ZXMgfSBmcm9tIFwiLi9yb3N0ZXJfZXh0cmFjdGlvbl9ldmFsdWF0aW9uLnRzXCI7XG5pbXBvcnQgeyBwYXJzZVJvc3RlclRleHQgfSBmcm9tIFwiLi4vLi4vc3VwYWJhc2UvZnVuY3Rpb25zL19zaGFyZWQvcm9zdGVyX2ltcG9ydC50c1wiO1xuY29uc3Qgcm93cyA9IFt7XG4gIG1lbWJlcl9uYW1lOiBcIsOJbG9kaWUgTml5b256aW1hXCIsXG4gIG1vbW9fbmFtZTogXCLDiUxPRElFIE5JWU9OWklNQVwiLFxuICBtb21vX251bWJlcjogXCIwNzg5OTY5MDAxXCIsXG59LCB7XG4gIG1lbWJlcl9uYW1lOiBcIkFsaW5lIFV3YXNlXCIsXG4gIG1vbW9fbmFtZTogXCJBTElORSBVV0FTRVwiLFxuICBtb21vX251bWJlcjogXCIwNzg5OTY5MDAyXCIsXG59XTtcbmNvbnN0IGNhbmRpZGF0ZXMgPSByb3dzLm1hcCgocm93LCBpbmRleCkgPT4gKHtcbiAgLi4ucm93LFxuICBzb3VyY2Vfcm93OiBpbmRleCArIDEsXG4gIGNvbmZpZGVuY2U6IDEsXG59KSk7XG5EZW5vLnRlc3QoXCJldmFsdWF0aW9uIGRpc3Rpbmd1aXNoZXMgZXhhY3Qgb3JkZXJlZCByb3dzIGZyb20gbWlzc2luZy9leHRyYS9yZW9yZGVyZWQgbnVtYmVyc1wiLCAoKSA9PiB7XG4gIGFzc2VydEVxdWFscyhldmFsdWF0ZVJvc3RlckNhbmRpZGF0ZXMocm93cywgY2FuZGlkYXRlcykuZXhhY3Rfb3JkZXIsIHRydWUpO1xuICBhc3NlcnRFcXVhbHMoZXZhbHVhdGVSb3N0ZXJDYW5kaWRhdGVzKHJvd3MsIFtjYW5kaWRhdGVzWzBdXSkucmVjYWxsLCAuNSk7XG4gIGFzc2VydEVxdWFscyhcbiAgICBldmFsdWF0ZVJvc3RlckNhbmRpZGF0ZXMocm93cywgW2NhbmRpZGF0ZXNbMV0sIGNhbmRpZGF0ZXNbMF1dKS5leGFjdF9vcmRlcixcbiAgICBmYWxzZSxcbiAgKTtcbiAgYXNzZXJ0RXF1YWxzKFxuICAgIGV2YWx1YXRlUm9zdGVyQ2FuZGlkYXRlcyhyb3dzLCBbe1xuICAgICAgLi4uY2FuZGlkYXRlc1swXSxcbiAgICAgIG1vbW9fbnVtYmVyOiBcIjA3ODk5Njk5OTlcIixcbiAgICB9XSkuaW52ZW50ZWRfcmVhZHlfbnVtYmVycyxcbiAgICAxLFxuICApO1xuICBhc3NlcnRFcXVhbHMoZXZhbHVhdGVSb3N0ZXJDYW5kaWRhdGVzKFtdLCBjYW5kaWRhdGVzKS5wcmVjaXNpb24sIDApO1xufSk7XG5EZW5vLnRlc3QoXCJldmFsdWF0aW9uIGJsb2NrcyBhbWJpZ3VvdXMvbWlzc2luZy9mb3JtdWxhL2xvdy1jb25maWRlbmNlIGRhdGFcIiwgKCkgPT4ge1xuICBmb3IgKFxuICAgIGNvbnN0IHBhdGNoIG9mIFt7IG1vbW9fbnVtYmVyOiBcIjA3OD8/Pz8/Pz9cIiB9LCB7IG1vbW9fbmFtZTogXCJcIiB9LCB7XG4gICAgICBtZW1iZXJfbmFtZTogXCI9SU5WRU5UKClcIixcbiAgICB9LCB7IGNvbmZpZGVuY2U6IC4yIH1dXG4gICkge1xuICAgIGNvbnN0IHJlc3VsdCA9IGV2YWx1YXRlUm9zdGVyQ2FuZGlkYXRlcyhyb3dzLCBbe1xuICAgICAgLi4uY2FuZGlkYXRlc1swXSxcbiAgICAgIC4uLnBhdGNoLFxuICAgIH1dKTtcbiAgICBhc3NlcnRFcXVhbHMocmVzdWx0LnJlYWR5X3Jvd3MsIDApO1xuICAgIGFzc2VydEVxdWFscyhyZXN1bHQuYmxvY2tlZF9yb3dzLCAxKTtcbiAgfVxufSk7XG5mb3IgKFxuICBjb25zdCBoZWFkZXIgb2YgW1xuICAgIFwiTm9tIGR1IG1lbWJyZSxOb20gTW9NbyxOdW3DqXJvIE1vTW9cIixcbiAgICBcIkl6aW5hIHJ5J3VtdW55YW11cnlhbmdvLEl6aW5hIHJ5YSBNb01vLE5pbWVybyB5YSBNb01vXCIsXG4gICAgXCJKaW5hIGxhIG13YW5hY2hhbWEsSmluYSBsYSBNb01vLE5hbWJhcmkgeWEgTW9Nb1wiLFxuICBdXG4pIHtcbiAgRGVuby50ZXN0KGBkZXRlcm1pbmlzdGljIG11bHRpbGluZ3VhbCBoZWFkZXJzICR7aGVhZGVyfWAsICgpID0+IHtcbiAgICBjb25zdCBwYXJzZWQgPSBwYXJzZVJvc3RlclRleHQoXG4gICAgICBoZWFkZXIgKyBcIlxcbsOJbG9kaWUgTml5b256aW1hLMOJTE9ESUUgTklZT05aSU1BLDA3ODk5NjkwMDFcIixcbiAgICApO1xuICAgIGFzc2VydEVxdWFscyhldmFsdWF0ZVJvc3RlckNhbmRpZGF0ZXMoW3Jvd3NbMF1dLCBwYXJzZWQpLmV4YWN0X29yZGVyLCB0cnVlKTtcbiAgfSk7XG59XG5EZW5vLnRlc3QoXCJkdXBsaWNhdGUgbXVsdGlsaW5ndWFsIHBob25lIGhlYWRlcnMgYXJlIHJlamVjdGVkIGFzIGFtYmlndW91c1wiLCAoKSA9PiB7XG4gIGxldCByZWplY3RlZCA9IGZhbHNlO1xuICB0cnkge1xuICAgIHBhcnNlUm9zdGVyVGV4dChcbiAgICAgIFwiTWVtYmVyIG5hbWUsTW9NbyBudW1iZXIsTnVtw6lybyBNb01vXFxuQWxpbmUsMDc4OTk2OTAwMSwwNzg5OTY5OTk5XCIsXG4gICAgKTtcbiAgfSBjYXRjaCB7XG4gICAgcmVqZWN0ZWQgPSB0cnVlO1xuICB9XG4gIGFzc2VydEVxdWFscyhyZWplY3RlZCwgdHJ1ZSk7XG59KTtcbiJdLCJuYW1lcyI6W10sIm1hcHBpbmdzIjoiQUFBQSxTQUFTLFlBQVksUUFBUSxrREFBa0Q7QUFDL0UsU0FBUyx3QkFBd0IsUUFBUSxvQ0FBb0M7QUFDN0UsU0FBUyxlQUFlLFFBQVEsb0RBQW9EO0FBQ3BGLE1BQU0sT0FBTztFQUFDO0lBQ1osYUFBYTtJQUNiLFdBQVc7SUFDWCxhQUFhO0VBQ2Y7RUFBRztJQUNELGFBQWE7SUFDYixXQUFXO0lBQ1gsYUFBYTtFQUNmO0NBQUU7QUFDRixNQUFNLGFBQWEsS0FBSyxHQUFHLENBQUMsQ0FBQyxLQUFLLFFBQVUsQ0FBQztJQUMzQyxHQUFHLEdBQUc7SUFDTixZQUFZLFFBQVE7SUFDcEIsWUFBWTtFQUNkLENBQUM7QUFDRCxLQUFLLElBQUksQ0FBQyxvRkFBb0Y7RUFDNUYsYUFBYSx5QkFBeUIsTUFBTSxZQUFZLFdBQVcsRUFBRTtFQUNyRSxhQUFhLHlCQUF5QixNQUFNO0lBQUMsVUFBVSxDQUFDLEVBQUU7R0FBQyxFQUFFLE1BQU0sRUFBRTtFQUNyRSxhQUNFLHlCQUF5QixNQUFNO0lBQUMsVUFBVSxDQUFDLEVBQUU7SUFBRSxVQUFVLENBQUMsRUFBRTtHQUFDLEVBQUUsV0FBVyxFQUMxRTtFQUVGLGFBQ0UseUJBQXlCLE1BQU07SUFBQztNQUM5QixHQUFHLFVBQVUsQ0FBQyxFQUFFO01BQ2hCLGFBQWE7SUFDZjtHQUFFLEVBQUUsc0JBQXNCLEVBQzFCO0VBRUYsYUFBYSx5QkFBeUIsRUFBRSxFQUFFLFlBQVksU0FBUyxFQUFFO0FBQ25FO0FBQ0EsS0FBSyxJQUFJLENBQUMsbUVBQW1FO0VBQzNFLEtBQ0UsTUFBTSxTQUFTO0lBQUM7TUFBRSxhQUFhO0lBQWE7SUFBRztNQUFFLFdBQVc7SUFBRztJQUFHO01BQ2hFLGFBQWE7SUFDZjtJQUFHO01BQUUsWUFBWTtJQUFHO0dBQUUsQ0FDdEI7SUFDQSxNQUFNLFNBQVMseUJBQXlCLE1BQU07TUFBQztRQUM3QyxHQUFHLFVBQVUsQ0FBQyxFQUFFO1FBQ2hCLEdBQUcsS0FBSztNQUNWO0tBQUU7SUFDRixhQUFhLE9BQU8sVUFBVSxFQUFFO0lBQ2hDLGFBQWEsT0FBTyxZQUFZLEVBQUU7RUFDcEM7QUFDRjtBQUNBLEtBQ0UsTUFBTSxVQUFVO0VBQ2Q7RUFDQTtFQUNBO0NBQ0QsQ0FDRDtFQUNBLEtBQUssSUFBSSxDQUFDLENBQUMsbUNBQW1DLEVBQUUsUUFBUSxFQUFFO0lBQ3hELE1BQU0sU0FBUyxnQkFDYixTQUFTO0lBRVgsYUFBYSx5QkFBeUI7TUFBQyxJQUFJLENBQUMsRUFBRTtLQUFDLEVBQUUsUUFBUSxXQUFXLEVBQUU7RUFDeEU7QUFDRjtBQUNBLEtBQUssSUFBSSxDQUFDLGtFQUFrRTtFQUMxRSxJQUFJLFdBQVc7RUFDZixJQUFJO0lBQ0YsZ0JBQ0U7RUFFSixFQUFFLE9BQU07SUFDTixXQUFXO0VBQ2I7RUFDQSxhQUFhLFVBQVU7QUFDekIifQ==
// denoCacheMetadata=13498056076408480453,14693197406806326152