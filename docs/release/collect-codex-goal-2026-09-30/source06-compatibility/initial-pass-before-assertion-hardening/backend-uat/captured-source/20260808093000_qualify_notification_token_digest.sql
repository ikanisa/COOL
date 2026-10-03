begin;

-- These SECURITY DEFINER functions deliberately pin search_path to public.
-- pgcrypto is installed in the extensions schema on hosted Supabase, so its
-- digest function must be schema-qualified to remain available fail-closed.
create or replace function register_notification_device(
  p_platform text,
  p_provider text,
  p_token text,
  p_environment text default 'production',
  p_locale text default 'en',
  p_app_version text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := (select auth.uid());
  clean_platform text := lower(trim(coalesce(p_platform, '')));
  clean_provider text := lower(trim(coalesce(p_provider, '')));
  clean_token text := trim(coalesce(p_token, ''));
  clean_environment text := lower(trim(coalesce(p_environment, '')));
  token_digest text;
  registered_id uuid;
begin
  if current_user_id is null then
    raise exception 'Authentication required';
  end if;
  if not (
    (clean_platform = 'ios' and clean_provider = 'apns')
    or (clean_platform = 'android' and clean_provider = 'fcm')
  ) then
    raise exception 'unsupported_notification_transport';
  end if;
  if clean_environment not in ('sandbox', 'production') then
    raise exception 'invalid_notification_environment';
  end if;
  if clean_provider = 'apns' and (
    char_length(clean_token) < 64
    or char_length(clean_token) > 512
    or clean_token !~ '^[0-9A-Fa-f]+$'
  ) then
    raise exception 'invalid_notification_token';
  end if;
  if clean_provider = 'fcm' and (
    char_length(clean_token) < 20
    or char_length(clean_token) > 4096
    or clean_token !~ '^[A-Za-z0-9_:\-]+$'
  ) then
    raise exception 'invalid_notification_token';
  end if;

  token_digest := encode(extensions.digest(clean_token, 'sha256'), 'hex');
  insert into notification_device_tokens (
    user_id, platform, provider, token, token_hash, token_last_four,
    environment, locale, app_version, enabled, last_seen_at,
    last_registered_at, disabled_at, disabled_reason, updated_at
  ) values (
    current_user_id, clean_platform, clean_provider, clean_token, token_digest,
    right(clean_token, 4), clean_environment,
    coalesce(nullif(trim(p_locale), ''), 'en'),
    nullif(trim(coalesce(p_app_version, '')), ''), true, now(), now(), null,
    null, now()
  )
  on conflict (provider, token_hash)
  do update set
    user_id = excluded.user_id,
    platform = excluded.platform,
    token = excluded.token,
    token_last_four = excluded.token_last_four,
    environment = excluded.environment,
    locale = excluded.locale,
    app_version = excluded.app_version,
    enabled = true,
    last_seen_at = now(),
    last_registered_at = now(),
    disabled_at = null,
    disabled_reason = null,
    updated_at = now()
  returning id into registered_id;
  return registered_id;
end;
$$;

create or replace function unregister_notification_device(
  p_provider text,
  p_token text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := (select auth.uid());
  clean_provider text := lower(trim(coalesce(p_provider, '')));
  token_digest text := encode(
    extensions.digest(trim(coalesce(p_token, '')), 'sha256'),
    'hex'
  );
begin
  if current_user_id is null then
    raise exception 'Authentication required';
  end if;
  update notification_device_tokens
  set enabled = false,
      disabled_at = now(),
      disabled_reason = 'user_signed_out',
      updated_at = now()
  where user_id = current_user_id
    and provider = clean_provider
    and token_hash = token_digest;
end;
$$;

revoke execute on function register_notification_device(text, text, text, text, text, text)
  from public, anon, authenticated;
grant execute on function register_notification_device(text, text, text, text, text, text)
  to authenticated;
revoke execute on function unregister_notification_device(text, text)
  from public, anon, authenticated;
grant execute on function unregister_notification_device(text, text)
  to authenticated;

commit;
