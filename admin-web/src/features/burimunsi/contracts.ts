/* eslint-disable no-control-regex -- Reject controls in untrusted directory fields. */
type Row = Record<string, unknown>;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/, GROUP = /^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$/;
const CAPABILITIES = ['records.read', 'members.enroll', 'payments.allocate', 'staff.manage', 'sms.read', 'gateway.manage'] as const;
export interface BuriScope {id: string; title: string; version: number; enabled: boolean; paired: boolean; receivingAccountId: string; receiverKeyId: string | null; receiverInstallationId: string | null; replacementPending: boolean;}
export interface BuriSharedOperator {adminId: string; principalId: string; email: string; displayName: string; role: 'owner' | 'admin' | 'staff';}
export interface BuriApproval {operator: BuriSharedOperator; phone: string; role: 'admin' | 'staff'; capabilities: string[]; active: boolean; version: number; sharedStatus: 'active' | 'invited' | 'revoked';}
export interface BuriDirectory {collectionId: string; configured: boolean; team: BuriSharedOperator[]; approvals: BuriApproval[]; approvalContract?: 2;}
export interface BuriNativeAccount {principalId: string; accountId: string | null; phone: string; name: string; role: 'admin' | 'staff'; capabilities: string[]; approvalVersion: number; version: number; credentialVersion: number; approved: boolean; active: boolean; removed: boolean;}
export interface BuriNativeGrant {id: string; accountId: string | null; installationId: string; profile: 'staff' | 'internal_receiver'; version: number; active: boolean;}
export interface BuriProvisioning {collectionId: string; configured: boolean; scopeVersion: number | null; scopeEnabled: boolean; accounts: BuriNativeAccount[]; grants: BuriNativeGrant[]; provisioningContract?: 2;}
function invalid(): never {throw new Error('BuriMunsi access could not be verified.');}
function obj(value: unknown): Row {return value !== null && typeof value === 'object' && !Array.isArray(value) ? value as Row : invalid();}
function exact(value: Row, keys: string[]) {if (Object.keys(value).length !== keys.length || keys.some(key => !Object.hasOwn(value, key))) invalid();}
function string(value: unknown, max = 254, min = 0): string {return typeof value === 'string' && value.length >= min && value.length <= max && !/[\x00-\x1f\x7f-\x9f]/.test(value) ? value : invalid();}
function id(value: unknown): string {return typeof value === 'string' && UUID.test(value) ? value : invalid();}
export function isBuriUuid(value: unknown): value is string {return typeof value === 'string' && UUID.test(value);}
// The operator directory returns existing text keys, including legacy Admin IDs.
// Preserve them exactly; UUID-only checks still apply to native/provisioning IDs.
function operatorId(value: unknown): string {return string(value, 254, 1);}
function group(value: unknown): string {return typeof value === 'string' && GROUP.test(value) ? value : invalid();}
function integer(value: unknown, min = 1): number {return typeof value === 'number' && Number.isSafeInteger(value) && value >= min ? value : invalid();}
function boolean(value: unknown): boolean {return typeof value === 'boolean' ? value : invalid();}
function values(value: unknown): unknown[] {return Array.isArray(value) && value.length <= 500 ? value : invalid();}
function unique<T>(rows: T[], key: (row: T) => string) {if (new Set(rows.map(key)).size !== rows.length) invalid();}
function role(value: unknown): 'admin' | 'staff' {return value === 'admin' || value === 'staff' ? value : invalid();}
function sharedRole(value: unknown): BuriSharedOperator['role'] {return value === 'owner' || value === 'admin' || value === 'staff' ? value : invalid();}
function phone(value: unknown): string {return typeof value === 'string' && /^\+2507[2389]\d{7}$/.test(value) ? value : invalid();}
function capabilities(value: unknown, r: 'admin' | 'staff'): string[] {
  if (!Array.isArray(value) || value.length < 1 || value.length > 6 || value.some(item => typeof item !== 'string' || !CAPABILITIES.includes(item as typeof CAPABILITIES[number])) ||
      !value.includes('records.read') || new Set(value).size !== value.length || r === 'staff' && value.some(item => !['records.read', 'members.enroll', 'payments.allocate'].includes(String(item)))) invalid();
  return [...value] as string[];
}
function shared(value: Row, roleField = 'role'): BuriSharedOperator {return {adminId: operatorId(value.adminId), principalId: operatorId(value.principalId), email: string(value.email), displayName: string(value.displayName, 120), role: sharedRole(value[roleField])};}

