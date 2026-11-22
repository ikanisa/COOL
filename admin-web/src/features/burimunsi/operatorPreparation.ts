import type { BuriDirectory, BuriSharedOperator } from './contracts';
import {CAPABILITIES, validOperatorCapabilities, type OperatorCapability} from '../../../../supabase/functions/_shared/domain/burimunsi/operator-access.mjs';

const labels: Record<OperatorCapability, string> = {
  'records.read': 'View records', 'members.enroll': 'Enroll members', 'payments.allocate': 'Allocate payments',
  'staff.manage': 'Manage staff', 'sms.read': 'View receiving SMS', 'gateway.manage': 'Manage receiving phone',
};
export const BURI_CAPABILITIES = CAPABILITIES.map(name => [name, labels[name]] as const);
export interface BuriApprovalDraft {
  collectionId: string;
  operator: BuriSharedOperator;
  phone: string;
  role: 'admin' | 'staff';
  capabilities: string[];
  active: boolean;
  expectedVersion: number;
}
export interface BuriApprovalDraftInput {phone: string; role: string; capabilities: readonly string[]; active: boolean;}
function fail(message: string): never {throw new Error(message);}
function loginPhone(value: string): string {
  if (value.length > 40 || !/^[+0-9 ()-]+$/.test(value)) return fail('Enter a Rwanda login phone number.');
  let phone = value.trim().replace(/[ ()-]/g, '');
  if (phone.startsWith('00')) phone = `+${phone.slice(2)}`;
  if (/^0\d{9}$/.test(phone)) phone = `+250${phone.slice(1)}`;
  else if (/^\d{9}$/.test(phone)) phone = `+250${phone}`;
  else if (/^250\d{9}$/.test(phone)) phone = `+${phone}`;
  if (!/^\+2507[2389]\d{7}$/.test(phone)) return fail('Enter a Rwanda login phone number.');
  return phone;
}

/** Prepare a preview only. It does not create a request, retain data, or send it. */
export function prepareBuriApproval(directory: BuriDirectory, principalId: string, input: BuriApprovalDraftInput): BuriApprovalDraft {
  if (!directory.configured) return fail('The group needs to be prepared before reviewing access.');
  if (typeof input.phone !== 'string' || typeof input.active !== 'boolean') return fail('Check the requested access.');
  const team = directory.team.find(operator => operator.principalId === principalId);
  const existing = directory.approvals.find(approval => approval.operator.principalId === principalId);
  const operator = team ?? existing?.operator;
  if (!operator || !existing && !team) return fail('Select a current Collect account.');
  if (input.active && !team) return fail('An active Collect account is required to enable access.');
  if (!existing && !input.active) return fail('A new approval must be enabled.');
  if (input.role !== 'staff' && input.role !== 'admin') return fail('Choose a BuriMunsi role.');
  if (existing && existing.role !== input.role) return fail('The role of an existing approval cannot be changed.');
  if (input.role === 'admin' && operator.role === 'staff') return fail('An administrator Collect account is required for administrator access.');
  if (!validOperatorCapabilities(input.role, input.capabilities)) return fail('Choose the permitted access for this role.');
  const expectedVersion = existing?.version ?? 0;
  if (!Number.isSafeInteger(expectedVersion) || expectedVersion < 0 || expectedVersion >= Number.MAX_SAFE_INTEGER) return fail('The current approval version could not be confirmed.');
  return {collectionId: directory.collectionId, operator, phone: loginPhone(input.phone), role: input.role, capabilities: [...input.capabilities].sort(), active: input.active, expectedVersion};
}
