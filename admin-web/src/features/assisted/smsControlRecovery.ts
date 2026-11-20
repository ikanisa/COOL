import type {PendingAttempt, PendingIdentity} from '../core/pendingAttempt';
import {custodyKey} from '../../custodyRealm';

export const MANAGEMENT_FAMILY = 'notification-management';
export const MANAGEMENT_PERMISSION = 'admin_users.manage';
export const MANAGEMENT_UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
export interface ManagementStoreContext {identity: PendingIdentity & {principalId: string}; isCurrent: () => boolean; storage?: Storage}
const running = new Set<string>();

/** Same owner/session/principal namespace as Flutter's management recovery. */
class ManagementStorage implements Storage {
  constructor(private readonly base: Storage, private readonly prefix: string, private readonly isCurrent: () => boolean) {}
  private guard() {if (!this.isCurrent()) throw new Error('The original session changed.');}
  get length() {return 0;}
  clear(): void {throw new Error('Unsupported recovery operation.');}
  key(): string | null {return null;}
  getItem(key: string): string | null {this.guard(); return this.base.getItem(`${this.prefix}.${key}`);}
  setItem(key: string, value: string): void {this.guard(); this.base.setItem(`${this.prefix}.${key}`, value);}
  removeItem(key: string): void {this.guard(); this.base.removeItem(`${this.prefix}.${key}`);}
}
export function managementStorage(context: ManagementStoreContext): Storage {
  const actor = context.identity;
  return new ManagementStorage(context.storage ?? sessionStorage, custodyKey(`collect.admin.notification-management.${actor.id}.${actor.sessionId}.${actor.principalId}`), context.isCurrent);
}
export function managementIdentity(context: ManagementStoreContext): PendingIdentity {return {...context.identity, permissions: [MANAGEMENT_PERMISSION]};}
export function withManagementLock<T>(context: ManagementStoreContext, work: () => Promise<T>): Promise<T> {
  const actor = context.identity, key = JSON.stringify([actor.id, actor.sessionId, actor.principalId]);
  if (running.has(key)) throw new Error('Wait for the current SMS controls request.');
  running.add(key); return work().finally(() => running.delete(key));
}
export function parseManagementPending(saved: PendingAttempt): PendingAttempt {
  const value = saved.intent, fields = Object.keys(value).sort().join(',');
  if (saved.family !== MANAGEMENT_FAMILY || saved.permission !== MANAGEMENT_PERMISSION || !MANAGEMENT_UUID.test(saved.request_key) || !['access', 'policy'].includes(String(value.action)) || typeof value.resource_id !== 'string' || !MANAGEMENT_UUID.test(value.resource_id) || saved.resource_id !== `${value.action}:${value.resource_id}`) throw new Error('The original SMS controls reference could not be verified.');
  if (value.action === 'policy' ? fields !== 'action,resource_id' : fields !== 'action,resource_id' && (fields !== 'action,expected_decision_revision,resource_id' || !Number.isSafeInteger(value.expected_decision_revision) || (value.expected_decision_revision as number) < 0 || (value.expected_decision_revision as number) >= Number.MAX_SAFE_INTEGER)) throw new Error('The original SMS controls reference could not be verified.');
  return saved;
}
