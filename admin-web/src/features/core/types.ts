export type AdminRequest = (
  path: string,
  options?: {
    method?: 'GET' | 'POST' | 'PATCH';
    body?: Record<string, unknown>;
    authenticated?: boolean;
    idempotencyKey?: string;
    reviewReason?: string;
    expectedStatus?: number;
    signal?: AbortSignal;
  },
) => Promise<Record<string, unknown>>;

export type FinancialModel = 'canonical_evidence_ledger' | 'transaction_journals';
export type CoreArea = 'groups' | 'users' | 'members' | 'payees' | 'transactions' | 'ledgers';

export interface FeatureAccess {
  request: AdminRequest;
  permissions: readonly string[];
  actorId: string;
  principalId: string | null;
  role: 'owner' | 'admin' | 'staff';
  /** Changes whenever the authenticated session or authority grants change. */
  authorityKey: string;
  financialModel: FinancialModel;
  navigate: (path: string) => void;
}

export type DataRow = Record<string, unknown> & {
  id: string;
  title: string;
  subtitle: string;
  status: string;
  amount: string;
  created_at: string;
};

export interface CorePage {
  rows: DataRow[];
  total: number;
  model: FinancialModel;
}

export const CORE_PERMISSIONS: Record<CoreArea, string> = {
  groups: 'collections.read', users: 'users.read', members: 'users.read',
  payees: 'receivers.read', transactions: 'payments.read', ledgers: 'ledger.read',
};

export const AREA_TITLES: Record<CoreArea, string> = {
  groups: 'Groups', users: 'Users', members: 'Members', payees: 'Payees',
  transactions: 'Transactions', ledgers: 'Ledgers',
};
