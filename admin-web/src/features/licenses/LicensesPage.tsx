import {useState} from 'react';
import notices from '../../generated/notices.json';
import {Card, EmptyState, Field, PageHeader} from '../../ui';
import './licenses.css';

/** Offline notices generated from the locked Admin dependencies and font asset. */
export function LicensesPage() {
  const [query, setQuery] = useState('');
  const items = [...notices.packages, ...notices.assets].filter((item) =>
    item.name.toLocaleLowerCase().includes(query.trim().toLocaleLowerCase()));
  return <><PageHeader title="Open-source licenses" subtitle="Bundled software packages and their offline notices." />
    <Card className="licenses-card"><Field label="Search packages" htmlFor="license-search">
      <input id="license-search" className="admin-input" type="search" value={query} onChange={(event) => setQuery(event.target.value)} />
    </Field>
      {items.length ? <div className="licenses-list">{items.map((item) => <details key={item.name}>
        <summary><strong>{item.name}</strong><span>{'version' in item && typeof item.version === 'string' ? item.version : 'Asset'} · {item.license}</span></summary>
        {item.notices.map((notice) => <div key={notice.file}><h2>{notice.file}</h2><pre>{notice.text}</pre></div>)}
      </details>)}</div> : <EmptyState title="No packages found" description="Try a different search." />}
    </Card>
  </>;
}
