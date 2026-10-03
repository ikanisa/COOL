begin;

update public.payment_entrypoints
set code = regexp_replace(code, '^\*182\*8\*1\*', '*182**8*1*'),
    display_code = regexp_replace(
      display_code,
      '^\*182\*8\*1\*',
      '*182**8*1*'
    ),
    updated_at = now()
where country_code = 'RW'
  and network = 'mtn_momo'
  and code ~ '^\*182\*8\*1\*[0-9]{4,9}\*[1-9][0-9]*#$';

commit;
