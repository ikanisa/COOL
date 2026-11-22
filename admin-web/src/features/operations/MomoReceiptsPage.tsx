import {useState} from 'react';
import {useSession} from '../../session/SessionProvider';
import {Button, ErrorState, PageHeader} from '../../ui';
import {MomoIncomingSms} from './MomoIncomingSms';
import {MomoTransactionList} from './MomoTransactionList';
import './operations.css';

export function MomoReceiptsPage({allowActions = false, allowRecovery = true, initialView = 'incoming', transactionsOnly = false}: {allowActions?: boolean; allowRecovery?: boolean; initialView?: 'incoming' | 'transactions'; transactionsOnly?: boolean}) {
  const session = useSession(), permissions = session.user?.permissions ?? [];
  const canSms = session.status === 'authenticated' && permissions.includes('sms.read'), canPayments = session.status === 'authenticated' && permissions.includes('payments.read');
  const [view, setView] = useState<'incoming' | 'transactions'>(initialView);
  const actual = transactionsOnly ? 'transactions' : view === 'incoming' && canSms || !canPayments ? 'incoming' : 'transactions';
  const available = transactionsOnly ? canPayments : canSms || canPayments;
  return <><PageHeader eyebrow="Collect Admin / Operations" title={transactionsOnly ? 'MoMo transactions' : 'MoMo receipts'} subtitle={actual === 'incoming' ? 'Mobile-money SMS shared by app users.' : 'Validated payments and their allocation status.'} />
    {!available ? <ErrorState title="Access unavailable" message="Your current account cannot open these records." /> : <>{!transactionsOnly && <div className="momo-views" aria-label="MoMo receipt views">{canSms && <Button variant={actual === 'incoming' ? 'primary' : 'secondary'} aria-pressed={actual === 'incoming'} onClick={() => setView('incoming')}>Incoming SMS</Button>}{canPayments && <Button variant={actual === 'transactions' ? 'primary' : 'secondary'} aria-pressed={actual === 'transactions'} onClick={() => setView('transactions')}>Transactions</Button>}</div>}{actual === 'incoming' ? <MomoIncomingSms key={session.epoch} /> : <MomoTransactionList key={session.epoch} allowActions={allowActions} allowRecovery={allowRecovery} />}</>}
  </>;
}
