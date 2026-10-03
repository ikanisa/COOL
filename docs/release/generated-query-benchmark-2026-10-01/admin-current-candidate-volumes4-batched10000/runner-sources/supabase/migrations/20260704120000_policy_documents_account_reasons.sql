begin;

create table if not exists policy_documents (
  id uuid primary key default gen_random_uuid(),
  kind text not null check (kind in ('privacy', 'terms')),
  locale text not null default 'en' check (locale ~ '^[a-z]{2}(-[A-Z]{2})?$'),
  version text not null check (version ~ '^[a-zA-Z0-9_.:-]+$'),
  title text not null,
  summary text,
  status text not null default 'draft'
    check (status in ('draft', 'published', 'archived')),
  effective_at timestamptz not null default now(),
  published_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  updated_by uuid references profiles(id) on delete set null,
  updated_reason text,
  unique (kind, locale, version)
);

create table if not exists policy_document_sections (
  id uuid primary key default gen_random_uuid(),
  policy_document_id uuid not null references policy_documents(id) on delete cascade,
  section_key text not null check (section_key ~ '^[a-z0-9_.-]+$'),
  title text not null,
  body text not null,
  display_order integer not null default 100,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  updated_by uuid references profiles(id) on delete set null,
  updated_reason text,
  unique (policy_document_id, section_key)
);

create table if not exists policy_acceptance_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id) on delete cascade,
  policy_document_id uuid not null references policy_documents(id) on delete restrict,
  accepted_version text not null,
  accepted_locale text not null default 'en',
  accepted_at timestamptz not null default now(),
  source text not null default 'mobile'
    check (source in ('mobile', 'admin', 'public_web', 'support')),
  metadata jsonb not null default '{}'::jsonb
);

create table if not exists account_request_reason_options (
  key text not null check (key ~ '^[a-z0-9_.-]+$'),
  request_type text not null default 'account_deletion'
    check (request_type in ('account_deletion', 'data_correction')),
  locale text not null default 'en' check (locale ~ '^[a-z]{2}(-[A-Z]{2})?$'),
  label text not null,
  description text,
  display_order integer not null default 100,
  enabled boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  updated_by uuid references profiles(id) on delete set null,
  updated_reason text,
  primary key (request_type, locale, key)
);

create index if not exists policy_documents_active_lookup_idx
  on policy_documents (kind, locale, status, effective_at desc, version);

create index if not exists policy_document_sections_order_idx
  on policy_document_sections (policy_document_id, display_order, section_key);

create index if not exists policy_acceptance_events_user_idx
  on policy_acceptance_events (user_id, accepted_at desc);

create index if not exists account_request_reason_options_lookup_idx
  on account_request_reason_options (
    request_type,
    locale,
    enabled,
    display_order,
    key
  );

alter table policy_documents enable row level security;
alter table policy_document_sections enable row level security;
alter table policy_acceptance_events enable row level security;
alter table account_request_reason_options enable row level security;

drop policy if exists "policy documents public published read" on policy_documents;
create policy "policy documents public published read"
on policy_documents for select to anon, authenticated
using (status = 'published' and effective_at <= now());

drop policy if exists "policy documents admin manage" on policy_documents;
create policy "policy documents admin manage"
on policy_documents for all to authenticated
using (public.has_admin_permission('settings.manage', (select auth.uid())))
with check (public.has_admin_permission('settings.manage', (select auth.uid())));

drop policy if exists "policy sections public published read" on policy_document_sections;
create policy "policy sections public published read"
on policy_document_sections for select to anon, authenticated
using (
  exists (
    select 1
    from policy_documents pd
    where pd.id = policy_document_sections.policy_document_id
      and pd.status = 'published'
      and pd.effective_at <= now()
  )
);

drop policy if exists "policy sections admin manage" on policy_document_sections;
create policy "policy sections admin manage"
on policy_document_sections for all to authenticated
using (public.has_admin_permission('settings.manage', (select auth.uid())))
with check (public.has_admin_permission('settings.manage', (select auth.uid())));

drop policy if exists "policy acceptance own read" on policy_acceptance_events;
create policy "policy acceptance own read"
on policy_acceptance_events for select to authenticated
using (
  user_id = (select auth.uid())
  or public.has_admin_permission('audit.read', (select auth.uid()))
);

