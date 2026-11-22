import {isId, isObject, isSafeCount} from './contracts';
import {invalidJournal, type JournalCreateIntent, type JournalEditIntent} from './legacyJournalInputs';
import type {AdminRequest} from './types';

const PAGE_SIZE = 100;
const MAX_LINKED_RECORDS = 10000;
export interface JournalChoice {id: string; label: string; version: number}

export function parseJournalChoices(data: Record<string, unknown>): JournalChoice[] {
  if (data.contract_version !== undefined || data.model !== undefined ||
      Object.keys(data).length !== 1 || !Array.isArray(data.rows) || data.rows.length > PAGE_SIZE) return invalidJournal();
  const seen = new Set<string>();
  return data.rows.map(row => {
    if (!isObject(row) || !isId(row.id) || seen.has(row.id) || typeof row.label !== 'string' || !row.label.trim() ||
        row.label.length > 300 || !isSafeCount(row.version) || row.version < 1) return invalidJournal();
    seen.add(row.id);
    return {id: row.id, label: row.label, version: row.version};
  });
}

function detail(data: Record<string, unknown>, type: string, id: string, actor: string): Record<string, unknown> {
  if (data.contract_version !== undefined || data.model !== undefined || data.resource_type !== type || data.current_actor_id !== actor ||
      data.can_manage !== true || !isObject(data.resource) || data.resource.id !== id) return invalidJournal();
  return data.resource;
}

function relatedPage(data: Record<string, unknown>, name: string, offset: number) {
  if (!isObject(data.related) || Object.keys(data.related).length !== 1 || !Array.isArray(data.related[name]) ||
      !isObject(data.related_pages) || Object.keys(data.related_pages).length !== 1 || !isObject(data.related_pages[name])) return invalidJournal();
  const rows: unknown[] = data.related[name], page = data.related_pages[name];
  if (!isSafeCount(page.total) || page.limit !== PAGE_SIZE || page.offset !== offset ||
      rows.length !== Math.max(0, Math.min(PAGE_SIZE, page.total - offset)) ||
      page.next_offset !== (offset + rows.length < page.total ? offset + rows.length : null) ||
      rows.some(row => !isObject(row)) || data.related_truncated !== (page.total > rows.length)) return invalidJournal();
  return {rows: rows as Record<string, unknown>[], total: page.total, next: page.next_offset as number | null};
}

async function readRelated(request: AdminRequest, resource: 'transactions' | 'journals', id: string, actor: string, relation: string, offset: number) {
  const query = new URLSearchParams({relation, limit: String(PAGE_SIZE), offset: String(offset)});
  const data = await request(`operations/${resource}/${id}?${query}`);
  return {record: detail(data, resource, id, actor), page: relatedPage(data, relation, offset)};
}

export async function readActiveJournalGroup(request: AdminRequest, id: string, actor: string): Promise<JournalChoice> {
  const group = detail(await request(`operations/groups/${id}`), 'groups', id, actor);
  if (group.status !== 'active' || group.currency !== 'RWF' || group.country_code !== 'RW' ||
      typeof group.title !== 'string' || !group.title.trim() || !isSafeCount(group.version) || group.version < 1) return invalidJournal();
  return {id, label: group.title, version: group.version};
}

async function getAccount(request: AdminRequest, id: string, groupId: string, actor: string) {
  const account = detail(await request(`operations/accounts/${id}`), 'accounts', id, actor);
  if (account.group_id !== groupId || account.currency !== 'RWF' || (account.status !== 'active' && account.status !== 'closed') ||
      !isSafeCount(account.version) || account.version < 1 || typeof account.code !== 'string' || !account.code.trim() || account.code.length > 40 ||
      typeof account.name !== 'string' || account.name.trim().length < 2 || account.name.length > 120) return invalidJournal();
  return {id, code: account.code, name: account.name, status: account.status, version: account.version};
}

type JournalAccount = Awaited<ReturnType<typeof getAccount>>;

async function readAccounts(request: AdminRequest, accountIds: string[], groupId: string, actor: string, requireActive: boolean) {
  const accounts = await Promise.all([...new Set(accountIds)].map(id => getAccount(request, id, groupId, actor)));
  if (requireActive && accounts.some(account => account.status !== 'active')) return invalidJournal();
  return accounts;
}

