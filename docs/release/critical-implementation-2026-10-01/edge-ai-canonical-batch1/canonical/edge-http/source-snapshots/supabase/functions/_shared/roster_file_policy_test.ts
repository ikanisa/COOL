import {
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  decodeRosterFile,
  MAX_ROSTER_FILE_BYTES,
  validateRosterFile,
} from "./roster_file_policy.ts";
import { PublicError } from "./production_contract.ts";
// Synthetic solid 2x3 images encoded by Pillow; no personal/vendor data.
const fixtures = {
  "PNG":
    "iVBORw0KGgoAAAANSUhEUgAAAAIAAAADCAIAAAA2iEnWAAAAFElEQVR4nGOUS+lhYGBgYgADKAUAE/ABFCFAuesAAAAASUVORK5CYII=",
  "JPEG":
    "/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJCQwLDBgNDRgyIRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjL/wAARCAADAAIDASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwDk6KKK9w+dP//Z",
  "WEBP":
    "UklGRjgAAABXRUJQVlA4ICwAAADwAQCdASoCAAMAAUAmJaACdLoB+AAETAAA/vD6K/8Qz0epku/+Uq8Fjc3wAA==",
  "JPEG_PROGRESSIVE":
    "/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJCQwLDBgNDRgyIRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjL/wgARCAADAAIDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAX/xAAVAQEBAAAAAAAAAAAAAAAAAAAEBf/aAAwDAQACEAMQAAABkh07/8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABBQJ//8QAFBEBAAAAAAAAAAAAAAAAAAAAAP/aAAgBAwEBPwF//8QAFBEBAAAAAAAAAAAAAAAAAAAAAP/aAAgBAgEBPwF//8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQAGPwJ//8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABPyF//9oADAMBAAIAAwAAABAD/8QAFBEBAAAAAAAAAAAAAAAAAAAAAP/aAAgBAwEBPxB//8QAFBEBAAAAAAAAAAAAAAAAAAAAAP/aAAgBAgEBPxB//8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABPxB//9k=",
  "WEBP_LOSSLESS": "UklGRh4AAABXRUJQVlA4TBEAAAAvAYAAAAdQsnqUsf+BiOh/AAA=",
};
const bytes = (key: keyof typeof fixtures) => decodeRosterFile(fixtures[key]);
const reject = (
  file: Uint8Array,
  mime: string,
  code = "roster_invalid_file",
) => {
  assertEquals(
    assertThrows(() => validateRosterFile(file, mime), PublicError).code,
    code,
  );
};
for (
  const [name, mime] of Object.entries({
    PNG: "image/png",
    JPEG: "image/jpeg",
    WEBP: "image/webp",
    JPEG_PROGRESSIVE: "image/jpeg",
    WEBP_LOSSLESS: "image/webp",
  })
) {
  Deno.test(`roster accepts complete ${name} fixture`, () =>
    validateRosterFile(bytes(name as keyof typeof fixtures), mime));
  Deno.test(`roster rejects truncated ${name}`, () => {
    const b = bytes(name as keyof typeof fixtures);
    reject(b.subarray(0, b.length - 2), mime);
  });
}
Deno.test("roster rejects MIME spoofing for every allowed MIME", () => {
  for (
    const mime of ["image/png", "image/jpeg", "image/webp", "application/pdf"]
  ) {
    reject(
      new TextEncoder().encode("<html>untrusted</html>"),
      mime,
      "roster_type_mismatch",
    );
  }
});
Deno.test("base64 rejects corrupt encoding, nonzero padding bits and surrounding whitespace", () => {
  for (
    const value of ["YQ=", "YQ===", "Y?==", "YR==", " YQ==", "YQ==\n", "===="]
  ) assertThrows(() => decodeRosterFile(value), PublicError);
  assertEquals(decodeRosterFile("YQ=="), new Uint8Array([97]));
});
Deno.test("base64 enforces exact decoded limit including final padded quartet", () => {
  const atLimit = "AAAA".repeat(Math.floor(MAX_ROSTER_FILE_BYTES / 3)) + "AAA=";
  assertEquals(decodeRosterFile(atLimit).length, MAX_ROSTER_FILE_BYTES);
  assertEquals(
    assertThrows(
      () => decodeRosterFile(atLimit.slice(0, -1) + "A"),
      PublicError,
    ).code,
    "roster_size_invalid",
  );
});
Deno.test("PNG rejects bad chunk CRC and trailing data", () => {
  const b = bytes("PNG");
  b[45] ^= 1;
  reject(b, "image/png");
  reject(new Uint8Array([...bytes("PNG"), 0]), "image/png");
});
Deno.test("PNG rejects oversized dimensions even when header CRC is valid", () => {
  const b = bytes("PNG"), view = new DataView(b.buffer);
  view.setUint32(16, 16001);
  let crc = 0xffffffff;
  for (const byte of b.subarray(12, 29)) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit++) {
      crc = (crc >>> 1) ^ ((crc & 1) ? 0xedb88320 : 0);
    }
  }
  view.setUint32(29, (crc ^ 0xffffffff) >>> 0);
  reject(b, "image/png", "roster_image_dimensions_exceeded");
});
Deno.test("JPEG rejects missing frame, oversized frame and out-of-bounds segment", () => {
  reject(new Uint8Array([255, 216, 255, 217]), "image/jpeg");
  const b = bytes("JPEG");
  const sof = b.findIndex((x, i) => x === 255 && b[i + 1] === 192);
  b[sof + 7] = 0xff;
  b[sof + 8] = 0xff;
  reject(b, "image/jpeg", "roster_image_dimensions_exceeded");
  const c = bytes("JPEG");
  c[4] = 0xff;
  c[5] = 0xff;
  reject(c, "image/jpeg");
});
Deno.test("WebP rejects oversized VP8 and VP8L dimensions, wrong RIFF size and chunk length", () => {
  const b = bytes("WEBP");
  b[26] = 0xff;
  b[27] = 0x3f;
  b[28] = 0xff;
  b[29] = 0x3f;
  reject(b, "image/webp", "roster_image_dimensions_exceeded");
  const lossless = bytes("WEBP_LOSSLESS");
  lossless[21] = 0xff;
  lossless[22] = 0xff;
  lossless[23] = 0xff;
  lossless[24] = 0x0f;
  reject(lossless, "image/webp", "roster_image_dimensions_exceeded");
  const c = bytes("WEBP");
  c[4]++;
  reject(c, "image/webp");
  const d = bytes("WEBP");
  d[16] = 0xff;
  reject(d, "image/webp");
});
Deno.test("PDF requires complete trailer and in-range cross-reference pointer", () => {
  const encode = (value: string) => new TextEncoder().encode(value);
  // Framing fixture only, deliberately not a claim of complete PDF decoding.
  const pdf =
    "%PDF-1.7\nxref\n0 1\n0000000000 65535 f \ntrailer\n<< /Size 1 >>\nstartxref\n9\n%%EOF\n";
  validateRosterFile(encode(pdf), "application/pdf");
  for (
    const invalid of [
      "%PDF-1.7\n",
      pdf.replace("startxref\n9", "startxref\n999"),
      pdf.replace("%%EOF", ""),
      pdf + "<script>",
    ]
  ) reject(encode(invalid), "application/pdf");
});
Deno.test("all file types reject empty and oversized payloads", () => {
  for (
    const mime of ["image/png", "image/jpeg", "image/webp", "application/pdf"]
  ) {
    reject(new Uint8Array(), mime, "roster_size_invalid");
    reject(
      new Uint8Array(MAX_ROSTER_FILE_BYTES + 1),
      mime,
      "roster_size_invalid",
    );
  }
});
