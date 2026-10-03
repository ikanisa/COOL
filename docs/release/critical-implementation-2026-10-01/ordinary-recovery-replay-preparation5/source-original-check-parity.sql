begin;
alter table public.notification_events drop constraint notification_events_copy_length_check;
alter table public.notification_events add constraint notification_events_copy_length_check check (
    char_length(trim(title)) between 1 and 120
    and char_length(trim(body)) between 1 and 500
  ) not valid;
alter table public.provider_finality_requests drop constraint provider_finality_requests_provider_network_check;
alter table public.provider_finality_requests add constraint provider_finality_requests_provider_network_check check (
    provider_network is null or (
      char_length(provider_network) between 2 and 32 and provider_network ~ '^[a-z0-9_]+$'
    )
  );
commit;
