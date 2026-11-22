import type { ButtonHTMLAttributes, HTMLAttributes, ReactNode } from 'react';
import { Icon } from './Icon';

export interface ButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: 'primary' | 'secondary' | 'soft' | 'danger';
  icon?: string;
  loading?: boolean;
}

export function Button({ variant = 'secondary', icon, loading = false, children, className = '', type = 'button', disabled, ...props }: ButtonProps) {
  return <button {...props} type={type} className={`admin-btn admin-btn--${variant} ${className}`} disabled={disabled || loading} aria-busy={loading || undefined}>
    {loading ? <span className="admin-spinner" aria-hidden="true" /> : icon ? <Icon name={icon} /> : null}
    {children}
  </button>;
}

export function Card({ className = '', children, ...props }: HTMLAttributes<HTMLDivElement>) {
  return <div className={`admin-card ${className}`} {...props}>{children}</div>;
}

export interface PageHeaderProps {
  title: string;
  eyebrow?: string;
  subtitle?: string;
  actions?: ReactNode;
}

export function PageHeader({ title, eyebrow, subtitle, actions }: PageHeaderProps) {
  return <div className="admin-page-heading">
    <div>{eyebrow && <p className="admin-eyebrow">{eyebrow}</p>}<h1>{title}</h1>{subtitle && <p className="admin-page-subtitle">{subtitle}</p>}</div>
    {actions && <div className="admin-heading-actions">{actions}</div>}
  </div>;
}

export interface StatusBadgeProps {
  children: ReactNode;
  tone?: 'success' | 'warning' | 'danger' | 'info' | 'neutral';
}

export function StatusBadge({ children, tone = 'neutral' }: StatusBadgeProps) {
  return <span className={`admin-badge admin-badge--${tone}`}><span className="admin-badge-dot" aria-hidden="true" />{children}</span>;
}

export function LoadingState({ label = 'Loading' }: { label?: string }) {
  return <div className="admin-state" role="status"><span className="admin-spinner" aria-hidden="true" /><span>{label}</span></div>;
}

export function ErrorState({ title = 'Unable to load this page', message, onRetry }: { title?: string; message: string; onRetry?: () => void }) {
  return <div className="admin-state admin-state--error" role="alert"><Icon name="alert" /><h2>{title}</h2><p>{message}</p>{onRetry && <Button onClick={onRetry} icon="refresh">Try again</Button>}</div>;
}

export function EmptyState({ title, description, action }: { title: string; description?: string; action?: ReactNode }) {
  return <div className="admin-state"><span className="admin-state-icon"><Icon name="file" /></span><h2>{title}</h2>{description && <p>{description}</p>}{action}</div>;
}

export function Field({ label, htmlFor, hint, error, children }: { label: string; htmlFor: string; hint?: string; error?: string; children: ReactNode }) {
  return <div className="admin-field"><label htmlFor={htmlFor}>{label}</label>{children}{hint && <p className="admin-field-hint">{hint}</p>}{error && <p className="admin-field-error" role="alert">{error}</p>}</div>;
}
