set application_name='privacy_qa_revocation_wins_a';set statement_timeout='15s';begin;delete from auth.sessions where id='99870000-0000-4000-8000-000000000106';select pg_sleep(3);commit;