drop policy if exists "policy acceptance own insert" on policy_acceptance_events;
create policy "policy acceptance own insert"
on policy_acceptance_events for insert to authenticated
with check (user_id = (select auth.uid()));

drop policy if exists "account request reasons public enabled read" on account_request_reason_options;
create policy "account request reasons public enabled read"
on account_request_reason_options for select to anon, authenticated
using (enabled);

drop policy if exists "account request reasons admin manage" on account_request_reason_options;
create policy "account request reasons admin manage"
on account_request_reason_options for all to authenticated
using (public.has_admin_permission('settings.manage', (select auth.uid())))
with check (public.has_admin_permission('settings.manage', (select auth.uid())));

create or replace function get_active_policy_document(
  p_kind text,
  p_locale text default 'en'
)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with selected_document as (
    select pd.*
    from policy_documents pd
    where pd.kind = lower(trim(p_kind))
      and pd.locale in (coalesce(nullif(trim(p_locale), ''), 'en'), 'en')
      and pd.status = 'published'
      and pd.effective_at <= now()
    order by
      case when pd.locale = coalesce(nullif(trim(p_locale), ''), 'en') then 0 else 1 end,
      pd.effective_at desc,
      pd.version desc
    limit 1
  )
  select coalesce(
    (
      select jsonb_build_object(
        'id', sd.id,
        'kind', sd.kind,
        'locale', sd.locale,
        'version', sd.version,
        'title', sd.title,
        'summary', sd.summary,
        'effective_at', sd.effective_at,
        'sections', coalesce((
          select jsonb_agg(
            jsonb_build_object(
              'key', pds.section_key,
              'title', pds.title,
              'body', pds.body,
              'display_order', pds.display_order
            )
            order by pds.display_order, pds.section_key
          )
          from policy_document_sections pds
          where pds.policy_document_id = sd.id
        ), '[]'::jsonb)
      )
      from selected_document sd
    ),
    '{}'::jsonb
  );
$$;

create or replace function list_account_request_reasons(
  p_request_type text default 'account_deletion',
  p_locale text default 'en'
)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with selected_reasons as (
    select distinct on (aro.key)
      aro.key,
      aro.request_type,
      aro.locale,
      aro.label,
      aro.description,
      aro.display_order
    from account_request_reason_options aro
    where aro.request_type = coalesce(nullif(trim(p_request_type), ''), 'account_deletion')
      and aro.locale in (coalesce(nullif(trim(p_locale), ''), 'en'), 'en')
      and aro.enabled
    order by
      aro.key,
      case when aro.locale = coalesce(nullif(trim(p_locale), ''), 'en') then 0 else 1 end,
      aro.display_order
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'key', sr.key,
        'request_type', sr.request_type,
        'locale', sr.locale,
        'label', sr.label,
        'description', sr.description,
        'display_order', sr.display_order
      )
      order by sr.display_order, sr.key
    ),
    '[]'::jsonb
  )
  from selected_reasons sr;
$$;

