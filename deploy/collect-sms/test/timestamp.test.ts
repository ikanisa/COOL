import assert from "node:assert/strict";
import { ApiError, timestamp } from "../src/util.ts";

Deno.test("UTC timestamps retain valid calendar and fractional formats", () => {
  const cases: ReadonlyArray<readonly [string, string]> = [
    ["0000-02-29T00:00:00Z", "0000-02-29T00:00:00.000Z"],
    ["0099-12-31T23:59:59.1Z", "0099-12-31T23:59:59.100Z"],
    ["0100-02-28T12:34:56.12Z", "0100-02-28T12:34:56.120Z"],
    ["1900-02-28T00:00:00Z", "1900-02-28T00:00:00.000Z"],
    ["2000-02-29T23:59:59.123Z", "2000-02-29T23:59:59.123Z"],
    ["2024-02-29T12:34:56Z", "2024-02-29T12:34:56.000Z"],
    ["2025-04-30T12:34:56Z", "2025-04-30T12:34:56.000Z"],
    ["9999-12-31T23:59:59.999Z", "9999-12-31T23:59:59.999Z"],
    ["2024-02-29T24:00:00.000Z", "2024-03-01T00:00:00.000Z"],
    ["9999-12-31T24:00:00Z", "+010000-01-01T00:00:00.000Z"],
  ];
  for (const [input, expected] of cases) {
    assert.equal(timestamp(input, "time"), expected, input);
  }
});

Deno.test("UTC timestamps reject impossible calendar days", () => {
  const invalid = [
    "0000-02-30T00:00:00Z",
    "0099-02-29T00:00:00Z",
    "0100-02-29T00:00:00Z",
    "1900-02-29T00:00:00Z",
    "2000-02-30T00:00:00Z",
    "2023-02-29T00:00:00Z",
    "2024-02-30T00:00:00Z",
    "2024-02-31T00:00:00Z",
    "2024-04-31T00:00:00Z",
    "2024-06-31T00:00:00Z",
    "2024-09-31T00:00:00Z",
    "2024-11-31T00:00:00Z",
    "2100-02-29T00:00:00Z",
    "2024-00-01T00:00:00Z",
    "2024-13-01T00:00:00Z",
    "2024-01-00T00:00:00Z",
  ];
  for (const input of invalid) {
    assert.throws(
      () => timestamp(input, "scheduled_at"),
      (error: unknown) =>
        error instanceof ApiError && error.status === 400 &&
        error.code === "invalid_request" &&
        error.message.includes("scheduled_at"),
      input,
    );
  }
});

Deno.test("timestamp syntax and time bounds remain unchanged", () => {
  const invalid: unknown[] = [
    null,
    123,
    "",
    "2024-01-01T25:00:00Z",
    "2024-01-01T24:00:00.001Z",
    "2024-01-01T24:00:01Z",
    "2024-01-01T23:60:00Z",
    "2024-01-01T23:59:60Z",
    "2024-01-01T12:00:00.Z",
    "2024-01-01T12:00:00.1234Z",
    "2024-01-01T12:00:00+00:00",
    "2024-01-01T12:00:00-05:00",
    "2024-01-01T12:00:00z",
    "2024-01-01 12:00:00Z",
    "+010000-01-01T00:00:00Z",
  ];
  for (const input of invalid) {
    assert.throws(
      () => timestamp(input, "at"),
      (error: unknown) =>
        error instanceof ApiError && error.status === 400 &&
        error.code === "invalid_request" && error.message.includes("at"),
      String(input),
    );
  }
});
