import { isId, isObject, isSafeCount, parseCoreRow } from './contracts';
import type { DataRow } from './types';

function parseActiveCollectPerson(row: unknown): DataRow {
  const owner = parseCoreRow('users', 'canonical_evidence_ledger', row);
  if (owner.status !== 'active' || owner.collect_user_id !== owner.id || !['app', 'direct'].includes(String(owner.member_type)) ||
      !isSafeCount(owner.version) || owner.version < 1 || !owner.display_name_recorded) throw new Error('Owner unavailable');
  return owner;
}
export function parseCollectPersonDetail(data: Record<string, unknown>, id: unknown, actor: string, label: 'Owner' | 'Member'): DataRow {
  if (!isId(id) || data.contract_version !== 2 || data.model !== 'canonical_evidence_ledger' || data.resource_type !== 'users' ||
      data.current_actor_id !== actor || !isObject(data.resource) || data.resource.id !== id) throw new Error(label + ' unavailable');
  return parseActiveCollectPerson(data.resource);
}
export function sameCollectPerson(left: DataRow, right: DataRow): boolean {
  return ['id', 'version', 'public_id', 'display_name', 'momo_provider', 'momo_number', 'momo_pay_code'].every(key => left[key] === right[key]);
}
export function parseCollectPeople(value: unknown): DataRow[] {
  if (!isObject(value) || Object.keys(value).length !== 6 || value.contract_version !== 2 || value.model !== 'canonical_evidence_ledger' ||
      value.kind !== 'users' || value.group_id !== null || !Array.isArray(value.rows) || !isSafeCount(value.total) ||
      value.rows.length !== Math.min(100, value.total)) throw new Error('Owner lookup unavailable');
  const result = value.rows.map(row => {
    if (!isObject(row) || typeof row.label !== 'string' || !row.label.trim() || row.label !== row.name || row.label !== row.display_name) throw new Error('Owner lookup unavailable');
    return parseActiveCollectPerson(row);
  });
  if (new Set(result.map(row => row.id)).size !== result.length) throw new Error('Owner lookup unavailable');
  return result;
}