export async function readLinkedJournalAllocation(request: AdminRequest, transactionId: string, allocationId: string, actor: string) {
  if (!isId(transactionId) || !isId(allocationId)) return invalidJournal();
  let transaction: {groupId: string; version: number; amount: number} | null = null;
  let found: {amount: number; memberId: string | null} | null = null;
  const counts = {allocations: -1, journals: -1};
  for (const relation of ['allocations', 'journals'] as const) {
    let offset = 0, total: number | null = null;
    const seen = new Set<string>();
    do {
      const {record, page} = await readRelated(request, 'transactions', transactionId, actor, relation, offset);
      if (!isId(record.group_id) || record.verification_status !== 'confirmation_recorded' || !isSafeCount(record.version) || record.version < 1 ||
          !isSafeCount(record.amount_rwf) || record.amount_rwf < 1 ||
          (transaction && (record.group_id !== transaction.groupId || record.version !== transaction.version || record.amount_rwf !== transaction.amount)) ||
          page.total > MAX_LINKED_RECORDS || (total !== null && total !== page.total)) return invalidJournal();
      transaction = {groupId: record.group_id, version: record.version, amount: record.amount_rwf};
      total = page.total;
      for (const row of page.rows) {
        if (!isId(row.id) || seen.has(row.id)) return invalidJournal();
        seen.add(row.id);
        if (relation === 'allocations' && row.id === allocationId) {
          if (found || row.transaction_id !== transactionId || row.group_id !== transaction.groupId || !isSafeCount(row.amount_rwf) ||
              row.amount_rwf < 1 || row.amount_rwf > transaction.amount || !(row.member_user_id === null || isId(row.member_user_id))) return invalidJournal();
          found = {amount: row.amount_rwf, memberId: row.member_user_id};
        }
        if (relation === 'journals') {
          if (!(row.allocation_id === null || isId(row.allocation_id)) || !['draft', 'posted'].includes(String(row.status)) ||
              !isSafeCount(row.version) || row.version < 1) return invalidJournal();
          if (row.allocation_id === allocationId) throw new Error('Allocation already has a journal');
        }
      }
      if (page.next === null) break;
      offset = page.next;
    } while (offset < MAX_LINKED_RECORDS);
    counts[relation] = total ?? -1;
  }
  if (!found || !transaction || counts.allocations < 0 || counts.journals < 0) return invalidJournal();
  return {transactionId, allocationId, groupId: transaction.groupId, transactionVersion: transaction.version,
    amount: found.amount, memberId: found.memberId, allocationCount: counts.allocations, journalCount: counts.journals};
}

export async function readJournalCreateSource(request: AdminRequest, body: JournalCreateIntent, actor: string, transactionId?: string, allocationId?: string) {
  let linked: Awaited<ReturnType<typeof readLinkedJournalAllocation>> | null = null;
  if (body.allocation_id != null) {
    if (!isId(transactionId) || body.allocation_id !== allocationId) return invalidJournal();
    linked = await readLinkedJournalAllocation(request, transactionId, body.allocation_id, actor);
    if (linked.groupId !== body.group_id || body.entries.reduce((sum, line) => sum + BigInt(line.debit_rwf), 0n) !== BigInt(linked.amount)) return invalidJournal();
  } else if (transactionId !== undefined || allocationId !== undefined) return invalidJournal();
  const group = await readActiveJournalGroup(request, body.group_id, actor);
  const accounts = await readAccounts(request, body.entries.map(line => line.account_id), group.id, actor, true);
  return {groupId: group.id, groupTitle: group.label, groupVersion: group.version, accounts, linked};
}

async function readExistingAllocation(request: AdminRequest, transactionId: string, allocationId: string, groupId: string, actor: string, amount: number) {
  let offset = 0, transactionVersion: number | null = null, allocationCount: number | null = null;
  let found = false, memberId: string | null = null;
  do {
    const {record, page} = await readRelated(request, 'transactions', transactionId, actor, 'allocations', offset);
    if (record.group_id !== groupId || record.verification_status !== 'confirmation_recorded' || !isSafeCount(record.version) || record.version < 1 ||
        (transactionVersion !== null && record.version !== transactionVersion) || (allocationCount !== null && page.total !== allocationCount) ||
        page.total > MAX_LINKED_RECORDS) return invalidJournal();
    transactionVersion = record.version;
    allocationCount = page.total;
    for (const row of page.rows) {
      if (row.id !== allocationId) continue;
      if (found || row.transaction_id !== transactionId || row.group_id !== groupId || row.amount_rwf !== amount ||
          !(row.member_user_id === null || isId(row.member_user_id))) return invalidJournal();
      found = true;
      memberId = row.member_user_id;
    }
    if (page.next === null) break;
    offset = page.next;
  } while (offset <= MAX_LINKED_RECORDS);
  if (!found) return invalidJournal();
  return {memberId, transactionVersion, allocationCount};
}

