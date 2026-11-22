import { useEffect, useMemo, useRef, useState, type KeyboardEvent as ReactKeyboardEvent, type ReactNode } from 'react';
import { Icon } from '../ui/Icon';
import { hasActiveFocusScope, useFocusScope } from '../ui/useFocusScope';
import {AdminAccountMenu, type AdminShellIdentity} from './AdminAccountMenu';
import {AdminNavigation, findCurrentSection, type AdminNavItem} from './AdminNavigation';

export type {AdminShellIdentity} from './AdminAccountMenu';
export type {AdminNavItem} from './AdminNavigation';

export interface AdminShellProps {
  navigation: AdminNavItem[];
  currentPath: string;
  identity?: AdminShellIdentity | null;
  onSignOut?: () => void;
  toolbar?: ReactNode;
  status?: ReactNode;
  children: ReactNode;
}

const compactNavigation = '(max-width: 720px)';

export function AdminShell({ navigation, currentPath, identity, onSignOut, toolbar, status, children }: AdminShellProps) {
  const [menuOpen, setMenuOpen] = useState(false);
  const [search, setSearch] = useState('');
  const searchRef = useRef<HTMLInputElement>(null);
  const menuTrigger = useRef<HTMLElement>(null);
  const sidebarRef = useRef<HTMLElement>(null);
  const sectionsRef = useRef<HTMLElement>(null);
  const pendingResult = useRef<'first' | 'last' | null>(null);
  const contentRef = useRef<HTMLElement>(null);
  const closeMenu = () => setMenuOpen(false);
  function openMenu(trigger: HTMLElement) {
    menuTrigger.current = trigger;
    setMenuOpen(true);
  }
  useFocusScope(menuOpen, sidebarRef, closeMenu, menuTrigger);
  const pathname = currentPath.split('?')[0];
  const selected = useMemo(() => findCurrentSection(navigation, pathname), [navigation, pathname]);
  const groups = useMemo(() => {
    const query = search.trim().toLocaleLowerCase();
    const result = new Map<string, AdminNavItem[]>();
    for (const item of navigation) {
      if (!item.label.toLocaleLowerCase().includes(query)) continue;
      const key = item.section ?? 'Workspace';
      const group = result.get(key);
      if (group) group.push(item);
      else result.set(key, [item]);
    }
    return result;
  }, [navigation, search]);

  useEffect(() => {
    const handleShortcut = (event: KeyboardEvent) => {
      if (!event.defaultPrevented && !hasActiveFocusScope() && (event.metaKey || event.ctrlKey) && event.key.toLowerCase() === 'k') {
        event.preventDefault();
        searchRef.current?.focus();
      }
    };
    document.addEventListener('keydown', handleShortcut);
    return () => document.removeEventListener('keydown', handleShortcut);
  }, []);

  useEffect(() => {
    if (!menuOpen) return;
    const edge = pendingResult.current;
    pendingResult.current = null;
    if (edge) {
      const links = sectionsRef.current?.querySelectorAll<HTMLAnchorElement>('a[href]');
      links?.[edge === 'first' ? 0 : links.length - 1]?.focus();
    }
    const media = window.matchMedia?.(compactNavigation);
    const resize = (event: MediaQueryListEvent) => {
      if (!event.matches) setMenuOpen(false);
    };
    media?.addEventListener?.('change', resize);
    return () => media?.removeEventListener?.('change', resize);
  }, [menuOpen]);

  const handleSearchKeys = (event: ReactKeyboardEvent<HTMLInputElement>) => {
    const {key} = event;
    if (key === 'Escape') {
      setSearch('');
      return;
    }
    if (key !== 'ArrowDown' && key !== 'ArrowUp' && key !== 'Enter') return;
    const compact = window.matchMedia?.(compactNavigation).matches;
    if (key === 'Enter' && compact) {
      event.preventDefault();
      openMenu(event.currentTarget);
      return;
    }
    const term = search.trim().toLocaleLowerCase();
    if (!term) return;
    const links = [...(sectionsRef.current?.querySelectorAll<HTMLAnchorElement>('a[href]') ?? [])];
    if (!links.length) return;
    if (key === 'ArrowDown' || key === 'ArrowUp') {
      event.preventDefault();
      const edge = key === 'ArrowDown' ? 'first' : 'last';
      if (compact && !menuOpen) {
        pendingResult.current = edge;
        openMenu(event.currentTarget);
      } else {
        links[edge === 'first' ? 0 : links.length - 1].focus();
      }
      return;
    }
    const exact = links.filter(link => link.textContent?.trim().toLocaleLowerCase() === term);
    const match = links.length === 1 ? links[0] : exact.length === 1 ? exact[0] : undefined;
    if (match) {
      event.preventDefault();
      match.click();
    }
  };

  const handleResultKeys = (event: ReactKeyboardEvent<HTMLElement>) => {
    if (event.key === 'Escape' && !menuOpen) {
      setSearch('');
      searchRef.current?.focus();
      return;
    }
    if (!search.trim() || (event.key !== 'ArrowDown' && event.key !== 'ArrowUp')) return;
    const links = [...event.currentTarget.querySelectorAll<HTMLAnchorElement>('a[href]')];
    const index = links.findIndex(link => link === event.target);
    if (index < 0) return;
    event.preventDefault();
    const step = event.key === 'ArrowDown' ? 1 : -1;
    links[(index + step + links.length) % links.length].focus();
  };

  const activeLabel = selected?.label ?? 'Workspace';
  return <div className={`admin-shell ${menuOpen ? 'admin-shell--menu-open' : ''}`}>
    <a className="admin-skip-link" href="#main-content" inert={menuOpen}
      onClick={(event) => { event.preventDefault(); contentRef.current?.focus(); }}>Skip to main content</a>
    {menuOpen && <button className="admin-menu-scrim" aria-hidden="true" tabIndex={-1} type="button" onClick={closeMenu} />}
    <AdminNavigation sidebar={sidebarRef} sections={sectionsRef} groups={groups} pathname={pathname} selected={selected}
      status={status} onClose={closeMenu} onSectionKeyDown={handleResultKeys} />
    <div className="admin-main-column" inert={menuOpen}>
      <header className="admin-topbar">
        <button type="button" className="admin-icon-button admin-menu-button" aria-label="Open navigation" aria-controls="admin-navigation" aria-expanded={menuOpen} onClick={event => openMenu(event.currentTarget)}><Icon name="menu" /></button>
        <div className="admin-crumb"><span>Workspace</span><span aria-hidden="true">/</span><strong>{activeLabel}</strong></div>
        <div className="admin-top-spacer" />
        <label className="admin-top-search"><Icon name="search" /><span className="admin-sr-only">Search admin sections</span><input ref={searchRef} value={search} onChange={(event) => setSearch(event.target.value)} onKeyDown={handleSearchKeys} type="search" placeholder="Search sections..." aria-describedby="admin-search-help" /><kbd aria-hidden="true">⌘ K</kbd></label>
        <span id="admin-search-help" className="admin-sr-only">Use the arrow keys to move through matching sections and Enter to open a focused section.</span>
        {toolbar}
        {identity && <AdminAccountMenu key={identity.name} identity={identity} onSignOut={onSignOut} />}
      </header>
      <main id="main-content" className="admin-content" ref={contentRef} tabIndex={-1}>{children}</main>
    </div>
  </div>;
}
