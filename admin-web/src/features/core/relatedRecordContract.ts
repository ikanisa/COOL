import { isObject, isSafeCount } from './contracts';

const relations: Record<string, readonly string[]> = { groups: ['memberships', 'payees', 'accounts'], users: ['memberships'], payees: [], transactions: ['evidence', 'reviews', 'allocations', 'journals', 'payer_insights', 'ledger_entries'], journals: ['entries'], ledgers: [] };
export interface RelatedPage { total: number; limit: number; offset: number; nextOffset: number | null }

export function relatedPage(data: Record<string, unknown>, name: string, rows: unknown[]): RelatedPage | null {
  if (data.related_pages === undefined || data.related_pages === null) {
    if (data.related_truncated === true) throw new Error('The related record page is incomplete.');
    return null;
  }
  if (!isObject(data.related_pages) || !isObject(data.related_pages[name])) throw new Error('Invalid related page');
  const page = data.related_pages[name];
  if (Object.keys(page).length !== 4 || !isSafeCount(page.total) || !isSafeCount(page.limit) || page.limit < 1 || page.limit > 100 ||
      !isSafeCount(page.offset) || rows.length !== Math.min(page.limit, Math.max(0, page.total - page.offset)) ||
      page.next_offset !== (page.offset + rows.length < page.total ? page.offset + rows.length : null)) throw new Error('Invalid related page');
  return { total: page.total, limit: page.limit, offset: page.offset, nextOffset: page.next_offset as number | null };
}

export function validateRelated(data: Record<string, unknown>, resource: string, requiredRelation?: string): void {
  if (!isObject(data.related) || typeof data.related_truncated !== 'boolean') throw new Error('Invalid related records');
  const names = Object.keys(data.related);
  if (requiredRelation && (names.length !== 1 || names[0] !== requiredRelation)) throw new Error('Invalid related page');
  if (isObject(data.related_pages) && Object.keys(data.related_pages).length !== names.length) throw new Error('Invalid related pages');
  for (const name of names) {
    const rows = data.related[name];
    if (!relations[resource]?.includes(name) || !Array.isArray(rows) || rows.length > 200 || rows.some(row => !isObject(row))) throw new Error('Invalid related records');
    relatedPage(data, name, rows);
  }
}
