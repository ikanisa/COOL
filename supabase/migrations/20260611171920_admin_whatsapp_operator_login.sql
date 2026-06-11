create or replace function admin_bootstrap_whatsapp_operator()
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  allowed_phone constant text := '+250788767816';
  current_digits text;
  current_phone text;
  owner_role_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  current_digits := regexp_replace(coalesce(auth.jwt() ->> 'phone', ''), '[^0-9]', '', 'g');
  if left(current_digits, 2) = '00' then
    current_digits := substring(current_digits from 3);
  end if;
  current_phone := case
    when current_digits = '' then ''
    else '+' || current_digits
  end;

  if current_phone <> allowed_phone then
    raise exception 'Registered admin WhatsApp number required';
  end if;

  if exists (
    select 1
    from profiles
    where whatsapp_phone = allowed_phone
      and id <> auth.uid()
  ) then
    raise exception 'Registered admin WhatsApp number belongs to another profile';
  end if;

  insert into profiles (
    id,
    public_id,
    whatsapp_phone,
    display_name,
    is_platform_admin
  )
  values (
    auth.uid(),
    generate_public_id(),
    allowed_phone,
    'Collect admin',
    true
  )
  on conflict (id) do update
  set
    whatsapp_phone = allowed_phone,
    display_name = coalesce(nullif(profiles.display_name, ''), 'Collect admin'),
    is_platform_admin = true,
    updated_at = now();

  select id into owner_role_id
  from admin_roles
  where name = 'platform_owner';

  if owner_role_id is null then
    raise exception 'Platform owner role is not configured';
  end if;

  if not exists (
    select 1
    from admin_user_roles
    where user_id = auth.uid()
      and role_id = owner_role_id
      and revoked_at is null
  ) then
    insert into admin_user_roles (user_id, role_id, granted_by, reason)
    values (
      auth.uid(),
      owner_role_id,
      auth.uid(),
      'Verified admin WhatsApp operator login'
    );
  end if;

  perform create_audit_log(
    'admin.bootstrap.whatsapp_operator',
    'profile',
    auth.uid(),
    jsonb_build_object('phone_masked', mask_phone(allowed_phone)),
    auth.uid()
  );

  return jsonb_build_object('ok', true);
end;
$$;

revoke execute on function admin_bootstrap_whatsapp_operator()
  from public, anon, authenticated;
grant execute on function admin_bootstrap_whatsapp_operator() to authenticated;
