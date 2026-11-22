import {useEffect, useLayoutEffect, useRef, type RefObject} from 'react';

const scopes: HTMLElement[] = [];
const controlSelector = [
  'a[href]', 'button', 'input:not([type="hidden"])', 'select', 'textarea', '[tabindex]',
].join(',');

export function hasActiveFocusScope(): boolean {
  return scopes.length > 0;
}

function tabbableControls(panel: HTMLElement): HTMLElement[] {
  return Array.from(panel.querySelectorAll<HTMLElement>(controlSelector)).filter(element =>
    element.tabIndex >= 0 && !element.matches(':disabled') &&
    !element.closest('[hidden], [inert], [aria-hidden="true"]') &&
    (element.checkVisibility?.({visibilityProperty: true}) ?? true));
}

export function useFocusScope(open: boolean, panelRef: RefObject<HTMLElement | null>, onDismiss: () => void,
  restoreTo?: RefObject<HTMLElement | null>) {
  const dismissRef = useRef(onDismiss);
  useLayoutEffect(() => { dismissRef.current = onDismiss; }, [onDismiss]);

  useEffect(() => {
    const panel = panelRef.current;
    if (!open || !panel) return;
    const owner = panel.ownerDocument;
    const previous = restoreTo?.current ?? (owner.activeElement instanceof HTMLElement ? owner.activeElement : null);
    scopes.push(panel);
    const focusFirst = () => (tabbableControls(panel)[0] ?? panel).focus();
    focusFirst();

    const onFocus = (event: FocusEvent) => {
      if (scopes.at(-1) === panel && event.target instanceof Node && !panel.contains(event.target)) focusFirst();
    };
    const onKeyDown = (event: KeyboardEvent) => {
      if (scopes.at(-1) !== panel || event.defaultPrevented) return;
      if (event.key === 'Escape') {
        event.preventDefault();
        dismissRef.current();
      } else if (event.key === 'Tab') {
        const controls = tabbableControls(panel);
        const active = owner.activeElement;
        const boundary = event.shiftKey ? controls.at(0) : controls.at(-1);
        if (active === boundary || !controls.some(control => control === active)) {
          event.preventDefault();
          ((event.shiftKey ? controls.at(-1) : controls.at(0)) ?? panel).focus();
        }
      }
    };
    owner.addEventListener('focusin', onFocus);
    owner.addEventListener('keydown', onKeyDown);
    return () => {
      const wasTop = scopes.at(-1) === panel;
      scopes.splice(scopes.indexOf(panel), 1);
      owner.removeEventListener('focusin', onFocus);
      owner.removeEventListener('keydown', onKeyDown);
      if (wasTop && previous?.isConnected) previous.focus();
    };
  }, [open, panelRef, restoreTo]);
}
