-- ============================================================================
-- Cool App - MoMo SMS retention minimization and redaction
-- ============================================================================

alter table public.momo_sms_raw
  add column if not exists sms_body_redacted_at timestamptz;

comment on column public.momo_sms_raw.sms_body_redacted_at is
  'When the original raw SMS body was replaced with a redacted placeholder after successful parse + reconciliation retention expiry.';

alter table public.momo_parse_attempts
  add column if not exists payloads_redacted_at timestamptz;

comment on column public.momo_parse_attempts.payloads_redacted_at is
  'When stored AI request/response payloads were cleared to minimize long-term retention of sensitive SMS context.';

create or replace function public.redact_momo_sms_artifacts_due(
  p_raw_retention interval default interval '14 days',
  p_attempt_retention interval default interval '14 days',
  p_batch_size integer default 500
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_now timestamptz := now();
  v_batch_size integer := greatest(coalesce(p_batch_size, 500), 1);
  v_raw_redacted integer := 0;
  v_attempt_payloads_redacted integer := 0;
begin
  with raw_candidates as (
    select raw.id
      from public.momo_sms_raw raw
      join public.momo_sms_parsed parsed
        on parsed.raw_sms_id = raw.id
       and parsed.parse_status = 'parsed'
      join public.momo_reconciliations reconciliation
        on reconciliation.parsed_sms_id = parsed.id
       and reconciliation.match_status = 'matched'
     where raw.sms_body_redacted_at is null
       and raw.parse_status = 'parsed'
       and raw.created_at <= v_now - p_raw_retention
     order by raw.created_at asc
     limit v_batch_size
  )
  update public.momo_sms_raw raw
     set sms_body = '[REDACTED AFTER PARSE + MATCHED RECONCILIATION]',
         sms_body_redacted_at = v_now,
         updated_at = v_now
    from raw_candidates
   where raw.id = raw_candidates.id;

  get diagnostics v_raw_redacted = row_count;

  with attempt_candidates as (
    select attempt.id
      from public.momo_parse_attempts attempt
      join public.momo_sms_raw raw
        on raw.id = attempt.raw_sms_id
     where attempt.payloads_redacted_at is null
       and raw.created_at <= v_now - p_attempt_retention
       and raw.parse_status in ('parsed', 'failed', 'ignored')
     order by attempt.created_at asc
     limit v_batch_size
  )
  update public.momo_parse_attempts attempt
     set request_payload = '{}'::jsonb,
         response_payload = '{}'::jsonb,
         payloads_redacted_at = v_now
    from attempt_candidates
   where attempt.id = attempt_candidates.id;

  get diagnostics v_attempt_payloads_redacted = row_count;

  return jsonb_build_object(
    'raw_redacted',
    v_raw_redacted,
    'attempt_payloads_redacted',
    v_attempt_payloads_redacted,
    'executed_at',
    v_now,
    'raw_retention_days',
    extract(day from p_raw_retention),
    'attempt_retention_days',
    extract(day from p_attempt_retention),
    'batch_size',
    v_batch_size
  );
end;
$function$;

revoke all on function public.redact_momo_sms_artifacts_due(interval, interval, integer)
  from public;

grant execute on function public.redact_momo_sms_artifacts_due(interval, interval, integer)
  to service_role;

grant execute on function public.redact_momo_sms_artifacts_due(interval, interval, integer)
  to postgres;

do $$
declare
  v_existing_job_id bigint;
begin
  if exists (
    select 1
      from pg_namespace
     where nspname = 'cron'
  ) then
    select jobid
      into v_existing_job_id
      from cron.job
     where jobname = 'redact-momo-sms-artifacts-daily'
     limit 1;

    if v_existing_job_id is not null then
      perform cron.unschedule(v_existing_job_id);
    end if;

    perform cron.schedule(
      'redact-momo-sms-artifacts-daily',
      '17 2 * * *',
      $cron$
        select public.redact_momo_sms_artifacts_due(
          interval '14 days',
          interval '14 days',
          500
        );
      $cron$
    );
  end if;
end;
$$;
