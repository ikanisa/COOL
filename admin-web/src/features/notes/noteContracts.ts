/* eslint-disable no-control-regex -- Reject disallowed control characters in private note content. */
import {isId, isObject, isSafeCount} from '../core/contracts';

export type NoteArea = 'groups' | 'users';
interface Note {id: string; body: string; author: string; createdAt: string}
interface NotePage {rows: Note[]; total: number}

function invalid(): never {throw new Error('Support notes could not be verified.');}
function exactKeys(value: Record<string, unknown>, keys: string[]): boolean {
  return Object.keys(value).length === keys.length && keys.every(key => Object.hasOwn(value, key));
}

/** The endpoint returns private note text; validate its entity and page before rendering. */
export function parseOperatorNotes(value: unknown, area: NoteArea, id: string, offset: number): NotePage {
  if (!isId(id) || !Number.isSafeInteger(offset) || offset < 0 || offset > 10000 || !isObject(value) ||
      !exactKeys(value, ['contract_version', 'entity_type', 'entity_id', 'rows', 'total', 'limit', 'offset']) ||
      value.contract_version !== 1 || value.entity_type !== (area === 'groups' ? 'collection' : 'profile') ||
      value.entity_id !== id || value.limit !== 25 || value.offset !== offset ||
      !isSafeCount(value.total) || !Array.isArray(value.rows) ||
      value.rows.length !== Math.min(25, Math.max(0, value.total - offset))) return invalid();
  const seen = new Set<string>();
  const rows = value.rows.map((row): Note => {
    if (!isObject(row) || !exactKeys(row, ['id', 'body', 'created_by', 'author_name', 'created_at']) ||
        !isId(row.id) || !isId(row.created_by) || seen.has(row.id) ||
        typeof row.body !== 'string' || !row.body.trim() || row.body.length > 2000 || /[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/.test(row.body) ||
        typeof row.author_name !== 'string' || !row.author_name.trim() || row.author_name.length > 120 || /[\x00-\x1f\x7f]/.test(row.author_name) ||
        typeof row.created_at !== 'string' || !/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$/.test(row.created_at) ||
        !Number.isFinite(Date.parse(row.created_at)) || new Date(row.created_at).toISOString() !== row.created_at) return invalid();
    seen.add(row.id);
    return {id: row.id, body: row.body, author: row.author_name, createdAt: row.created_at};
  });
  return {rows, total: value.total};
}
