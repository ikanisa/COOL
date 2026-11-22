import { BuriError, requireThat } from './errors.js';
import { normalizePhone } from './values.js';
import { defs } from './wire/burimunsi.generated.mjs';
import { validateSchema } from './wire/runtime.mjs';

export const SMART_IMPORT_LIMITS = Object.freeze({
  documentBytes: 5 * 1024 * 1024,
  csvBytes: 2 * 1024 * 1024,
  rows: 500,
  columns: 32,
  fieldCharacters: 1024,
  decoderResponseBytes: 7100000,
  providerResponseBytes: 262144,
});

export const PDF_MIME = 'application/pdf';
export const XLSX_MIME = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
const IMAGE_TYPES = new Set(['image/png', 'image/jpeg', 'image/webp']);
const CSV_TYPES = new Set(['text/csv', 'text/comma-separated-values', 'application/csv', 'text/plain']);
export function isImportImage(mime) {
  return IMAGE_TYPES.has(mime);
}

export function isSmartImportDocument(mime) {
  return mime === PDF_MIME || mime === XLSX_MIME || isImportImage(mime);
}

export function smartImportSourceKind(mime) {
  switch (mime) {
    case 'text/csv':
      return 'csv';
    case XLSX_MIME:
      return 'xlsx';
    case PDF_MIME:
      return 'pdf';
    default:
      return 'image';
  }
}

export function assertSmartImportPreview(preview, mime) {
  try {
    validateSchema(defs, 'onboardingPreview.data', preview);
  } catch {
    throw new BuriError('smart_import_recovery_invalid', 503);
  }
  requireThat(preview.sourceKind === smartImportSourceKind(mime), 'smart_import_recovery_invalid', 503);
}

export function isSmartImportRow(row) {
  return row !== null && typeof row === 'object' && !Array.isArray(row) &&
    Object.keys(row).length === 2 && Object.hasOwn(row, 'momoName') && Object.hasOwn(row, 'momoNumber') &&
    typeof row.momoName === 'string' && typeof row.momoNumber === 'string' &&
    row.momoName.length <= SMART_IMPORT_LIMITS.fieldCharacters &&
    row.momoNumber.length <= SMART_IMPORT_LIMITS.fieldCharacters;
}

function begins(bytes, signature) {
  return bytes.length >= signature.length && signature.every((value, index) => bytes[index] === value);
}

