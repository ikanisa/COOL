-- ============================================================================
-- generate_invite_code lint cleanup
-- ============================================================================
-- Removes the unreachable defensive RETURN from the helper after remote
-- plpgsql_check confirmed the retry loop already exits via RETURN or RAISE.
-- ============================================================================

create or replace function public.generate_invite_code()
returns text
language plpgsql
set search_path = public
as $$
declare
  v_code text;
  v_attempts integer := 0;
begin
  while v_attempts < 100 loop
    v_code := upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));

    if not exists (
      select 1
      from public.groups g
      where g.invite_code = v_code
    ) then
      return v_code;
    end if;

    v_attempts := v_attempts + 1;
  end loop;

  raise exception 'Could not generate unique invite code after 100 attempts';
end;
$$;

grant execute on function public.generate_invite_code()
  to authenticated, service_role;

comment on function public.generate_invite_code() is
  'Generates a unique six-character invite code for public.groups.';
