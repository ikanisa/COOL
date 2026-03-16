import {
  assertEquals,
  assertStrictEquals,
} from "https://deno.land/std@0.224.0/assert/mod.ts";

import {
  normalizeDocumentType,
  normalizeIsoDate,
  normalizeKycExtraction,
  unwrapJsonText,
} from "./rules.ts";

Deno.test("normalizeDocumentType maps common identity labels", () => {
  assertEquals(normalizeDocumentType("National ID Card"), "national_id");
  assertEquals(normalizeDocumentType("Passport"), "passport");
  assertEquals(normalizeDocumentType("Driving License"), "driving_license");
  assertEquals(normalizeDocumentType("Residence Permit"), "residence_permit");
  assertStrictEquals(normalizeDocumentType("membership"), null);
});

Deno.test("normalizeIsoDate handles iso and slash dates", () => {
  assertEquals(normalizeIsoDate("1998-03-12"), "1998-03-12");
  assertEquals(normalizeIsoDate("03/12/1998"), "1998-03-12");
  assertStrictEquals(normalizeIsoDate("not-a-date"), null);
});

Deno.test("unwrapJsonText strips markdown fences", () => {
  assertEquals(
    unwrapJsonText('```json\n{"fullName":"Jane"}\n```'),
    '{"fullName":"Jane"}',
  );
});

Deno.test("normalizeKycExtraction normalizes core OCR fields", () => {
  assertEquals(
    normalizeKycExtraction(
      {
        fullName: "Jane Doe",
        dateOfBirth: "03/12/1998",
        nationalIdNumber: "1234567890123456",
        gender: "f",
        nationality: "Rwandan",
        documentType: "National ID Card",
        issuingCountry: "Rwanda",
        expiryDate: "2030-12-01",
        confidence: "0.82",
      },
      "passport",
    ),
    {
      fullName: "Jane Doe",
      dateOfBirth: "1998-03-12",
      nationalIdNumber: "1234567890123456",
      gender: "F",
      nationality: "Rwandan",
      documentType: "national_id",
      issuingCountry: "Rwanda",
      expiryDate: "2030-12-01",
      confidence: 0.82,
    },
  );
});
