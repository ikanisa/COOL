begin;
create index payments_history_global_newest_idx on public.payments (posted_at desc, id) where status = 'posted' and currency = 'RWF';
create index payments_history_global_oldest_idx on public.payments (posted_at, id) where status = 'posted' and currency = 'RWF';
create index payments_history_global_highest_idx on public.payments (amount_rwf desc, posted_at desc, id) where status = 'posted' and currency = 'RWF';
create index payments_history_global_lowest_idx on public.payments (amount_rwf, posted_at desc, id) where status = 'posted' and currency = 'RWF';
commit;
