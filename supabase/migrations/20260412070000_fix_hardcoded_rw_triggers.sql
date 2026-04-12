-- ==========================================================================
-- Phase 2C: Fix hardcoded 'RW' in trigger functions
-- ==========================================================================
-- Replaces literal 'RW' in enforce_partner_payment_route_fields() and
-- create_group_atomic() with config-driven lookups.
-- ==========================================================================

-- ── Fix enforce_partner_payment_route_fields() ──────────────────────────

CREATE OR REPLACE FUNCTION public.enforce_partner_payment_route_fields()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_country public.supported_countries;
  v_default_country text;
BEGIN
  -- Use config-driven default instead of hardcoded 'RW'
  SELECT value INTO v_default_country
  FROM public.app_config WHERE key = 'default_country';
  v_default_country := coalesce(v_default_country, 'RW');

  new.country := coalesce(
    nullif(btrim(new.country), ''),
    v_default_country
  );

  new.provider := public.normalize_partner_payment_provider(new.provider);
  new.status := lower(btrim(coalesce(new.status, 'draft')));

  new.reconciliation_label := regexp_replace(
    lower(btrim(coalesce(new.reconciliation_label, ''))),
    '[^a-z0-9]+',
    '_',
    'g'
  );
  new.reconciliation_label := btrim(new.reconciliation_label, '_');

  new.recipient_code := public.normalize_momo_code_for_country(
    new.country,
    new.recipient_code
  );

  -- Dynamic country config lookup
  SELECT *
  INTO v_country
  FROM public.get_supported_country_momo_config(new.country);

  IF v_country.iso_code IS NULL THEN
    RAISE EXCEPTION 'Mobile money configuration is missing for country: %', new.country;
  END IF;

  IF new.provider = '' THEN
    RAISE EXCEPTION 'Payment provider is required.';
  END IF;

  IF new.reconciliation_label = '' THEN
    RAISE EXCEPTION 'Reconciliation label is required.';
  END IF;

  IF new.status NOT IN ('draft', 'active', 'inactive') THEN
    RAISE EXCEPTION 'Invalid payment route status: %', new.status;
  END IF;

  IF coalesce(nullif(v_country.momo_code_ussd_template, ''), '') = '' THEN
    RAISE EXCEPTION 'Merchant-code payments are not configured for country: %', new.country;
  END IF;

  IF new.status = 'active' AND new.recipient_code IS NULL THEN
    RAISE EXCEPTION 'Active payment routes require a merchant code.';
  END IF;

  RETURN new;
END;
$$;

-- ── Fix create_group_atomic() ───────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.create_group_atomic(
  p_name text,
  p_visibility text,
  p_type text,
  p_description text DEFAULT NULL,
  p_country text DEFAULT NULL,
  p_target_amount integer DEFAULT 0,
  p_monthly_contribution integer DEFAULT NULL,
  p_cycle_days integer DEFAULT 30,
  p_bank_partner text DEFAULT NULL,
  p_momo_number text DEFAULT NULL,
  p_receiving_momo_code text DEFAULT NULL,
  p_receiving_momo_route_type text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user public.users;
  v_group public.groups;
  v_invite_code text;
  v_default_country text;
BEGIN
  p_country := nullif(btrim(coalesce(p_country, '')), '');

  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required.';
  END IF;

  SELECT *
  INTO v_user
  FROM public.users
  WHERE id = auth.uid();

  IF v_user.id IS NULL THEN
    RAISE EXCEPTION 'Complete profile before creating a group.';
  END IF;

  -- Use user's country or config default — not hardcoded 'RW'
  SELECT value INTO v_default_country
  FROM public.app_config WHERE key = 'default_country';

  v_invite_code := public.generate_group_invite_code();

  INSERT INTO public.groups (
    creator_id,
    name,
    description,
    country,
    visibility,
    type,
    amount,
    target_amount,
    monthly_contribution,
    contribution_amount,
    cycle_days,
    frequency,
    bank_partner,
    momo_number,
    receiving_momo_code,
    receiving_momo_route_type,
    invite_code
  )
  VALUES (
    auth.uid(),
    nullif(btrim(p_name), ''),
    nullif(btrim(coalesce(p_description, '')), ''),
    coalesce(p_country, v_user.country, v_default_country, 'RW'),
    coalesce(nullif(btrim(coalesce(p_visibility, '')), ''), 'private'),
    coalesce(nullif(btrim(coalesce(p_type, '')), ''), 'saving'),
    0,
    coalesce(p_target_amount, 0),
    p_monthly_contribution,
    coalesce(p_monthly_contribution, p_target_amount, 0),
    greatest(coalesce(p_cycle_days, 30), 1),
    coalesce(
      nullif(
        btrim(
          CASE
            WHEN p_cycle_days <= 1 THEN 'daily'
            WHEN p_cycle_days <= 7 THEN 'weekly'
            ELSE 'monthly'
          END
        ),
        ''
      ),
      'monthly'
    ),
    nullif(btrim(coalesce(p_bank_partner, '')), ''),
    nullif(btrim(coalesce(p_momo_number, '')), ''),
    nullif(btrim(coalesce(p_receiving_momo_code, '')), ''),
    nullif(btrim(coalesce(p_receiving_momo_route_type, '')), ''),
    v_invite_code
  )
  RETURNING *
  INTO v_group;

  INSERT INTO public.group_members (
    group_id,
    user_id,
    display_name,
    is_admin,
    is_anonymous,
    contribution_amount,
    joined_at
  )
  VALUES (
    v_group.id,
    auth.uid(),
    coalesce(nullif(btrim(v_user.public_user_id), ''), '000000'),
    true,
    false,
    0,
    now()
  )
  ON CONFLICT (group_id, user_id) DO UPDATE
  SET
    is_admin = true,
    display_name = excluded.display_name;

  RETURN jsonb_build_object(
    'status', 'success',
    'group_id', v_group.id,
    'invite_code', v_invite_code
  );
EXCEPTION
  WHEN others THEN
    RETURN jsonb_build_object(
      'status', 'error',
      'message', sqlerrm
    );
END;
$$;
