-- ============================================================================
-- Admin loan write contracts
-- ============================================================================
-- Adds create/detail/update/repayment/status RPCs so admin clients can manage
-- loans without direct table writes.

create or replace function public.admin_create_loan(
  p_member_id uuid,
  p_group_id uuid,
  p_loan_type text default 'general',
  p_initial_amount numeric default null,
  p_repayment_amount numeric default null,
  p_repayment_frequency text default 'daily',
  p_due_date timestamptz default null,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_loan_id uuid;
begin
  if not public.is_admin_user() then
    raise exception 'Forbidden: platform admin access required.';
  end if;

  if p_member_id is null or not exists (
    select 1 from public.users where id = p_member_id
  ) then
    raise exception 'Member not found.';
  end if;

  if p_group_id is null or not exists (
    select 1 from public.groups where id = p_group_id and type = 'saving'
  ) then
    raise exception 'Savings group not found.';
  end if;

  if not exists (
    select 1
    from public.group_members gm
    where gm.group_id = p_group_id
      and gm.user_id = p_member_id
  ) then
    raise exception 'Member is not part of the selected group.';
  end if;

  if coalesce(p_initial_amount, 0) <= 0 then
    raise exception 'Initial amount must be greater than zero.';
  end if;

  if coalesce(p_repayment_amount, 0) <= 0 then
    raise exception 'Repayment amount must be greater than zero.';
  end if;

  if p_loan_type not in ('solar', 'insurance', 'taxes', 'emoto', 'general') then
    raise exception 'Invalid loan type.';
  end if;

  if p_repayment_frequency not in ('daily', 'weekly', 'monthly') then
    raise exception 'Invalid repayment frequency.';
  end if;

  insert into public.loans (
    member_id,
    group_id,
    loan_type,
    initial_amount,
    repayment_amount,
    repayment_frequency,
    due_date,
    notes,
    created_by
  ) values (
    p_member_id,
    p_group_id,
    p_loan_type,
    p_initial_amount,
    p_repayment_amount,
    p_repayment_frequency,
    p_due_date,
    nullif(btrim(coalesce(p_notes, '')), ''),
    auth.uid()
  )
  returning id into v_loan_id;

  return jsonb_build_object(
    'status', 'success',
    'loan_id', v_loan_id
  );
end;
$$;

revoke all on function public.admin_create_loan(uuid, uuid, text, numeric, numeric, text, timestamptz, text) from public;
grant execute on function public.admin_create_loan(uuid, uuid, text, numeric, numeric, text, timestamptz, text) to authenticated;

create or replace function public.admin_update_loan(
  p_loan_id uuid,
  p_loan_type text default null,
  p_initial_amount numeric default null,
  p_repayment_amount numeric default null,
  p_repayment_frequency text default null,
  p_due_date timestamptz default null,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_loan public.loans%rowtype;
begin
  if not public.is_admin_user() then
    raise exception 'Forbidden: platform admin access required.';
  end if;

  select *
  into v_loan
  from public.loans
  where id = p_loan_id;

  if not found then
    raise exception 'Loan not found.';
  end if;

  if p_loan_type is not null and p_loan_type not in ('solar', 'insurance', 'taxes', 'emoto', 'general') then
    raise exception 'Invalid loan type.';
  end if;

  if p_repayment_frequency is not null and p_repayment_frequency not in ('daily', 'weekly', 'monthly') then
    raise exception 'Invalid repayment frequency.';
  end if;

  if p_initial_amount is not null and p_initial_amount < v_loan.total_paid then
    raise exception 'Initial amount cannot be less than total paid.';
  end if;

  if p_repayment_amount is not null and p_repayment_amount <= 0 then
    raise exception 'Repayment amount must be greater than zero.';
  end if;

  update public.loans
  set
    loan_type = coalesce(p_loan_type, loan_type),
    initial_amount = coalesce(p_initial_amount, initial_amount),
    repayment_amount = coalesce(p_repayment_amount, repayment_amount),
    repayment_frequency = coalesce(p_repayment_frequency, repayment_frequency),
    due_date = coalesce(p_due_date, due_date),
    notes = case
      when p_notes is not null then nullif(btrim(p_notes), '')
      else notes
    end,
    updated_at = now()
  where id = p_loan_id;

  return jsonb_build_object(
    'status', 'success',
    'loan_id', p_loan_id
  );
end;
$$;

revoke all on function public.admin_update_loan(uuid, text, numeric, numeric, text, timestamptz, text) from public;
grant execute on function public.admin_update_loan(uuid, text, numeric, numeric, text, timestamptz, text) to authenticated;

create or replace function public.admin_record_loan_repayment(
  p_loan_id uuid,
  p_amount numeric,
  p_method text default 'cash',
  p_reference text default null,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_loan public.loans%rowtype;
  v_repayment_id uuid;
begin
  if not public.is_admin_user() then
    raise exception 'Forbidden: platform admin access required.';
  end if;

  if coalesce(p_amount, 0) <= 0 then
    raise exception 'Repayment amount must be greater than zero.';
  end if;

  if p_method not in ('cash', 'momo') then
    raise exception 'Invalid repayment method.';
  end if;

  select *
  into v_loan
  from public.loans
  where id = p_loan_id;

  if not found then
    raise exception 'Loan not found.';
  end if;

  if v_loan.status = 'defaulted' then
    raise exception 'Defaulted loans must be re-opened before recording repayments.';
  end if;

  if v_loan.total_paid + p_amount > v_loan.initial_amount then
    raise exception 'Repayment exceeds the outstanding balance.';
  end if;

  insert into public.loan_repayments (
    loan_id,
    amount,
    method,
    reference,
    recorded_by,
    notes
  ) values (
    p_loan_id,
    p_amount,
    p_method,
    nullif(btrim(coalesce(p_reference, '')), ''),
    auth.uid(),
    nullif(btrim(coalesce(p_notes, '')), '')
  )
  returning id into v_repayment_id;

  return jsonb_build_object(
    'status', 'success',
    'loan_id', p_loan_id,
    'repayment_id', v_repayment_id
  );
end;
$$;

revoke all on function public.admin_record_loan_repayment(uuid, numeric, text, text, text) from public;
grant execute on function public.admin_record_loan_repayment(uuid, numeric, text, text, text) to authenticated;

create or replace function public.admin_update_loan_status(
  p_loan_id uuid,
  p_status text,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if not public.is_admin_user() then
    raise exception 'Forbidden: platform admin access required.';
  end if;

  if p_status not in ('active', 'completed', 'non_performing', 'defaulted') then
    raise exception 'Invalid loan status.';
  end if;

  if not exists (select 1 from public.loans where id = p_loan_id) then
    raise exception 'Loan not found.';
  end if;

  update public.loans
  set
    status = p_status,
    completed_at = case
      when p_status = 'completed' then coalesce(completed_at, now())
      when p_status in ('active', 'non_performing', 'defaulted') then null
      else completed_at
    end,
    notes = case
      when p_notes is not null then nullif(btrim(p_notes), '')
      else notes
    end,
    updated_at = now()
  where id = p_loan_id;

  return jsonb_build_object(
    'status', 'success',
    'loan_id', p_loan_id,
    'loan_status', p_status
  );
end;
$$;

revoke all on function public.admin_update_loan_status(uuid, text, text) from public;
grant execute on function public.admin_update_loan_status(uuid, text, text) to authenticated;

create or replace function public.admin_get_loan_detail(
  p_loan_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
  v_result jsonb;
begin
  if not public.is_admin_user() then
    raise exception 'Forbidden: platform admin access required.';
  end if;

  select jsonb_build_object(
    'loan',
    jsonb_build_object(
      'id', l.id,
      'loan_code', l.loan_code,
      'loan_type', l.loan_type,
      'initial_amount', l.initial_amount,
      'total_paid', l.total_paid,
      'outstanding_balance', l.initial_amount - l.total_paid,
      'repayment_amount', l.repayment_amount,
      'repayment_frequency', l.repayment_frequency,
      'status', l.status,
      'issued_at', l.issued_at,
      'due_date', l.due_date,
      'completed_at', l.completed_at,
      'notes', l.notes,
      'member_id', l.member_id,
      'member_name', u.full_name,
      'member_phone', u.phone,
      'group_id', l.group_id,
      'group_name', g.name
    ),
    'repayments',
    coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', lr.id,
            'amount', lr.amount,
            'method', lr.method,
            'reference', lr.reference,
            'notes', lr.notes,
            'recorded_by', lr.recorded_by,
            'recorded_by_name', recorder.full_name,
            'created_at', lr.created_at
          )
          order by lr.created_at desc
        )
        from public.loan_repayments lr
        left join public.users recorder on recorder.id = lr.recorded_by
        where lr.loan_id = l.id
      ),
      '[]'::jsonb
    )
  )
  into v_result
  from public.loans l
  join public.users u on u.id = l.member_id
  join public.groups g on g.id = l.group_id
  where l.id = p_loan_id;

  if v_result is null then
    raise exception 'Loan not found.';
  end if;

  return v_result;
end;
$$;

revoke all on function public.admin_get_loan_detail(uuid) from public;
grant execute on function public.admin_get_loan_detail(uuid) to authenticated;