export async function readExistingJournal(request: AdminRequest, id: string, actor: string, canReadPayments: boolean, mode: 'edit' | 'post', expected?: number) {
  const {record, page} = await readRelated(request, 'journals', id, actor, 'entries', 0);
  const posting = mode === 'post';
  if (page.total < 2 || page.total > PAGE_SIZE || page.next !== null || !isId(record.group_id) || record.status !== 'draft' || record.currency !== 'RWF' ||
      !isSafeCount(record.version) || record.version < 1 || record.version >= Number.MAX_SAFE_INTEGER || (expected !== undefined && expected !== record.version) ||
      typeof record.description !== 'string' || record.description.trim().length < 3 || record.description.length > 1000 ||
      !isId(record.created_by_admin_id) || !(record.edited_by_admin_id === null || isId(record.edited_by_admin_id)) ||
      (posting && (record.created_by_admin_id === actor || record.edited_by_admin_id === null || record.edited_by_admin_id === actor)) ||
      !(record.allocation_id === null || isId(record.allocation_id)) || !(record.transaction_id === null || isId(record.transaction_id)) ||
      ((record.allocation_id === null) !== (record.transaction_id === null))) return invalidJournal();

  const ids = new Set<string>();
  let debit = 0n, credit = 0n;
  const lines = page.rows.map((row, index) => {
    if (!isId(row.id) || ids.has(row.id) || row.journal_id !== id || row.group_id !== record.group_id || !isId(row.account_id) ||
        row.line_number !== index + 1 || !isSafeCount(row.debit_rwf) || !isSafeCount(row.credit_rwf) ||
        ((row.debit_rwf === 0) === (row.credit_rwf === 0)) || typeof row.description !== 'string' || row.description.length > 500 ||
        typeof row.account_code !== 'string' || !row.account_code.trim() || row.account_code.length > 40 ||
        typeof row.account_name !== 'string' || row.account_name.trim().length < 2 || row.account_name.length > 120) return invalidJournal();
    ids.add(row.id);
    debit += BigInt(row.debit_rwf);
    credit += BigInt(row.credit_rwf);
    return {id: row.id, accountId: row.account_id, accountCode: row.account_code, accountName: row.account_name,
      debit: row.debit_rwf, credit: row.credit_rwf, description: row.description};
  });
  if (debit === 0n || debit !== credit || debit > BigInt(Number.MAX_SAFE_INTEGER)) return invalidJournal();

  const group = await readActiveJournalGroup(request, record.group_id, actor);
  const accounts = await readAccounts(request, lines.map(line => line.accountId), group.id, actor, posting);
  const byId = new Map(accounts.map(account => [account.id, account]));
  if (lines.some(line => {
    const account = byId.get(line.accountId);
    return account?.code !== line.accountCode || account.name !== line.accountName;
  })) return invalidJournal();

  let allocation: {memberId: string | null; transactionVersion: number | null; allocationCount: number | null} =
    {memberId: null, transactionVersion: null, allocationCount: null};
  if (record.allocation_id !== null && record.transaction_id !== null) {
    if (!canReadPayments) throw new Error('Payment read access is required');
    allocation = await readExistingAllocation(request, record.transaction_id, record.allocation_id, group.id, actor, Number(debit));
  }
  return {id, groupId: group.id, groupTitle: group.label, groupVersion: group.version, version: record.version, description: record.description,
    createdBy: record.created_by_admin_id, editedBy: record.edited_by_admin_id, allocationId: record.allocation_id,
    transactionId: record.transaction_id, ...allocation, total: Number(debit), lines, accounts};
}

export interface JournalEditReview {
  draft: Awaited<ReturnType<typeof readExistingJournal>>;
  accounts: JournalAccount[];
}

export async function readJournalEditSource(request: AdminRequest, id: string, actor: string, canReadPayments: boolean, body: JournalEditIntent): Promise<JournalEditReview> {
  const draft = await readExistingJournal(request, id, actor, canReadPayments, 'edit', body.expected_version);
  if (draft.allocationId !== null && body.entries.reduce((sum, line) => sum + BigInt(line.debit_rwf), 0n) !== BigInt(draft.total)) {
    throw new Error('Allocation amount changed');
  }
  const accounts = await readAccounts(request, body.entries.map(line => line.account_id), draft.groupId, actor, true);
  return {draft, accounts};
}
