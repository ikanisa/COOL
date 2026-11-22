import {Card, StatusBadge} from '../../ui';
import {directoryOperatorRows, type BuriDirectory, type BuriProvisioning} from './contracts';

export function BuriDirectoryView({directory, provisioning, provisioningError}: {
  directory: BuriDirectory;
  provisioning: BuriProvisioning | null;
  provisioningError: boolean;
}) {
  const operators = directoryOperatorRows(directory);
  return <>
    <Card><div className="core-detail">
      <h2>Collect operators</h2>
      {!directory.configured && <p>The BuriMunsi group and receiving account need to be configured before approving access.</p>}
      {operators.length === 0 ? <p>No Collect accounts or approvals are recorded for this group.</p> :
        <div className="admin-table-wrap" role="region" aria-label="BuriMunsi operator records" tabIndex={0}>
          <table className="admin-table">
            <thead><tr><th scope="col">Account</th><th scope="col">Collect role</th><th scope="col">BuriMunsi access</th><th scope="col">Capabilities</th></tr></thead>
            <tbody>{operators.map(({operator, approval}) => <tr key={operator.principalId}>
              <td>{operator.displayName || operator.email}<br />{operator.email}</td>
              <td>{operator.role}</td>
              <td>{approval ? <>
                <StatusBadge tone={approval.active ? 'success' : 'warning'}>{approval.active ? 'Recorded enabled' : 'Recorded disabled'}</StatusBadge>
                <br />{approval.role} · {approval.phone}<br />Collect status: {approval.sharedStatus}
              </> : 'No approval recorded'}</td>
              <td>{approval ? approval.capabilities.join(', ') : '—'}</td>
            </tr>)}</tbody>
          </table>
        </div>}
    </div></Card>
    <Card><div className="core-detail">
      <h2>Native app access</h2>
      {provisioningError ? <p role="alert">Native setup could not be verified. Refresh before continuing.</p> : provisioning && <>
        <p>Recorded scope: {provisioning.scopeEnabled ? 'enabled' : 'not enabled'} · {provisioning.configured ? 'configured' : 'not configured'}.</p>
        {provisioning.accounts.length === 0 ? <p>No approved native accounts are recorded.</p> : <>
          <h3>Accounts</h3>
          <ul>{provisioning.accounts.map(account => <li key={account.principalId}>{account.name || account.phone} · {account.role} · {account.approved ? 'approval current' : 'approval not current'} · {account.active && !account.removed ? 'recorded active' : 'not active'}</li>)}</ul>
        </>}
        {provisioning.grants.length === 0 ? <p>No installation grants are recorded.</p> : <>
          <h3>Installation grants</h3>
          <ul>{provisioning.grants.map(grant => <li key={grant.id}>{grant.installationId} · {grant.profile} · {grant.active ? 'recorded active' : 'recorded inactive'} · version {grant.version}</li>)}</ul>
        </>}
        <p>A recorded grant does not confirm physical device possession, carrier delivery or payment settlement.</p>
      </>}
    </div></Card>
  </>;
}
