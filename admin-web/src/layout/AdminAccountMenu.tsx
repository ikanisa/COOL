import {useEffect, useRef, useState} from 'react';
import {Icon} from '../ui/Icon';
import {hasActiveFocusScope} from '../ui/useFocusScope';

export interface AdminShellIdentity {
  name: string;
  role?: string;
}

export function AdminAccountMenu({identity, onSignOut}: {identity: AdminShellIdentity; onSignOut?: () => void}) {
  const [open, setOpen] = useState(false);
  const container = useRef<HTMLDivElement>(null);
  const trigger = useRef<HTMLButtonElement>(null);
  useEffect(() => {
    if (!open) return;
    const outside = (event: PointerEvent) => {
      if (event.target instanceof Node && !container.current?.contains(event.target)) setOpen(false);
    };
    const escape = (event: KeyboardEvent) => {
      if (event.key !== 'Escape' || event.defaultPrevented || hasActiveFocusScope()) return;
      const restoreFocus = container.current?.contains(document.activeElement);
      setOpen(false);
      if (restoreFocus) trigger.current?.focus();
    };
    document.addEventListener('pointerdown', outside);
    document.addEventListener('keydown', escape);
    return () => {
      document.removeEventListener('pointerdown', outside);
      document.removeEventListener('keydown', escape);
    };
  }, [open]);

  return <div className="admin-profile" ref={container}>
    <button className="admin-profile-button" type="button" ref={trigger} aria-label={'Account: ' + identity.name}
      aria-expanded={open} onClick={() => setOpen(value => !value)}>
      <span className="admin-operator-role">{identity.role}</span>
      <span className="admin-avatar" aria-hidden="true">{identity.name.slice(0, 1).toLocaleUpperCase()}</span>
    </button>
    {open && <div className="admin-profile-menu">
      <strong>{identity.name}</strong>
      {identity.role && <span>{identity.role}</span>}
      {onSignOut && <button type="button" onClick={() => {setOpen(false); onSignOut();}}>
        <Icon name="logout" />Sign out
      </button>}
    </div>}
  </div>;
}
