insert into public.admin_permissions(name,description) values
  ('payments.read', 'Read payments')
on conflict(name) do update set description=excluded.description;