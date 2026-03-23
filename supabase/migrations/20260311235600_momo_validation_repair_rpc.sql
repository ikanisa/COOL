-- ==========================================================================
-- Cool App — Admin RPC for repairing fixable MoMo validation issues
-- ==========================================================================
-- Re-applies the DB normalization layer to a selected user/group record.
-- This is intentionally narrow and admin-only. It is meant for rows that
-- became invalid before the trigger layer existed or that need route-type
-- reset so the trigger can infer the correct recipient type.
-- ==========================================================================

create or replace function public.repair_momo_validation_issue(
  p_record_type text,
  p_record_id uuid,
  p_issue_code text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_record_type text := lower(btrim(coalesce(p_record_type, '')));
  v_issue_code text := lower(btrim(coalesce(p_issue_code, '')));
  v_row_count integer := 0;
begin
  if not public.is_admin() then
    return jsonb_build_object(
      'status', 'error',
      'message', 'Admin access required.'
    );
  end if;

  if p_record_id is null then
    return jsonb_build_object(
      'status', 'error',
      'message', 'record_id is required.'
    );
  end if;

  begin
    if v_record_type = 'user' then
      update public.users u
      set
        country = public.normalize_country_code(u.country),
        momo_number = u.momo_number,
        momo_code = u.momo_code,
        updated_at = now()
      where u.id = p_record_id;

      get diagnostics v_row_count = row_count;
    elsif v_record_type = 'group' then
      update public.groups g
      set
        country = public.normalize_country_code(g.country),
        receiving_momo_code = coalesce(
          nullif(btrim(coalesce(g.receiving_momo_code, '')), ''),
          nullif(btrim(coalesce(g.momo_number, '')), '')
        ),
        receiving_momo_route_type = case
          when v_issue_code in (
            'unsupported_route_type',
            'invalid_momo_code',
            'invalid_phone_recipient'
          ) then null
          else g.receiving_momo_route_type
        end,
        updated_at = now()
      where g.id = p_record_id;

      get diagnostics v_row_count = row_count;
    else
      return jsonb_build_object(
        'status', 'error',
        'message', format('Unsupported record_type %s.', coalesce(v_record_type, '(blank)'))
      );
    end if;
  exception
    when others then
      return jsonb_build_object(
        'status', 'error',
        'record_type', v_record_type,
        'record_id', p_record_id,
        'issue_code', v_issue_code,
        'message', sqlerrm
      );
  end;

  if v_row_count = 0 then
    return jsonb_build_object(
      'status', 'not_found',
      'record_type', v_record_type,
      'record_id', p_record_id,
      'issue_code', v_issue_code,
      'message', 'No matching record was found.'
    );
  end if;

  return jsonb_build_object(
    'status', 'repaired',
    'record_type', v_record_type,
    'record_id', p_record_id,
    'issue_code', v_issue_code,
    'message', 'Normalization was re-applied to the record.'
  );
end;
$$;
revoke all on function public.repair_momo_validation_issue(text, uuid, text)
  from public;
grant execute on function public.repair_momo_validation_issue(text, uuid, text)
  to authenticated;
