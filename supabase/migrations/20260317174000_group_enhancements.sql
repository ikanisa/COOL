-- ══════════════════════════════════════════════════════════════════════════
-- Group creation enhancements:
--   1) Add bank_partner_id FK to groups (savings groups link to a bank)
--   2) confirm_contribution() — idempotent pending → completed + balance update
--   3) Support one_off frequency (cycle_days = 0)
-- ══════════════════════════════════════════════════════════════════════════

-- 1) Add bank_partner_id to groups table
ALTER TABLE public.groups
  ADD COLUMN IF NOT EXISTS bank_partner_id uuid REFERENCES public.partners(id);
COMMENT ON COLUMN public.groups.bank_partner_id IS
  'For savings groups: the banking partner whose momo_code receives contributions. NULL for community groups.';
-- 2) Idempotent contribution confirmation function
CREATE OR REPLACE FUNCTION public.confirm_contribution(
  p_contribution_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_contribution record;
  v_group      record;
BEGIN
  -- Lock the contribution row
  SELECT id, group_id, amount, status
    INTO v_contribution
    FROM public.group_contributions
   WHERE id = p_contribution_id
   FOR UPDATE;

  IF v_contribution IS NULL THEN
    RETURN jsonb_build_object('status', 'error', 'message', 'Contribution not found.');
  END IF;

  -- Idempotent: already completed → no-op
  IF v_contribution.status = 'completed' THEN
    RETURN jsonb_build_object('status', 'already_completed');
  END IF;

  -- Only pending contributions can be confirmed
  IF v_contribution.status <> 'pending' THEN
    RETURN jsonb_build_object(
      'status', 'error',
      'message', format('Cannot confirm contribution with status: %s', v_contribution.status)
    );
  END IF;

  -- Mark as completed
  UPDATE public.group_contributions
     SET status = 'completed',
         updated_at = now()
   WHERE id = p_contribution_id;

  -- Update group balance
  UPDATE public.groups
     SET amount = coalesce(amount, 0) + v_contribution.amount,
         updated_at = now()
   WHERE id = v_contribution.group_id;

  RETURN jsonb_build_object('status', 'success', 'amount', v_contribution.amount);
END;
$$;
COMMENT ON FUNCTION public.confirm_contribution(uuid) IS
  'Idempotent: moves a pending contribution to completed and updates the group balance.';
-- 3) Update create_group_atomic to accept bank_partner_id
-- Drop and recreate to add the new parameter
CREATE OR REPLACE FUNCTION public.create_group_atomic(
  p_name              text,
  p_visibility        text    DEFAULT 'private',
  p_type              text    DEFAULT 'saving',
  p_description       text    DEFAULT NULL,
  p_country           text    DEFAULT 'RW',
  p_target_amount     bigint  DEFAULT 0,
  p_monthly_contribution bigint DEFAULT NULL,
  p_cycle_days        int     DEFAULT 30,
  p_momo_number       text    DEFAULT NULL,
  p_receiving_momo_code text  DEFAULT NULL,
  p_receiving_momo_route_type text DEFAULT NULL,
  p_bank_partner_id   uuid    DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id     uuid := auth.uid();
  v_group_id    uuid;
  v_invite_code text;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('status', 'error', 'message', 'Not authenticated.');
  END IF;

  -- Generate a 6-char invite code
  v_invite_code := upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));

  INSERT INTO public.groups (
    creator_id,
    name,
    visibility,
    type,
    description,
    country,
    target_amount,
    monthly_contribution,
    cycle_days,
    momo_number,
    receiving_momo_code,
    receiving_momo_route_type,
    bank_partner_id,
    invite_code,
    amount,
    created_at,
    updated_at
  ) VALUES (
    v_user_id,
    btrim(p_name),
    lower(btrim(coalesce(p_visibility, 'private'))),
    lower(btrim(coalesce(p_type, 'saving'))),
    nullif(btrim(coalesce(p_description, '')), ''),
    upper(btrim(coalesce(p_country, 'RW'))),
    coalesce(p_target_amount, 0),
    p_monthly_contribution,
    coalesce(p_cycle_days, 30),
    nullif(btrim(coalesce(p_momo_number, '')), ''),
    nullif(btrim(coalesce(p_receiving_momo_code, '')), ''),
    nullif(btrim(coalesce(p_receiving_momo_route_type, '')), ''),
    p_bank_partner_id,
    v_invite_code,
    0,
    now(),
    now()
  )
  RETURNING id INTO v_group_id;

  -- Auto-add creator as admin member
  INSERT INTO public.group_members (
    group_id,
    user_id,
    display_name,
    is_admin,
    joined_at
  ) VALUES (
    v_group_id,
    v_user_id,
    (SELECT coalesce(
       nullif(btrim(display_name), ''),
       nullif(btrim(phone), ''),
       v_user_id::text
     ) FROM public.users WHERE id = v_user_id),
    true,
    now()
  );

  RETURN jsonb_build_object('status', 'success', 'group_id', v_group_id);
END;
$$;
