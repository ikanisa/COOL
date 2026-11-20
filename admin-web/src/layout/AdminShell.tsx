import { useEffect, useMemo, useRef, useState, type ReactNode } from 'react';
import { Icon } from '../ui/Icon';
import collectLogo from '../ui/assets/collect-logo.png';

export interface AdminNavItem {
  label: string;
  path: string;
  section?: string;
  icon?: string;
}

export interface AdminShellIdentity {
  name: string;
  role?: string;
}

export interface AdminShellProps {
  navigation: AdminNavItem[];
  currentPath: string;
  identity?: AdminShellIdentity | null;
  onSignOut?: () => void;
  toolbar?: ReactNode;
  status?: ReactNode;
  children: ReactNode;
}

function matchesPath(item: AdminNavItem, path: string): boolean {
  const route = path.split('?')[0];
  return item.path === '/admin' ? route === item.path : route === item.path || route.startsWith(`${item.path}/`);
}

export function AdminShell({ navigation, currentPath, identity, onSignOut, toolbar, status, children }: AdminShellProps) {
  const [menuOpen, setMenuOpen] = useState(false);
  const [profileOpen, setProfileOpen] = useState(false);
  const [search, setSearch] = useState('');
  const searchRef = useRef<HTMLInputElement>(null);
  const menuButtonRef = useRef<HTMLButtonElement>(null);
  const closeMenuRef = useRef<HTMLButtonElement>(null);
  const sidebarRef = useRef<HTMLElement>(null);
  const profileRef = useRef<HTMLDivElement>(null);
  const selected = useMemo(() => navigation.filter((item) => matchesPath(item, currentPath)).sort((a, b) => b.path.length - a.path.length)[0], [navigation, currentPath]);
  const groups = useMemo(() => {
    const filtered = navigation.filter((item) => item.label.toLocaleLowerCase().includes(search.trim().toLocaleLowerCase()));
    const result = new Map<string, AdminNavItem[]>();
    for (const item of filtered) {
      const key = item.section ?? 'Workspace';
      result.set(key, [...(result.get(key) ?? []), item]);
    }
    return result;
  }, [navigation, search]);

  useEffect(() => {
    const handleShortcut = (event: KeyboardEvent) => {
      if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === 'k') {
        event.preventDefault();
        searchRef.current?.focus();
      }
    };
    document.addEventListener('keydown', handleShortcut);
    return () => document.removeEventListener('keydown', handleShortcut);
  }, []);

  useEffect(() => {
    if (!menuOpen) return;
    closeMenuRef.current?.focus();
    const handleEscape = (event: KeyboardEvent) => {
      if (event.key === 'Escape') {
        setMenuOpen(false);
        menuButtonRef.current?.focus();
      } else if (event.key === 'Tab') {
        const sidebar = sidebarRef.current;
        if (!sidebar) return;
        const controls = [...sidebar.querySelectorAll<HTMLElement>('a[href], button:not([disabled])')];
        const first = controls[0];
        const last = controls[controls.length - 1];
        if (!first || !last) return;
        if (event.shiftKey && (document.activeElement === first || !sidebar.contains(document.activeElement))) {
          event.preventDefault();
          last.focus();
        } else if (!event.shiftKey && (document.activeElement === last || !sidebar.contains(document.activeElement))) {
          event.preventDefault();
          first.focus();
        }
      }
    };
    document.addEventListener('keydown', handleEscape);
    return () => document.removeEventListener('keydown', handleEscape);
  }, [menuOpen]);

  useEffect(() => {
    if (!profileOpen) return;
    const dismiss = (event: PointerEvent) => {
      if (event.target instanceof Node && !profileRef.current?.contains(event.target)) setProfileOpen(false);
    };
    const escape = (event: KeyboardEvent) => { if (event.key === 'Escape') setProfileOpen(false); };
    document.addEventListener('pointerdown', dismiss);
    document.addEventListener('keydown', escape);
    return () => { document.removeEventListener('pointerdown', dismiss); document.removeEventListener('keydown', escape); };
  }, [profileOpen]);

  const closeMenu = () => {
    setMenuOpen(false);
    menuButtonRef.current?.focus();
  };
  const activeLabel = selected?.label ?? 'Workspace';
  return <div className={`admin-shell ${menuOpen ? 'admin-shell--menu-open' : ''}`}>
    <a className="admin-skip-link" href="#main-content" onClick={(event) => { event.preventDefault(); document.getElementById('main-content')?.focus(); }}>Skip to main content</a>
    {menuOpen && <button className="admin-menu-scrim" aria-label="Close navigation" type="button" onClick={closeMenu} />}
    <aside ref={sidebarRef} className="admin-sidebar" id="admin-navigation" aria-label="Primary admin navigation">
      <div className="admin-brand">
        <img className="admin-brand-mark" src={collectLogo} alt="" />
        <div className="admin-brand-copy"><span className="admin-brand-title">Collect</span><span className="admin-brand-caption">Admin workspace</span></div>
        <button ref={closeMenuRef} type="button" className="admin-icon-button admin-sidebar-close" onClick={closeMenu} aria-label="Close navigation"><Icon name="close" /></button>
      </div>
      <nav className="admin-sidebar-scroll" aria-label="Admin sections">
        {[...groups].map(([section, items]) => <div className="admin-nav-group" key={section}>
          <div className="admin-nav-heading">{section}</div>
          {items.map((item) => {
            const active = selected?.path === item.path;
            return <a key={item.path} className={`admin-nav-link ${active ? 'admin-nav-link--active' : ''}`} href={`#${item.path}`} aria-current={active ? (currentPath.split('?')[0] === item.path ? 'page' : 'location') : undefined} onClick={() => { if (menuOpen) closeMenu(); }}>
              <Icon name={item.icon ?? 'file'} /><span>{item.label}</span><Icon name="chevron" className="admin-nav-chevron" />
            </a>;
          })}
        </div>)}
        {groups.size === 0 && <p className="admin-nav-empty">No matching sections.</p>}
      </nav>
      {status && <div className="admin-sidebar-footer">{status}</div>}
    </aside>
    <div className="admin-main-column">
      <header className="admin-topbar">
        <button ref={menuButtonRef} type="button" className="admin-icon-button admin-menu-button" aria-label="Open navigation" aria-controls="admin-navigation" aria-expanded={menuOpen} onClick={() => setMenuOpen(true)}><Icon name="menu" /></button>
        <div className="admin-crumb"><span>Workspace</span><span aria-hidden="true">/</span><strong>{activeLabel}</strong></div>
        <div className="admin-top-spacer" />
        <label className="admin-top-search"><Icon name="search" /><span className="admin-sr-only">Search admin sections</span><input ref={searchRef} value={search} onChange={(event) => setSearch(event.target.value)} onKeyDown={(event) => {
          if (event.key === 'Escape') setSearch('');
          if (event.key === 'Enter' && window.matchMedia?.('(max-width: 720px)').matches) {event.preventDefault(); setMenuOpen(true);}
        }} type="search" placeholder="Search sections..." aria-describedby="admin-search-help" /><kbd aria-hidden="true">⌘ K</kbd></label>
        <span id="admin-search-help" className="admin-sr-only">On small screens, press Enter to open matching sections.</span>
        {toolbar}
        {identity && <div className="admin-profile" ref={profileRef}><button className="admin-profile-button" type="button" aria-label={`Account: ${identity.name}`} aria-expanded={profileOpen} onClick={() => setProfileOpen((open) => !open)}><span className="admin-operator-role">{identity.role}</span><span className="admin-avatar" aria-hidden="true">{identity.name.slice(0, 1).toLocaleUpperCase()}</span></button>{profileOpen && <div className="admin-profile-menu"><strong>{identity.name}</strong>{identity.role && <span>{identity.role}</span>}{onSignOut && <button type="button" onClick={() => { setProfileOpen(false); onSignOut(); }}><Icon name="logout" />Sign out</button>}</div>}</div>}
      </header>
      <main id="main-content" className="admin-content" tabIndex={-1}>{children}</main>
    </div>
  </div>;
}