export function parseBuriScopes(input: unknown): BuriScope[] {
  const value = obj(input); exact(value, ['contractVersion', 'collections', 'accounts', 'scopes', 'installations']); if (value.contractVersion !== 1) invalid();
  const groups = values(value.collections).map(item => {
    const row = obj(item), groupId = group(row.id);
    const title = typeof row.title === 'string' ? row.title.replace(/[\x00-\x1f\x7f-\x9f]/g, ' ').trim() : invalid();
    // SQL permits empty and unusually long legacy titles; normal writes allow
    // tabs/newlines. Keep the exact stable ID and use a safe display label.
    return {id: groupId, title: !title.trim() ? `Group ${groupId}` : title.length > 160 ? `${title.slice(0, 157)}… (${groupId})` : title, version: integer(row.version)};
  });
  unique(groups, row => row.id); values(value.accounts); const installations = values(value.installations); if (installations.length) invalid();
  const scopes = values(value.scopes).map(item => {
    const row = obj(item), collection = group(row.collectionId), title = groups.find(entry => entry.id === collection)?.title;
    const receivingAccountId = group(row.receivingAccountId), enabled = boolean(row.enabled), paired = boolean(row.paired), version = integer(row.version);
    const receiverKeyId = row.receiverKeyId === null ? null : group(row.receiverKeyId), receiverInstallationId = row.receiverInstallationId === null ? null : id(row.receiverInstallationId);
    if (row.pendingReplacement !== null) {
      const pending = obj(row.pendingReplacement); exact(pending, ['handoffId', 'targetInstallationId', 'targetGrantId', 'targetGrantVersion', 'targetCustodianAccountId', 'expectedScopeVersion', 'expectedBindingId', 'expectedBindingVersion', 'expectedReceiverKeyId', 'expiresAt', 'phase', 'subscriptionId']);
      for (const key of ['handoffId', 'targetInstallationId', 'targetGrantId', 'targetCustodianAccountId']) id(pending[key]);
      for (const key of ['targetGrantVersion', 'expectedScopeVersion', 'expectedBindingVersion', 'expiresAt']) integer(pending[key]);
      group(pending.expectedBindingId); group(pending.expectedReceiverKeyId);
      if (!['prepared', 'retired'].includes(String(pending.phase)) || integer(pending.subscriptionId, 0) >= 2147483647) invalid();
    }
    return {id: collection, title: title ?? '', receivingAccountId, enabled, paired, version, receiverKeyId, receiverInstallationId, replacementPending: row.pendingReplacement !== null};
  });
  unique(scopes, row => row.id); return scopes.filter(scope => scope.title !== '');
}
export function parseBuriDirectory(input: unknown, collectionId: string, acceptApprovalContract = false): BuriDirectory {
  const value = obj(input), guarded = acceptApprovalContract && Object.hasOwn(value, 'approvalContract');
  exact(value, ['contractVersion', 'collectionId', 'configured', 'team', 'approvals', ...(guarded ? ['approvalContract'] : [])]);
  if (value.contractVersion !== 1 || value.collectionId !== group(collectionId) || guarded && value.approvalContract !== 2) invalid();
  const team = values(value.team).map(item => {const row = obj(item); exact(row, ['adminId', 'principalId', 'email', 'displayName', 'role']); return shared(row);});
  const approvals = values(value.approvals).map(item => {
    const row = obj(item); exact(row, ['adminId', 'principalId', 'email', 'displayName', 'sharedRole', 'sharedStatus', 'phone', 'role', 'capabilities', 'active', 'version']);
    const r = role(row.role); if (!['active', 'invited', 'revoked'].includes(String(row.sharedStatus))) invalid();
    return {operator: shared(row, 'sharedRole'), phone: phone(row.phone), role: r, capabilities: capabilities(row.capabilities, r), active: boolean(row.active), version: integer(row.version), sharedStatus: row.sharedStatus as BuriApproval['sharedStatus']};
  });
  unique(team, row => row.adminId); unique(team, row => row.principalId); unique(approvals, row => row.operator.adminId); unique(approvals, row => row.operator.principalId); unique(approvals, row => row.phone);
  const teamByPrincipal = new Map(team.map(person => [person.principalId, person]));
  const teamByAdmin = new Map(team.map(person => [person.adminId, person]));
  for (const {operator} of approvals) {
    const principal = teamByPrincipal.get(operator.principalId), admin = teamByAdmin.get(operator.adminId);
    if ((principal || admin) && (principal !== admin || JSON.stringify(principal) !== JSON.stringify(operator))) invalid();
  }
  return {collectionId, configured: boolean(value.configured), team, approvals, ...(guarded ? {approvalContract: 2 as const} : {})};
}

