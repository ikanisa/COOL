update public.groups as g
set institution_id = p.id
from public.partners as p
where p.category = 'bank'
  and nullif(btrim(coalesce(g.institution_id, '')), '') is null
  and lower(btrim(coalesce(g.bank_partner, ''))) = lower(btrim(p.name));

create index if not exists idx_groups_institution_id
  on public.groups (institution_id);
