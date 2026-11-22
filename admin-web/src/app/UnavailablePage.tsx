import {useNavigate} from 'react-router';
import {Button, ErrorState, PageHeader} from '../ui';

export function UnavailablePage({title}: {title: string}) {
  const go = useNavigate();
  return <><PageHeader title={title} /><ErrorState title="Workspace unavailable"
    message="This part of your workspace is unavailable." /><Button onClick={() => go('/admin')}>Go to overview</Button></>;
}
