import { PublicError } from "./production_contract.ts";

export const MAX_ROSTER_FILE_BYTES = 5 * 1024 * 1024;
const MAX_IMAGE_PIXELS = 40_000_000;
const MAX_IMAGE_SIDE = 16_000;

/** Reject noncanonical/oversized encodings before allocating their decoded copy. */
export function decodeRosterFile(value: unknown): Uint8Array {
  if (
    typeof value !== "string" || !value.length ||
    value.length > 4 * Math.ceil(MAX_ROSTER_FILE_BYTES / 3)
  ) {
    throw new PublicError("roster_size_invalid");
  }
  if (!/^[A-Za-z0-9+/]*={0,2}$/.test(value) || value.length % 4 !== 0) {
    throw new PublicError("roster_invalid_base64");
  }
  const padding = value.endsWith("==") ? 2 : value.endsWith("=") ? 1 : 0;
  if (value.length / 4 * 3 - padding > MAX_ROSTER_FILE_BYTES) {
    throw new PublicError("roster_size_invalid");
  }
  let binary: string;
  try {
    binary = atob(value);
  } catch {
    throw new PublicError("roster_invalid_base64");
  }
  if (btoa(binary) !== value) throw new PublicError("roster_invalid_base64");
  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
}

function invalid(): never {
  throw new PublicError("roster_invalid_file");
}
function dimensions(width: number, height: number): void {
  if (
    !width || !height || width > MAX_IMAGE_SIDE || height > MAX_IMAGE_SIDE ||
    width * height > MAX_IMAGE_PIXELS
  ) {
    throw new PublicError("roster_image_dimensions_exceeded");
  }
}
function ascii(bytes: Uint8Array, offset: number, length: number): string {
  return String.fromCharCode(...bytes.subarray(offset, offset + length));
}
const crcTable = Uint32Array.from({ length: 256 }, (_, index) => {
  let crc = index;
  for (let bit = 0; bit < 8; bit++) {
    crc = (crc >>> 1) ^ ((crc & 1) ? 0xedb88320 : 0);
  }
  return crc >>> 0;
});
function crc32(bytes: Uint8Array): number {
  let crc = 0xffffffff;
  for (const byte of bytes) crc = crcTable[(crc ^ byte) & 255] ^ (crc >>> 8);
  return (crc ^ 0xffffffff) >>> 0;
}
function validatePng(bytes: Uint8Array, view: DataView): void {
  let offset = 8, imageData = 0;
  while (offset < bytes.length) {
    if (bytes.length - offset < 12) invalid();
    const length = view.getUint32(offset), end = offset + 12 + length;
    if (end > bytes.length) invalid();
    const type = ascii(bytes, offset + 4, 4), data = offset + 8;
    if (
      !/^[A-Za-z]{4}$/.test(type) ||
      crc32(bytes.subarray(offset + 4, end - 4)) !== view.getUint32(end - 4)
    ) invalid();
    if (offset === 8 && type !== "IHDR") invalid();
    if (type === "IHDR") {
      if (offset !== 8 || length !== 13) invalid();
      dimensions(view.getUint32(data), view.getUint32(data + 4));
      const legalDepths: Record<number, number[]> = {
        0: [1, 2, 4, 8, 16],
        2: [8, 16],
        3: [1, 2, 4, 8],
        4: [8, 16],
        6: [8, 16],
      };
      if (
        !legalDepths[bytes[data + 9]]?.includes(bytes[data + 8]) ||
        bytes[data + 10] !== 0 || bytes[data + 11] !== 0 || bytes[data + 12] > 1
      ) invalid();
    } else if (type === "IDAT") imageData += length;
    else if (type === "IEND") {
      if (length || !imageData || end !== bytes.length) invalid();
      return;
    }
    offset = end;
  }
  invalid();
}
function validateJpeg(bytes: Uint8Array, view: DataView): void {
  let offset = 2, foundFrame = false, scans = 0;
  const frameMarkers = new Set([
    0xc0,
    0xc1,
    0xc2,
    0xc3,
    0xc5,
    0xc6,
    0xc7,
    0xc9,
    0xca,
    0xcb,
    0xcd,
    0xce,
    0xcf,
  ]);
  while (offset < bytes.length) {
    if (bytes[offset++] !== 0xff) invalid();
    while (bytes[offset] === 0xff) offset++;
    const marker = bytes[offset++];
    if (marker === 0xd9) {
      if (!foundFrame || !scans || offset !== bytes.length) invalid();
      return;
    }
    if (
      !marker || marker === 0xd8 || (marker >= 0xd0 && marker <= 0xd7) ||
      offset + 2 > bytes.length
    ) invalid();
    const length = view.getUint16(offset), end = offset + length;
    if (length < 2 || end > bytes.length) invalid();
    if (frameMarkers.has(marker)) {
      if (foundFrame || length < 8 || length !== 8 + 3 * bytes[offset + 7]) {
        invalid();
      }
      dimensions(view.getUint16(offset + 5), view.getUint16(offset + 3));
      foundFrame = true;
    }
    offset = end;
    if (marker === 0xda) {
      if (!foundFrame || length < 6) invalid();
      scans++;
      // Stuffed FF and restart markers belong to entropy data, not the header.
      while (offset < bytes.length) {
        if (bytes[offset] !== 0xff) {
          offset++;
          continue;
        }
        let next = offset + 1;
        while (bytes[next] === 0xff) next++;
        if (bytes[next] === 0 || (bytes[next] >= 0xd0 && bytes[next] <= 0xd7)) {
          offset = next + 1;
        } else break;
      }
    }
  }
  invalid();
}
function validateWebp(bytes: Uint8Array, view: DataView): void {
  if (bytes.length < 20 || view.getUint32(4, true) + 8 !== bytes.length) {
    invalid();
  }
  const u24 = (at: number) =>
    bytes[at] + bytes[at + 1] * 256 + bytes[at + 2] * 65536;
  let offset = 12, image = false;
  while (offset < bytes.length) {
    if (bytes.length - offset < 8) invalid();
    const type = ascii(bytes, offset, 4),
      length = view.getUint32(offset + 4, true);
    const data = offset + 8, end = data + length, next = end + (length & 1);
    if (next > bytes.length || ((length & 1) && bytes[end] !== 0)) invalid();
    if (type === "VP8X") {
      if (offset !== 12 || length !== 10) invalid();
      dimensions(u24(data + 4) + 1, u24(data + 7) + 1);
    } else if (type === "VP8 ") {
      if (
        length < 10 || (bytes[data] & 1) !== 0 ||
        ascii(bytes, data + 3, 3) !== "\x9d\x01\x2a"
      ) invalid();
      dimensions(
        view.getUint16(data + 6, true) & 0x3fff,
        view.getUint16(data + 8, true) & 0x3fff,
      );
      image = true;
    } else if (type === "VP8L") {
      if (length < 5 || bytes[data] !== 0x2f || (bytes[data + 4] >> 5) !== 0) {
        invalid();
      }
      const packed = view.getUint32(data + 1, true);
      dimensions((packed & 0x3fff) + 1, ((packed >>> 14) & 0x3fff) + 1);
      image = true;
    } else if (type === "ANMF") {
      if (length < 24) invalid();
      dimensions(u24(data + 6) + 1, u24(data + 9) + 1);
      image = true;
    }
    offset = next;
  }
  if (!image) invalid();
}
/**
 * Bounded container/dimension checks, not a complete codec/PDF parser or malware
 * scanner. PDF page/object-stream and codec/animation expansion budgets still
 * require a sandboxed decoder before claiming extraction-resource acceptance.
 * Format references: https://www.w3.org/TR/png-3/ and
 * https://developers.google.com/speed/webp/docs/riff_container
 */
