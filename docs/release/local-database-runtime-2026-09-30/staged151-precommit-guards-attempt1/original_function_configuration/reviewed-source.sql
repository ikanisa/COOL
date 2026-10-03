begin;

-- Database-owner provisioning keeps the existing runtime-control audit guards.
-- Serialize the absence check: a conflicting BEFORE INSERT would otherwise
-- advance governance state even when ON CONFLICT skips the navigation row.
lock table public.admin_navigation_items in share row exclusive mode;

insert into public.admin_navigation_items (
  key, label, icon_key, route_path, required_permission,
  display_order, enabled, metadata, updated_reason
)
select
  'automations', 'Automations', 'manage_search', '/admin/automations',
  'system_health.read', 145, true, '{}'::jsonb,
  'Read-only payment and notification operations monitoring'
where not exists (
  select 1 from public.admin_navigation_items
  where key = 'automations' or route_path = '/admin/automations'
)
on conflict do nothing;

alter function public.user_can_read_collection(uuid,uuid) set statement_timeout='17s';
commit;
