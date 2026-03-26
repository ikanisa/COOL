-- Remove retired credit, KYC, and bank-loan surfaces.
-- Keep bank partners focused on group savings custody only.

-- Retire the scheduled credit refresh before removing the functions it calls.
select cron.unschedule(jobid)
from cron.job
where jobname = 'refresh-credit-scores-hourly';

drop function if exists public.refresh_credit_scores_due(timestamptz, integer, interval);
drop function if exists public.refresh_my_credit_score();
drop function if exists public.recompute_credit_scores_for_all_users(timestamptz);
drop function if exists public.recompute_credit_score(uuid, timestamptz);
drop function if exists public.credit_score_summary(integer, text[]);
drop function if exists public.credit_score_band(integer);
drop function if exists public.create_partner_credit_application(uuid, text, text, text, text, boolean, text, text);
drop function if exists public.get_bank_loans(uuid, text, integer, integer);
drop function if exists public.update_bank_loan_status(uuid, text, text);
drop function if exists public.get_bank_baskets(uuid, text, integer, integer);
drop function if exists public.get_bank_analytics_summary(uuid);

drop table if exists public.partner_application_handoffs cascade;
drop table if exists public.partner_credit_applications cascade;
drop table if exists public.credit_score_runs cascade;
drop table if exists public.credit_scores cascade;
drop table if exists public.bank_loans cascade;
drop table if exists public.bank_baskets cascade;

drop index if exists public.idx_users_kyc_status;
drop index if exists public.idx_users_kyc_document_type;
drop index if exists public.idx_users_kyc_extracted_at;

alter table public.users
  drop constraint if exists users_kyc_status_check;

alter table public.users
  drop constraint if exists users_kyc_document_type_check;

alter table public.users
  drop column if exists kyc_status,
  drop column if exists kyc_verified_at,
  drop column if exists credit_consent_granted_at,
  drop column if exists kyc_id_photo_url,
  drop column if exists kyc_document_type,
  drop column if exists kyc_extracted_at,
  drop column if exists kyc_extraction_provider;

delete from public.app_config
where key in (
  'kill_credit_features',
  'feature_credit_stage',
  'feature_credit_admin_only',
  'credit_grade_excellent',
  'credit_grade_good',
  'credit_grade_building'
);

delete from public.ai_content
where area = 'credit'
   or cta_action in ('/credit', '/credit/readiness');

delete from public.partner_services
where partner_id in (
  select id
  from public.partners
  where category = 'bank'
);

insert into public.partner_services (
  partner_id,
  title,
  subtitle,
  emoji,
  category,
  details,
  cta_label,
  cta_action,
  country,
  sort_order,
  is_active
)
select
  partner.id,
  'Group Savings Custodian',
  'Create a bank-custodied savings group',
  '🏦',
  'banking',
  '[]'::jsonb,
  'Open Custodian',
  'internal:group_savings_custodian',
  partner.country,
  0,
  true
from public.partners as partner
where partner.category = 'bank';

comment on table public.partner_services is
  'Dynamic partner services managed via admin. '
  'GUARDRAIL: Bank partners (category=bank) must expose exactly one custody CTA: '
  'internal:group_savings_custodian. Non-bank partners keep their own service schemas.';

create or replace function public.get_bank_analytics_summary(p_partner_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  result jsonb;
begin
  select jsonb_build_object(
    'total_groups',
      (
        select count(*)
        from public.groups as group_record
        where group_record.bank_partner_id = p_partner_id
      ),
    'active_groups_count',
      (
        select count(*)
        from public.groups as group_record
        where group_record.bank_partner_id = p_partner_id
      ),
    'total_group_balance',
      (
        select coalesce(sum(coalesce(group_record.amount, 0)), 0)
        from public.groups as group_record
        where group_record.bank_partner_id = p_partner_id
      ),
    'total_collected',
      (
        select coalesce(sum(coalesce(contribution.amount, 0)), 0)
        from public.group_contributions as contribution
        join public.groups as group_record
          on group_record.id = contribution.group_id
        where group_record.bank_partner_id = p_partner_id
          and contribution.status in ('completed', 'confirmed')
      ),
    'total_members',
      (
        select count(*)
        from public.group_members as member
        join public.groups as group_record
          on group_record.id = member.group_id
        where group_record.bank_partner_id = p_partner_id
      )
  ) into result;

  return coalesce(result, '{}'::jsonb);
end;
$$;
