import type { ReactNode, SVGProps } from 'react';

const paths: Record<string, ReactNode> = {
  home: <><path d="m3 10 9-7 9 7v10a1 1 0 0 1-1 1h-5v-7H9v7H4a1 1 0 0 1-1-1z" /></>,
  users: <><path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2" /><circle cx="9" cy="7" r="4" /><path d="M22 21v-2a4 4 0 0 0-3-3.9M16 3.1a4 4 0 0 1 0 7.8" /></>,
  user: <><circle cx="12" cy="7" r="4" /><path d="M4 21v-2a8 8 0 0 1 16 0v2" /></>,
  'user-check': <><path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2" /><circle cx="9" cy="7" r="4" /><path d="m17 11 2 2 4-4" /></>,
  contact: <><rect x="3" y="4" width="18" height="16" rx="2" /><circle cx="10" cy="10" r="2" /><path d="M6 17c1-3 7-3 8 0M16 8h3M16 12h3" /></>,
  swap: <><path d="M4 7h16m-4-4 4 4-4 4M20 17H4m4-4-4 4 4 4" /></>,
  layers: <><rect x="4" y="4" width="16" height="16" rx="3" /><path d="M8 9h8M8 13h8M8 17h4" /></>,
  book: <><path d="M4 4h15v17H6a2 2 0 0 1-2-2V4zM4 18a2 2 0 0 1 2-2h13M8 8h7" /></>,
  alert: <><path d="m12 3 10 18H2L12 3zM12 9v5M12 18h.01" /></>,
  message: <><rect x="3" y="3" width="18" height="16" rx="3" /><path d="M7 8h10M7 12h7M7 19v2" /></>,
  file: <><path d="M5 3h10l4 4v14H5zM15 3v5h4M8 12h8M8 16h6" /></>,
  smartphone: <><rect x="6" y="2" width="12" height="20" rx="2" /><path d="M11 18h2" /></>,
  bell: <><path d="M18 8a6 6 0 1 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9M10 21h4" /></>,
  shield: <><path d="m12 22 8-4V6l-8-4-8 4v12zM9 12l2 2 4-4" /></>,
  lock: <><rect x="4" y="11" width="16" height="11" rx="2" /><path d="M8 11V7a4 4 0 0 1 8 0v4" /></>,
  settings: <><circle cx="12" cy="12" r="3" /><path d="M12 2v3m0 14v3M2 12h3m14 0h3M4.9 4.9 7 7m10 10 2.1 2.1m0-14.2L17 7M7 17l-2.1 2.1" /></>,
  search: <><circle cx="11" cy="11" r="7" /><path d="m16 16 5 5" /></>,
  chevron: <><path d="m9 18 6-6-6-6" /></>,
  down: <><path d="m6 9 6 6 6-6" /></>,
  plus: <><path d="M12 5v14M5 12h14" /></>,
  refresh: <><path d="M20 8A8 8 0 1 0 20 16M20 3v5h-5" /></>,
  download: <><path d="M12 2v13m-5-5 5 5 5-5M4 17v4h16v-4" /></>,
  filter: <><path d="M3 5h18L14 13v6l-4 2v-8z" /></>,
  more: <><circle cx="5" cy="12" r="1" /><circle cx="12" cy="12" r="1" /><circle cx="19" cy="12" r="1" /></>,
  close: <><path d="M5 5 19 19M19 5 5 19" /></>,
  check: <><path d="m4 12 5 5L20 6" /></>,
  info: <><circle cx="12" cy="12" r="9" /><path d="M12 11v5M12 7h.01" /></>,
  menu: <><path d="M3 6h18M3 12h18M3 18h18" /></>,
  arrow: <><path d="M5 12h14m-6-6 6 6-6 6" /></>,
  copy: <><rect x="8" y="8" width="12" height="12" rx="2" /><path d="M16 8V5a2 2 0 0 0-2-2H5a2 2 0 0 0-2 2v9a2 2 0 0 0 2 2h3" /></>,
  edit: <><path d="M4 20h4l12-12-4-4L4 16zM14 6l4 4" /></>,
  external: <><path d="M14 4h6v6M20 4l-9 9M19 13v6H5V5h6" /></>,
  logout: <><path d="M10 4H5v16h5M14 8l4 4-4 4M8 12h10" /></>,
};

export interface IconProps extends SVGProps<SVGSVGElement> {
  name: string;
}

export function Icon({ name, className = '', ...props }: IconProps) {
  return <svg aria-hidden="true" focusable="false" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.85" strokeLinecap="round" strokeLinejoin="round" className={`admin-icon ${className}`} {...props}>{paths[name] ?? paths.info}</svg>;
}