export function directoryOperatorRows(directory: BuriDirectory): Array<{operator: BuriSharedOperator; approval?: BuriApproval}> {
  const approvals = new Map(directory.approvals.map(approval => [approval.operator.principalId, approval]));
  const operators = new Map([...directory.approvals.map(({operator}) => [operator.principalId, operator] as const),
    ...directory.team.map(operator => [operator.principalId, operator] as const)]);
  return [...operators.values()].map(operator => ({operator, approval: approvals.get(operator.principalId)}));
}
export function parseBuriProvisioning(input: unknown, collectionId: string, negotiate = false): BuriProvisioning {
  const value = obj(input), guarded = negotiate && Object.hasOwn(value, 'provisioningContract');
  exact(value, ['contractVersion', 'collectionId', 'configured', 'scopeVersion', 'scopeEnabled', 'accounts', 'grants', ...(guarded ? ['provisioningContract'] : [])]);
  if (value.contractVersion !== 1 || value.collectionId !== group(collectionId) ||
      guarded && (value.provisioningContract !== 2 || value.configured !== true)) invalid();
  const configured = boolean(value.configured), scopeVersion = value.scopeVersion === null ? null : integer(value.scopeVersion), scopeEnabled = boolean(value.scopeEnabled); if (configured && scopeVersion === null) invalid();
  const accounts = values(value.accounts).map(item => {
    const row = obj(item); exact(row, ['principalId', 'accountId', 'phone', 'name', 'role', 'capabilities', 'approvalVersion', 'version', 'credentialVersion', 'approved', 'active', 'removed']);
    const r = role(row.role), accountId = row.accountId === null ? null : id(row.accountId), version = integer(row.version, 0), credentialVersion = integer(row.credentialVersion, 0);
    if ((accountId === null) !== (version === 0) || (accountId === null) !== (credentialVersion === 0)) invalid();
    return {principalId: id(row.principalId), accountId, phone: phone(row.phone), name: string(row.name, 100), role: r, capabilities: capabilities(row.capabilities, r), approvalVersion: integer(row.approvalVersion), version, credentialVersion, approved: boolean(row.approved), active: boolean(row.active), removed: boolean(row.removed)};
  });
  const grants = values(value.grants).map(item => {
    const row = obj(item); exact(row, ['id', 'accountId', 'installationId', 'profile', 'version', 'active']);
    if (row.profile !== 'staff' && row.profile !== 'internal_receiver') invalid();
    return {id: id(row.id), accountId: row.accountId === null ? null : id(row.accountId), installationId: id(row.installationId), profile: row.profile as BuriNativeGrant['profile'], version: integer(row.version), active: boolean(row.active)};
  });
  unique(accounts, row => row.principalId); unique(accounts.filter(row => row.accountId !== null), row => row.accountId!); unique(grants, row => row.id); unique(grants, row => row.installationId);
  return {collectionId, configured, scopeVersion, scopeEnabled, accounts, grants, ...(guarded ? {provisioningContract: 2 as const} : {})};
}
