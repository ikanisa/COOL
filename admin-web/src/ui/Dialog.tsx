import { useId, useRef, type ReactNode } from 'react';
import { createPortal } from 'react-dom';
import { Icon } from './Icon';
import { useFocusScope } from './useFocusScope';

export interface DialogProps {
  open: boolean;
  title: string;
  onClose: () => void;
  children: ReactNode;
  footer?: ReactNode;
  placement?: 'center' | 'side';
}

/** Dialogs retain keyboard focus and restore it to the triggering control. */
export function Dialog({ open, title, onClose, children, footer, placement = 'center' }: DialogProps) {
  const titleId = useId();
  const panelRef = useRef<HTMLDivElement>(null);
  useFocusScope(open, panelRef, onClose);

  if (!open) return null;
  return createPortal(<div className={`admin-dialog-backdrop admin-dialog-backdrop--${placement}`} onMouseDown={(event) => { if (event.target === event.currentTarget) onClose(); }}>
    <div ref={panelRef} className={`admin-dialog admin-dialog--${placement}`} role="dialog" aria-modal="true" aria-labelledby={titleId} tabIndex={-1}>
      <div className="admin-dialog-header"><h2 id={titleId}>{title}</h2><button type="button" className="admin-icon-button" aria-label="Close dialog" onClick={onClose}><Icon name="close" /></button></div>
      <div className="admin-dialog-body">{children}</div>
      {footer && <div className="admin-dialog-footer">{footer}</div>}
    </div>
  </div>, document.body);
}