/** Reject MIME/signature disagreement before passing a document to any decoder. */
export function identifySmartImport(bytes, mimeType) {
  requireThat(
    bytes instanceof Uint8Array && bytes.byteLength > 0 &&
      bytes.byteLength <= SMART_IMPORT_LIMITS.documentBytes,
    'smart_import_size_invalid',
  );
  requireThat(typeof mimeType === 'string' && mimeType.length <= 150, 'smart_import_type_invalid');
  const mime = mimeType.trim().toLowerCase().split(';', 1)[0];
  const png = begins(bytes, [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  const jpeg = begins(bytes, [0xff, 0xd8, 0xff]);
  const webp = bytes.length >= 12 && begins(bytes, [0x52, 0x49, 0x46, 0x46]) &&
    bytes[8] === 0x57 && bytes[9] === 0x45 && bytes[10] === 0x42 && bytes[11] === 0x50;
  const pdf = begins(bytes, [0x25, 0x50, 0x44, 0x46, 0x2d]);
  const zip = begins(bytes, [0x50, 0x4b, 0x03, 0x04]);
  let detected = png
    ? 'image/png'
    : jpeg
    ? 'image/jpeg'
    : webp
    ? 'image/webp'
    : pdf
    ? PDF_MIME
    : zip
    ? XLSX_MIME
    : null;
  if (!detected && (CSV_TYPES.has(mime) || mime === 'application/octet-stream')) {
    requireThat(bytes.byteLength <= SMART_IMPORT_LIMITS.csvBytes, 'smart_import_size_invalid');
    try {
      const text = new TextDecoder('utf-8', { fatal: true }).decode(bytes);
      requireThat(!/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/.test(text), 'smart_import_csv_invalid');
    } catch (error) {
      if (error instanceof BuriError) throw error;
      throw new BuriError('smart_import_csv_invalid');
    }
    detected = 'text/csv';
  }
  requireThat(detected !== null, 'smart_import_type_unsupported');
  requireThat(
    mime === 'application/octet-stream' || mime === detected ||
      (detected === 'text/csv' && CSV_TYPES.has(mime)),
    'smart_import_type_mismatch',
  );
  return detected;
}

const header = (value) =>
  value.normalize('NFKD').replace(/[\u0300-\u036f]/g, '')
    .toLowerCase().trim().replace(/[_\s]+/g, ' ');
const NAME_HEADERS = [
  'momo name',
  'nom momo',
  'nom de momo',
  'izina rya momo',
  'name',
  'amazina',
  'member name',
  'nom du membre',
];
const PHONE_HEADERS = [
  'momo number',
  'numero momo',
  'numero de momo',
  'nimero ya momo',
  'nambari ya momo',
  'phone',
  'phone number',
  'numero de telephone',
  'number',
  'nimero',
  'mobile',
];

// RFC-style CSV with bounded memory, strict quotes and support for quoted CRLF.
function csvGrid(text) {
  const rows = [], row = [];
  let field = '', quoted = false, closed = false;
  const pushField = () => {
    requireThat(
      field.length <= SMART_IMPORT_LIMITS.fieldCharacters &&
        row.length < SMART_IMPORT_LIMITS.columns,
      'smart_import_csv_invalid',
    );
    row.push(field);
    field = '';
    closed = false;
  };
  const pushRow = () => {
    pushField();
    requireThat(rows.length <= SMART_IMPORT_LIMITS.rows, 'smart_import_rows_limit');
    rows.push(row.splice(0));
  };
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (quoted) {
      if (c === '"' && text[i + 1] === '"') {
        field += '"';
        i++;
      } else if (c === '"') {
        quoted = false;
        closed = true;
      } else field += c;
    } else if (c === '"') {
      requireThat(field === '' && !closed, 'smart_import_csv_invalid');
      quoted = true;
    } else if (c === ',') pushField();
    else if (c === '\n' || c === '\r') {
      if (c === '\r' && text[i + 1] === '\n') i++;
      pushRow();
    } else {
      requireThat(!closed, 'smart_import_csv_invalid');
      field += c;
    }
    requireThat(field.length <= SMART_IMPORT_LIMITS.fieldCharacters, 'smart_import_csv_invalid');
  }
  requireThat(!quoted, 'smart_import_csv_invalid');
  if (field !== '' || row.length || closed) pushRow();
  return rows;
}

export function sourceRowsFromCsv(bytes) {
  let text;
  try {
    text = new TextDecoder('utf-8', { fatal: true }).decode(bytes).replace(/^\uFEFF/, '');
  } catch {
    throw new BuriError('smart_import_csv_invalid');
  }
  const grid = csvGrid(text);
  requireThat(grid.length > 0, 'smart_import_csv_invalid');
  const headers = grid.shift().map(header);
  function column(aliases) {
    for (const alias of aliases) {
      const matches = headers.flatMap((value, index) => value === alias ? [index] : []);
      requireThat(matches.length <= 1, 'smart_import_csv_invalid');
      if (matches.length === 1) return matches[0];
    }
    return -1;
  }
  const nameAt = column(NAME_HEADERS), phoneAt = column(PHONE_HEADERS);
  requireThat(nameAt >= 0 && phoneAt >= 0 && nameAt !== phoneAt, 'smart_import_csv_headers_invalid');
  return grid.filter((row) => row.some((value) => value.trim())).map((row) => ({
    momoName: row[nameAt] ?? '',
    momoNumber: row[phoneAt] ?? '',
  }));
}

/** Never treats a name or suffix as verified payer identity. */
export function prepareSmartImportRows(rows) {
  requireThat(Array.isArray(rows) && rows.length <= SMART_IMPORT_LIMITS.rows, 'smart_import_rows_limit');
  const seen = new Set();
  return rows.map((input, index) => {
    requireThat(isSmartImportRow(input), 'smart_import_row_invalid');
    const momoName = input.momoName.normalize('NFKC').trim().replace(/\s+/g, ' ');
    const rawPhone = input.momoNumber.trim();
    let momoNumber = rawPhone, status = 'ready', issue = null, normalized = null;
    if (momoName.length < 2 || momoName.length > 100 || /[\u0000-\u001f\u007f]/.test(momoName)) {
      status = 'invalid';
      issue = 'invalid_name';
    }
    try {
      normalized = normalizePhone(rawPhone);
      momoNumber = normalized;
    } catch {
      status = 'invalid';
      issue = issue ?? 'invalid_phone';
    }
    if (normalized && seen.has(normalized)) {
      status = 'duplicate_in_file';
      issue = 'duplicate_phone';
    }
    if (normalized) seen.add(normalized);
    return { row: index + 1, momoName, momoNumber, status, issue, selected: status === 'ready' };
  });
}

export function sourceRowsFromWorkbook(content) {
  const lines = content.split('\n');
  requireThat(
    lines.length >= 1 && lines.length <= SMART_IMPORT_LIMITS.rows + 1 &&
      lines[0] === 'Member name\tMoMo name\tMoMo number' && !/[\u0000\r]/.test(content),
    'smart_import_decoder_invalid',
    502,
  );
  return lines.slice(1).filter((line) => line.length).map((line) => {
    const fields = line.split('\t');
    requireThat(fields.length === 3, 'smart_import_decoder_invalid', 502);
    return { momoName: fields[1], momoNumber: fields[2] };
  });
}