create or replace function record_policy_acceptance(
  p_policy_kind text,
  p_policy_version text default null,
  p_locale text default 'en',
  p_source text default 'mobile'
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  policy_row policy_documents%rowtype;
  acceptance_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select *
  into policy_row
  from policy_documents pd
  where pd.kind = lower(trim(p_policy_kind))
    and pd.locale in (coalesce(nullif(trim(p_locale), ''), 'en'), 'en')
    and (p_policy_version is null or pd.version = trim(p_policy_version))
    and pd.status = 'published'
    and pd.effective_at <= now()
  order by
    case when pd.locale = coalesce(nullif(trim(p_locale), ''), 'en') then 0 else 1 end,
    pd.effective_at desc,
    pd.version desc
  limit 1;

  if policy_row.id is null then
    raise exception 'Active policy document not found';
  end if;

  insert into policy_acceptance_events (
    user_id,
    policy_document_id,
    accepted_version,
    accepted_locale,
    source
  )
  values (
    auth.uid(),
    policy_row.id,
    policy_row.version,
    policy_row.locale,
    coalesce(nullif(trim(p_source), ''), 'mobile')
  )
  returning id into acceptance_id;

  perform create_audit_log(
    'policy.accepted',
    'policy_document',
    policy_row.id,
    jsonb_build_object(
      'acceptance_id', acceptance_id,
      'kind', policy_row.kind,
      'version', policy_row.version,
      'locale', policy_row.locale
    )
  );

  return acceptance_id;
end;
$$;

revoke execute on function get_active_policy_document(text, text) from public, anon, authenticated;
revoke execute on function list_account_request_reasons(text, text) from public, anon, authenticated;
revoke execute on function record_policy_acceptance(text, text, text, text) from public, anon, authenticated;
grant execute on function get_active_policy_document(text, text) to anon, authenticated;
grant execute on function list_account_request_reasons(text, text) to anon, authenticated;
grant execute on function record_policy_acceptance(text, text, text, text) to authenticated;

create or replace function audit_policy_runtime_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  metadata_key text;
begin
  metadata_key := case
    when tg_op = 'DELETE' then coalesce(
      to_jsonb(old)->>'kind',
      to_jsonb(old)->>'section_key',
      to_jsonb(old)->>'key',
      to_jsonb(old)->>'id'
    )
    else coalesce(
      to_jsonb(new)->>'kind',
      to_jsonb(new)->>'section_key',
      to_jsonb(new)->>'key',
      to_jsonb(new)->>'id'
    )
  end;

  if auth.uid() is not null then
    perform create_audit_log(
      'policy_runtime.' || lower(tg_op),
      tg_table_name,
      null,
      jsonb_build_object('key', metadata_key)
    );
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

revoke execute on function audit_policy_runtime_change() from public, anon, authenticated;
grant execute on function audit_policy_runtime_change() to service_role;

drop trigger if exists audit_policy_runtime_change_trigger on policy_documents;
create trigger audit_policy_runtime_change_trigger
after insert or update or delete on policy_documents
for each row execute function audit_policy_runtime_change();

drop trigger if exists audit_policy_runtime_change_trigger on policy_document_sections;
create trigger audit_policy_runtime_change_trigger
after insert or update or delete on policy_document_sections
for each row execute function audit_policy_runtime_change();

drop trigger if exists audit_policy_runtime_change_trigger on account_request_reason_options;
create trigger audit_policy_runtime_change_trigger
after insert or update or delete on account_request_reason_options
for each row execute function audit_policy_runtime_change();

drop trigger if exists app_realtime_event_trigger on policy_documents;
create trigger app_realtime_event_trigger
after insert or update or delete on policy_documents
for each row execute function emit_app_realtime_event('settings');

drop trigger if exists app_realtime_event_trigger on policy_document_sections;
create trigger app_realtime_event_trigger
after insert or update or delete on policy_document_sections
for each row execute function emit_app_realtime_event('settings');

drop trigger if exists app_realtime_event_trigger on account_request_reason_options;
create trigger app_realtime_event_trigger
after insert or update or delete on account_request_reason_options
for each row execute function emit_app_realtime_event('settings');

revoke all on policy_documents from anon, authenticated;
revoke all on policy_document_sections from anon, authenticated;
revoke all on policy_acceptance_events from anon, authenticated;
revoke all on account_request_reason_options from anon, authenticated;
grant select on policy_documents to anon, authenticated;
grant select on policy_document_sections to anon, authenticated;
grant select, insert on policy_acceptance_events to authenticated;
grant select on account_request_reason_options to anon, authenticated;
grant insert, update, delete on policy_documents to authenticated;
grant insert, update, delete on policy_document_sections to authenticated;
grant insert, update, delete on account_request_reason_options to authenticated;

with upserted as (
  insert into policy_documents (
    kind,
    locale,
    version,
    title,
    summary,
    status,
    effective_at,
    published_at
  )
  values
    (
      'privacy',
      'en',
      '2026-07-04',
      'Privacy Policy',
      'Collect privacy, payment evidence, support, and retention rules.',
      'published',
      '2026-07-04 00:00:00+00',
      '2026-07-04 00:00:00+00'
    ),
    (
      'terms',
      'en',
      '2026-07-04',
      'Terms & Conditions',
      'Collect group, MoMo payment, owner, dispute, and acceptable-use terms.',
      'published',
      '2026-07-04 00:00:00+00',
      '2026-07-04 00:00:00+00'
    )
  on conflict (kind, locale, version) do update
  set title = excluded.title,
      summary = excluded.summary,
      status = excluded.status,
      effective_at = excluded.effective_at,
      published_at = excluded.published_at,
      updated_at = now()
  returning id, kind
)
insert into policy_document_sections (
  policy_document_id,
  section_key,
  title,
  body,
  display_order
)
select
  upserted.id,
  seeded.section_key,
  seeded.title,
  seeded.body,
  seeded.display_order
from upserted
join (
  values
    (
      'privacy',
      'data_we_collect',
      'Data we collect',
      'Collect stores your Collect ID, WhatsApp sign-in phone, optional MoMo account, group memberships, group profile details, payment requests, contribution records, and permission status. Group owners may allow Collect to process MoMo SMS evidence for payment matching.',
      10
    ),
    (
      'privacy',
      'how_we_use_data',
      'How we use data',
      'We use this data to create and join groups, verify contributions, keep ledgers accurate, show notifications, prevent misuse, provide support, and maintain audit records for payment disputes.',
      20
    ),
    (
      'privacy',
      'what_stays_private',
      'What stays private',
      'Receiver MoMo numbers, private confirmation text, sign-in phones, and support evidence are not shown on public group cards or public share links. Member-facing screens use Collect IDs and safe payment status.',
      30
    ),
    (
      'privacy',
      'sharing',
      'Sharing',
      'We share only what is needed with service providers that operate authentication, hosting, storage, messaging, support, analytics, or payment verification. We do not sell personal data.',
      40
    ),
    (
      'privacy',
      'choices_and_retention',
      'Choices and retention',
      'You can update your MoMo account, request account deletion, leave groups where supported, and contact support for correction requests. Ledger records may be retained where needed for audit, security, dispute, and legal reasons.',
      50
    ),
    (
      'terms',
      'using_collect',
      'Using Collect',
      'Collect helps groups organize contributions, create payment requests, scan or share group QR codes, and maintain a verified contribution ledger. You must use accurate group, receiver, and payment information.',
      10
    ),
    (
      'terms',
      'momo_payments',
      'MoMo payments',
      'Payments are approved outside Collect through MoMo or the mobile money flow shown on your device. Collect does not ask for payment credentials or sign-in secrets.',
      20
    ),
    (
      'terms',
      'group_ownership',
      'Group ownership',
      'Group owners are responsible for group profile details, receiver setup, recurring settings, member management, and permission readiness. Android SMS access may be required for owner-side payment verification.',
      30
    ),
    (
      'terms',
      'disputes_and_corrections',
      'Disputes and corrections',
      'If a payment is missing, duplicated, incorrect, or needs review, contact support. Collect may use payment status, transaction references, SMS evidence, and audit logs to investigate.',
      40
    ),
    (
      'terms',
      'acceptable_use',
      'Acceptable use',
      'Do not create misleading groups, impersonate another person, abuse QR links, submit false payment claims, or use Collect to request illegal or unauthorized payments.',
      50
    )
) as seeded(kind, section_key, title, body, display_order)
on seeded.kind = upserted.kind
on conflict (policy_document_id, section_key) do update
set title = excluded.title,
    body = excluded.body,
    display_order = excluded.display_order,
    updated_at = now();

insert into account_request_reason_options (
  key,
  request_type,
  locale,
  label,
  display_order,
  enabled
)
values
  (
    'no_longer_use_collect',
    'account_deletion',
    'en',
    'I no longer use Collect',
    10,
    true
  ),
  (
    'joined_by_mistake',
    'account_deletion',
    'en',
    'I joined by mistake',
    20,
    true
  ),
  (
    'prefer_not_to_keep_data',
    'account_deletion',
    'en',
    'I prefer not to keep my data',
    30,
    true
  )
on conflict (request_type, locale, key) do update
set label = excluded.label,
    display_order = excluded.display_order,
    enabled = excluded.enabled,
    updated_at = now();

commit;
