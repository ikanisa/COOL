import { assertEquals } from "./test_assert.ts";
import { canonicalRwandaMomoNumber, normalizeRosterCandidates, parseRosterText } from "./roster_import.ts";
Deno.test("parses a quoted reviewed CSV roster", ()=>{
  const rows = parseRosterText([
    "member_name,momo_name,momo_number",
    '"Alice A.","ALICE UWASE","0788 000 456"',
    "Bob,BOSCO BOB,+250788000457"
  ].join("\n"));
  const preview = normalizeRosterCandidates(rows);
  assertEquals(preview.can_submit, true);
  assertEquals(preview.normalized_rows, [
    {
      member_name: "Alice A.",
      momo_name: "ALICE UWASE",
      momo_number: "+250788000456"
    },
    {
      member_name: "Bob",
      momo_name: "BOSCO BOB",
      momo_number: "+250788000457"
    }
  ]);
});
Deno.test("parses headerless tab-separated rows", ()=>{
  const rows = parseRosterText("Alice\tALICE UWASE\t0788000456\nBob\tBOB MUGISHA\t0788000457");
  assertEquals(normalizeRosterCandidates(rows).ready_count, 2);
});
Deno.test("invalid, low-confidence and duplicate numbers remain review-only", ()=>{
  const preview = normalizeRosterCandidates([
    {
      source_row: 3,
      member_name: "Alice",
      momo_name: "ALICE UWASE",
      momo_number: "0788000456",
      confidence: 0.95
    },
    {
      source_row: 4,
      member_name: "Bob",
      momo_name: "BOB MUGISHA",
      momo_number: "+250788000456",
      confidence: 0.6
    }
  ]);
  assertEquals(preview.can_submit, false);
  assertEquals(preview.error_count, 1);
  assertEquals(preview.rows[1].issues.length, 2);
});
Deno.test("spreadsheet formula-like names remain review-only", ()=>{
  const preview = normalizeRosterCandidates([
    {
      source_row: 1,
      member_name: '=HYPERLINK("https://example.test")',
      momo_name: "SAFE NAME",
      momo_number: "0788123456",
      confidence: 1
    }
  ]);
  assertEquals(preview.can_submit, false);
  assertEquals(preview.rows[0].issues.includes("Names cannot begin with spreadsheet formula characters"), true);
});
Deno.test("Rwanda MoMo normalization rejects masked or foreign numbers", ()=>{
  assertEquals(canonicalRwandaMomoNumber("0788-000-456"), "+250788000456");
  assertEquals(canonicalRwandaMomoNumber("***456"), null);
  assertEquals(canonicalRwandaMomoNumber("+35699123456"), null);
});
//# sourceMappingURL=data:application/json;base64,eyJ2ZXJzaW9uIjozLCJzb3VyY2VzIjpbImZpbGU6Ly8vVm9sdW1lcy9QUk8tRzQwL1Byb2plY3RzL1JlY292ZXJlZC1HLVBSTy9DT09ML2RvY3MvcmVsZWFzZS9jcml0aWNhbC1pbXBsZW1lbnRhdGlvbi0yMDI2LTEwLTAxL3N1Y2Nlc3Nvci1vYnNlcnZlZC1maXh0dXJlLWltcG9ydC1wcm9wb3NhbDEvY2FuZGlkYXRlLXN0YWdlMS9zb3VyY2Uvc3VwYWJhc2UvZnVuY3Rpb25zL19zaGFyZWQvcm9zdGVyX2ltcG9ydF90ZXN0LnRzIl0sInNvdXJjZXNDb250ZW50IjpbImltcG9ydCB7IGFzc2VydEVxdWFscyB9IGZyb20gXCIuL3Rlc3RfYXNzZXJ0LnRzXCI7XG5pbXBvcnQge1xuICBjYW5vbmljYWxSd2FuZGFNb21vTnVtYmVyLFxuICBub3JtYWxpemVSb3N0ZXJDYW5kaWRhdGVzLFxuICBwYXJzZVJvc3RlclRleHQsXG59IGZyb20gXCIuL3Jvc3Rlcl9pbXBvcnQudHNcIjtcblxuRGVuby50ZXN0KFwicGFyc2VzIGEgcXVvdGVkIHJldmlld2VkIENTViByb3N0ZXJcIiwgKCkgPT4ge1xuICBjb25zdCByb3dzID0gcGFyc2VSb3N0ZXJUZXh0KFtcbiAgICBcIm1lbWJlcl9uYW1lLG1vbW9fbmFtZSxtb21vX251bWJlclwiLFxuICAgICdcIkFsaWNlIEEuXCIsXCJBTElDRSBVV0FTRVwiLFwiMDc4OCAwMDAgNDU2XCInLFxuICAgIFwiQm9iLEJPU0NPIEJPQiwrMjUwNzg4MDAwNDU3XCIsXG4gIF0uam9pbihcIlxcblwiKSk7XG4gIGNvbnN0IHByZXZpZXcgPSBub3JtYWxpemVSb3N0ZXJDYW5kaWRhdGVzKHJvd3MpO1xuICBhc3NlcnRFcXVhbHMocHJldmlldy5jYW5fc3VibWl0LCB0cnVlKTtcbiAgYXNzZXJ0RXF1YWxzKHByZXZpZXcubm9ybWFsaXplZF9yb3dzLCBbXG4gICAge1xuICAgICAgbWVtYmVyX25hbWU6IFwiQWxpY2UgQS5cIixcbiAgICAgIG1vbW9fbmFtZTogXCJBTElDRSBVV0FTRVwiLFxuICAgICAgbW9tb19udW1iZXI6IFwiKzI1MDc4ODAwMDQ1NlwiLFxuICAgIH0sXG4gICAge1xuICAgICAgbWVtYmVyX25hbWU6IFwiQm9iXCIsXG4gICAgICBtb21vX25hbWU6IFwiQk9TQ08gQk9CXCIsXG4gICAgICBtb21vX251bWJlcjogXCIrMjUwNzg4MDAwNDU3XCIsXG4gICAgfSxcbiAgXSk7XG59KTtcblxuRGVuby50ZXN0KFwicGFyc2VzIGhlYWRlcmxlc3MgdGFiLXNlcGFyYXRlZCByb3dzXCIsICgpID0+IHtcbiAgY29uc3Qgcm93cyA9IHBhcnNlUm9zdGVyVGV4dChcbiAgICBcIkFsaWNlXFx0QUxJQ0UgVVdBU0VcXHQwNzg4MDAwNDU2XFxuQm9iXFx0Qk9CIE1VR0lTSEFcXHQwNzg4MDAwNDU3XCIsXG4gICk7XG4gIGFzc2VydEVxdWFscyhub3JtYWxpemVSb3N0ZXJDYW5kaWRhdGVzKHJvd3MpLnJlYWR5X2NvdW50LCAyKTtcbn0pO1xuXG5EZW5vLnRlc3QoXCJpbnZhbGlkLCBsb3ctY29uZmlkZW5jZSBhbmQgZHVwbGljYXRlIG51bWJlcnMgcmVtYWluIHJldmlldy1vbmx5XCIsICgpID0+IHtcbiAgY29uc3QgcHJldmlldyA9IG5vcm1hbGl6ZVJvc3RlckNhbmRpZGF0ZXMoW1xuICAgIHtcbiAgICAgIHNvdXJjZV9yb3c6IDMsXG4gICAgICBtZW1iZXJfbmFtZTogXCJBbGljZVwiLFxuICAgICAgbW9tb19uYW1lOiBcIkFMSUNFIFVXQVNFXCIsXG4gICAgICBtb21vX251bWJlcjogXCIwNzg4MDAwNDU2XCIsXG4gICAgICBjb25maWRlbmNlOiAwLjk1LFxuICAgIH0sXG4gICAge1xuICAgICAgc291cmNlX3JvdzogNCxcbiAgICAgIG1lbWJlcl9uYW1lOiBcIkJvYlwiLFxuICAgICAgbW9tb19uYW1lOiBcIkJPQiBNVUdJU0hBXCIsXG4gICAgICBtb21vX251bWJlcjogXCIrMjUwNzg4MDAwNDU2XCIsXG4gICAgICBjb25maWRlbmNlOiAwLjYsXG4gICAgfSxcbiAgXSk7XG4gIGFzc2VydEVxdWFscyhwcmV2aWV3LmNhbl9zdWJtaXQsIGZhbHNlKTtcbiAgYXNzZXJ0RXF1YWxzKHByZXZpZXcuZXJyb3JfY291bnQsIDEpO1xuICBhc3NlcnRFcXVhbHMocHJldmlldy5yb3dzWzFdLmlzc3Vlcy5sZW5ndGgsIDIpO1xufSk7XG5cbkRlbm8udGVzdChcInNwcmVhZHNoZWV0IGZvcm11bGEtbGlrZSBuYW1lcyByZW1haW4gcmV2aWV3LW9ubHlcIiwgKCkgPT4ge1xuICBjb25zdCBwcmV2aWV3ID0gbm9ybWFsaXplUm9zdGVyQ2FuZGlkYXRlcyhbe1xuICAgIHNvdXJjZV9yb3c6IDEsXG4gICAgbWVtYmVyX25hbWU6ICc9SFlQRVJMSU5LKFwiaHR0cHM6Ly9leGFtcGxlLnRlc3RcIiknLFxuICAgIG1vbW9fbmFtZTogXCJTQUZFIE5BTUVcIixcbiAgICBtb21vX251bWJlcjogXCIwNzg4MTIzNDU2XCIsXG4gICAgY29uZmlkZW5jZTogMSxcbiAgfV0pO1xuICBhc3NlcnRFcXVhbHMocHJldmlldy5jYW5fc3VibWl0LCBmYWxzZSk7XG4gIGFzc2VydEVxdWFscyhcbiAgICBwcmV2aWV3LnJvd3NbMF0uaXNzdWVzLmluY2x1ZGVzKFxuICAgICAgXCJOYW1lcyBjYW5ub3QgYmVnaW4gd2l0aCBzcHJlYWRzaGVldCBmb3JtdWxhIGNoYXJhY3RlcnNcIixcbiAgICApLFxuICAgIHRydWUsXG4gICk7XG59KTtcblxuRGVuby50ZXN0KFwiUndhbmRhIE1vTW8gbm9ybWFsaXphdGlvbiByZWplY3RzIG1hc2tlZCBvciBmb3JlaWduIG51bWJlcnNcIiwgKCkgPT4ge1xuICBhc3NlcnRFcXVhbHMoY2Fub25pY2FsUndhbmRhTW9tb051bWJlcihcIjA3ODgtMDAwLTQ1NlwiKSwgXCIrMjUwNzg4MDAwNDU2XCIpO1xuICBhc3NlcnRFcXVhbHMoY2Fub25pY2FsUndhbmRhTW9tb051bWJlcihcIioqKjQ1NlwiKSwgbnVsbCk7XG4gIGFzc2VydEVxdWFscyhjYW5vbmljYWxSd2FuZGFNb21vTnVtYmVyKFwiKzM1Njk5MTIzNDU2XCIpLCBudWxsKTtcbn0pO1xuIl0sIm5hbWVzIjpbXSwibWFwcGluZ3MiOiJBQUFBLFNBQVMsWUFBWSxRQUFRLG1CQUFtQjtBQUNoRCxTQUNFLHlCQUF5QixFQUN6Qix5QkFBeUIsRUFDekIsZUFBZSxRQUNWLHFCQUFxQjtBQUU1QixLQUFLLElBQUksQ0FBQyx1Q0FBdUM7RUFDL0MsTUFBTSxPQUFPLGdCQUFnQjtJQUMzQjtJQUNBO0lBQ0E7R0FDRCxDQUFDLElBQUksQ0FBQztFQUNQLE1BQU0sVUFBVSwwQkFBMEI7RUFDMUMsYUFBYSxRQUFRLFVBQVUsRUFBRTtFQUNqQyxhQUFhLFFBQVEsZUFBZSxFQUFFO0lBQ3BDO01BQ0UsYUFBYTtNQUNiLFdBQVc7TUFDWCxhQUFhO0lBQ2Y7SUFDQTtNQUNFLGFBQWE7TUFDYixXQUFXO01BQ1gsYUFBYTtJQUNmO0dBQ0Q7QUFDSDtBQUVBLEtBQUssSUFBSSxDQUFDLHdDQUF3QztFQUNoRCxNQUFNLE9BQU8sZ0JBQ1g7RUFFRixhQUFhLDBCQUEwQixNQUFNLFdBQVcsRUFBRTtBQUM1RDtBQUVBLEtBQUssSUFBSSxDQUFDLG9FQUFvRTtFQUM1RSxNQUFNLFVBQVUsMEJBQTBCO0lBQ3hDO01BQ0UsWUFBWTtNQUNaLGFBQWE7TUFDYixXQUFXO01BQ1gsYUFBYTtNQUNiLFlBQVk7SUFDZDtJQUNBO01BQ0UsWUFBWTtNQUNaLGFBQWE7TUFDYixXQUFXO01BQ1gsYUFBYTtNQUNiLFlBQVk7SUFDZDtHQUNEO0VBQ0QsYUFBYSxRQUFRLFVBQVUsRUFBRTtFQUNqQyxhQUFhLFFBQVEsV0FBVyxFQUFFO0VBQ2xDLGFBQWEsUUFBUSxJQUFJLENBQUMsRUFBRSxDQUFDLE1BQU0sQ0FBQyxNQUFNLEVBQUU7QUFDOUM7QUFFQSxLQUFLLElBQUksQ0FBQyxxREFBcUQ7RUFDN0QsTUFBTSxVQUFVLDBCQUEwQjtJQUFDO01BQ3pDLFlBQVk7TUFDWixhQUFhO01BQ2IsV0FBVztNQUNYLGFBQWE7TUFDYixZQUFZO0lBQ2Q7R0FBRTtFQUNGLGFBQWEsUUFBUSxVQUFVLEVBQUU7RUFDakMsYUFDRSxRQUFRLElBQUksQ0FBQyxFQUFFLENBQUMsTUFBTSxDQUFDLFFBQVEsQ0FDN0IsMkRBRUY7QUFFSjtBQUVBLEtBQUssSUFBSSxDQUFDLCtEQUErRDtFQUN2RSxhQUFhLDBCQUEwQixpQkFBaUI7RUFDeEQsYUFBYSwwQkFBMEIsV0FBVztFQUNsRCxhQUFhLDBCQUEwQixpQkFBaUI7QUFDMUQifQ==
// denoCacheMetadata=10711321892276739233,5287555371655211167