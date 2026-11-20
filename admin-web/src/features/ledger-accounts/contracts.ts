/* eslint-disable no-control-regex -- Reject control characters in account fields. */
import { z } from 'zod';

const uuid = z.string().regex(/^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/);
const safeInt = z.number().int().min(0).max(Number.MAX_SAFE_INTEGER);
const text = (minimum: number, maximum: number) => z.string().min(minimum).max(maximum).refine((value) => value.trim().length >= minimum && !/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/.test(value));
const account = z.object({id: uuid, group_id: uuid, code: z.string().min(1).max(40).regex(/^[A-Za-z0-9_.-]+$/), name: text(2, 120),
  account_type: z.enum(['asset', 'liability', 'equity', 'income', 'expense']), normal_side: z.enum(['debit', 'credit']),
  currency: z.literal('RWF'), status: z.enum(['active', 'closed']), created_by_admin_id: uuid, created_at: safeInt.min(1), version: safeInt.min(1)}).strict();
export type LedgerAccount = z.infer<typeof account>;
export interface LedgerAccountDetail {account: LedgerAccount; canManage: boolean;}
const detail = z.object({resource_type: z.literal('accounts'), resource: account, current_actor_id: uuid, can_manage: z.boolean(),
  related: z.object({}).strict(), related_pages: z.object({}).strict().optional(), related_truncated: z.literal(false)}).strict();
export function parseLedgerAccountDetail(input: unknown, id: string, actor: string, role: string): LedgerAccountDetail {
  const value = detail.parse(input);
  if (value.resource.id !== id || value.current_actor_id !== actor || role === 'staff' && value.can_manage) throw new Error('The ledger account could not be verified.');
  return {account: value.resource, canManage: value.can_manage};
}
export function isLedgerId(id: string | undefined): id is string {return uuid.safeParse(id).success;}
