import type {KeyboardEvent, ReactNode, RefObject} from 'react';
import {Icon} from '../ui/Icon';
import collectLogo from '../ui/assets/collect-logo.png';

export interface AdminNavItem {
  label: string;
  path: string;
  section?: string;
  icon?: string;
}

export function findCurrentSection(navigation: readonly AdminNavItem[], pathname: string): AdminNavItem | undefined {
  let current: AdminNavItem | undefined;
  for (const item of navigation) {
    const matches = item.path === pathname || (item.path !== '/admin' && pathname.startsWith(item.path + '/'));
    if (matches && (!current || item.path.length > current.path.length)) current = item;
  }
  return current;
}

interface AdminNavigationProps {
  sidebar: RefObject<HTMLElement | null>;
  sections: RefObject<HTMLElement | null>;
  groups: ReadonlyMap<string, readonly AdminNavItem[]>;
  pathname: string;
  selected?: AdminNavItem;
  status?: ReactNode;
  onClose: () => void;
  onSectionKeyDown: (event: KeyboardEvent<HTMLElement>) => void;
}

export function AdminNavigation({sidebar, sections, groups, pathname, selected, status, onClose, onSectionKeyDown}: AdminNavigationProps) {
  return <aside ref={sidebar} className="admin-sidebar" id="admin-navigation" aria-label="Primary admin navigation" tabIndex={-1}>
    <div className="admin-brand">
      <img className="admin-brand-mark" src={collectLogo} alt="" />
      <div className="admin-brand-copy">
        <span className="admin-brand-title">Collect</span>
        <span className="admin-brand-caption">Admin workspace</span>
      </div>
      <button type="button" className="admin-icon-button admin-sidebar-close" onClick={onClose} aria-label="Close navigation">
        <Icon name="close" />
      </button>
    </div>
    <nav ref={sections} className="admin-sidebar-scroll" aria-label="Admin sections" onKeyDown={onSectionKeyDown}>
      {[...groups].map(([section, items]) => <div className="admin-nav-group" key={section}>
        <div className="admin-nav-heading">{section}</div>
        {items.map((item) => {
          const active = selected?.path === item.path;
          return <a key={item.path} className={active ? 'admin-nav-link admin-nav-link--active' : 'admin-nav-link'}
            href={`#${item.path}`} aria-current={active ? (pathname === item.path ? 'page' : 'location') : undefined} onClick={onClose}>
            <Icon name={item.icon ?? 'file'} /><span>{item.label}</span><Icon name="chevron" className="admin-nav-chevron" />
          </a>;
        })}
      </div>)}
      {groups.size === 0 && <p className="admin-nav-empty">No matching sections.</p>}
    </nav>
    {status && <div className="admin-sidebar-footer">{status}</div>}
  </aside>;
}