export function validateRosterFile(bytes: Uint8Array, mime: string): void {
  if (!bytes.length || bytes.length > MAX_ROSTER_FILE_BYTES) {
    throw new PublicError("roster_size_invalid");
  }
  const starts = (prefix: number[]) =>
    prefix.every((value, index) => bytes[index] === value);
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  if (mime === "image/png" && starts([137, 80, 78, 71, 13, 10, 26, 10])) {
    return validatePng(bytes, view);
  }
  if (mime === "image/jpeg" && starts([255, 216, 255])) {
    return validateJpeg(bytes, view);
  }
  if (
    mime === "image/webp" && ascii(bytes, 0, 4) === "RIFF" &&
    ascii(bytes, 8, 4) === "WEBP"
  ) return validateWebp(bytes, view);
  if (mime === "application/pdf" && ascii(bytes, 0, 5) === "%PDF-") {
    if (!/^%PDF-(?:1\.[0-7]|2\.0)[\r\n]/.test(ascii(bytes, 0, 9))) invalid();
    const tail = new TextDecoder("latin1").decode(
      bytes.subarray(Math.max(0, bytes.length - 1024)),
    );
    const trailer = /startxref\s+(\d+)\s+%%EOF[\t\r\n ]*$/.exec(tail);
    if (!trailer) invalid();
    const xref = Number(trailer[1]);
    if (
      !Number.isSafeInteger(xref) || xref < 9 || xref >= bytes.length - 20 ||
      !/^(?:xref\s|\d+\s+\d+\s+obj\b)/.test(ascii(bytes, xref, 64))
    ) invalid();
    return;
  }
  throw new PublicError("roster_type_mismatch");
}
