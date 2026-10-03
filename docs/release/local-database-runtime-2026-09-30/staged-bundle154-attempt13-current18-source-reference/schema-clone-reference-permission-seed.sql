insert into public.admin_permissions (name, description)
values
  ('notifications.read', 'Read notification event and delivery health'),
  ('notifications.manage', 'Retry failed notification deliveries with a reason')
on conflict (name) do update set description = excluded.description;