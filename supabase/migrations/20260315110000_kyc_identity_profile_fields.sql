alter table public.users
  add column if not exists date_of_birth date,
  add column if not exists national_id_number text,
  add column if not exists kyc_id_photo_url text,
  add column if not exists kyc_document_type text,
  add column if not exists kyc_extracted_at timestamptz,
  add column if not exists kyc_extraction_provider text,
  add column if not exists identity_data jsonb not null default '{}'::jsonb;

alter table public.users
  drop constraint if exists users_kyc_document_type_check;

alter table public.users
  add constraint users_kyc_document_type_check
    check (
      kyc_document_type is null
      or kyc_document_type in (
        'national_id',
        'passport',
        'driving_license',
        'residence_permit',
        'other'
      )
    );

create index if not exists idx_users_kyc_document_type
  on public.users (kyc_document_type);

create index if not exists idx_users_kyc_extracted_at
  on public.users (kyc_extracted_at desc);
