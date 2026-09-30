create role anon;
create role authenticated;
create role service_role;
create schema auth;
create schema extensions;
create schema collect_hybrid;
create extension pgcrypto with schema extensions;
create table auth.users(
  id uuid primary key,
  phone text,
  phone_confirmed_at timestamptz,
  deleted_at timestamptz
);
create table public.profiles(
  id uuid primary key,
  country_code text,
  momo_number text
);
create table public.payment_intents(
  id uuid primary key,
  contributor_user_id uuid,
  collection_id uuid,
  sender_phone_hash text,
  status text
);
create table public.parsed_payment_events(
  id uuid primary key,
  sender_phone_hash text
);
create table public.payments(
  id uuid primary key,
  payment_intent_id uuid references public.payment_intents(id),
  parsed_event_id uuid references public.parsed_payment_events(id),
  contributor_user_id uuid,
  collection_id uuid,
  receiver_user_id uuid,
  receiver_momo_number_hash text,
  amount_rwf bigint,
  currency text,
  transaction_id text,
  provider_network text,
  member_record_id uuid,
  status text
);

insert into auth.users(id,phone,phone_confirmed_at) values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1','250788123456',now()),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1','250788123458',now());
insert into public.profiles(id,country_code,momo_number) values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1','RW','0788123456'),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1','RW','0788123457');
insert into public.payment_intents(
  id,contributor_user_id,collection_id,sender_phone_hash,status
) values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1',
   'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1',
   'cccccccc-cccc-4ccc-8ccc-ccccccccccc1',
   encode(extensions.digest('+250788123456','sha256'),'hex'),'pending'),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',
   'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',
   'cccccccc-cccc-4ccc-8ccc-ccccccccccc1',
   encode(extensions.digest('+250788123457','sha256'),'hex'),'pending'),
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4',
   'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1',
   'cccccccc-cccc-4ccc-8ccc-ccccccccccc1',
   encode(extensions.digest('+250788123456','sha256'),'hex'),'matched'),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb4',
   'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',
   'cccccccc-cccc-4ccc-8ccc-ccccccccccc1',
   encode(extensions.digest('+250788123457','sha256'),'hex'),'matched');
insert into public.parsed_payment_events(id,sender_phone_hash) values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1',
   encode(extensions.digest('+250788123456','sha256'),'hex')),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',
   encode(extensions.digest('+250788123457','sha256'),'hex')),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb3',
   encode(extensions.digest('+250788123457','sha256'),'hex'));
insert into public.payments(
  id,payment_intent_id,parsed_event_id,collection_id,contributor_user_id,status
) values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2',
   'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4',
   'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1',
   'cccccccc-cccc-4ccc-8ccc-ccccccccccc1',
   'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1','review'),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2',
   'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb4',
   'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',
   'cccccccc-cccc-4ccc-8ccc-ccccccccccc1',
   'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1','review'),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb3',
   'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb4',
   'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb3',
   'cccccccc-cccc-4ccc-8ccc-ccccccccccc1',
   'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1','posted');
