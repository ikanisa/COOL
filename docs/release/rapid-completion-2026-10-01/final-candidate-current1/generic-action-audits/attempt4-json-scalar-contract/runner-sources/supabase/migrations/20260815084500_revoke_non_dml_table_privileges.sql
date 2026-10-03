begin;

-- Mobile and browser clients need only the explicitly enumerated DML grants
-- protected by RLS. Schema-level REFERENCES, TRIGGER, and TRUNCATE privileges
-- are never part of the client contract and can bypass intended mutation paths.
revoke references, trigger, truncate on all tables in schema public
  from anon, authenticated;

alter default privileges in schema public
  revoke references, trigger, truncate on tables from anon, authenticated;

commit;
