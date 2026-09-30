# Historical bank and diaspora upgrade rehearsal — 29 September 2026

**Local result:** the isolated predecessor-to-current replay passed. The
pre-cutover synthetic bank and foreign-profile fingerprints matched exactly
after migration 134. Fourteen rollback-only scope and grant assertions passed.
This is evidence for D09, S08 and X02; all three acceptance items remain open.

The dedicated Supabase CLI project was `collect_historical_bank_qa_20260929`
(PostgreSQL 17.6, database port 55622). Docker labels, compose project, local
config and port binding were checked before replay. The fixture contained no
customer data or provider transaction, and cron jobs were disabled. The
[predecessor report](predecessor-replay.json) records **126/126** migrations
through `20260914213600`. The [seed](../../../scripts/tests/historical_bank_upgrade_seed.sql)
then committed a synthetic GB/GBP profile, RWF group with the historical
`diaspora_enabled` flag, one EUR 2,100-minor-unit bank intent, its matching
bank transaction, allocation and owner membership. This models the historical
schema in which group ledger currency was RWF and the bank records held EUR.

The [successor report](successor-replay.json) records the next **8/8**
migrations, from the Rwanda-only cutover `20260925190000` through
`20260929110000`; the database then held 134 migrations, two synthetic Auth
users and exactly one bank intent, transaction and allocation. The
[read-only fingerprint query](../../../scripts/tests/historical_bank_upgrade_snapshot.sql)
covered all four bank tables plus the foreign profile, diaspora group and
owner membership. Its [before](predecessor-fingerprints.json) and
[after](successor-fingerprints.json) output is byte-identical (SHA-256
`992b04ca8e73c15754d2e9a583d85d660af88b42e0082a446d8afab7273db3fd`).
The same match was checked again after UAT.

The [rollback-only UAT](../../../scripts/tests/historical_bank_upgrade_uat.sql)
passed [14 assertions](uat-result.txt): retained profile/group/bank relations
and EUR values; denial of retired bank tables and RPCs to API roles; rejection
of new foreign-profile and diaspora-group writes; exclusion of the historical
group and bank intent from active member collections, balances and intents;
retired profile overloads absent and an older foreign-country profile request
rejected before writing.
The fixture also contains two ordinary public seed groups, so active member
lists are correctly tested for absence of the retired group, not for emptiness.
No UAT write was committed; post-UAT counts and fingerprints matched.

The checked-in [local fixture config](../../../scripts/tests/fixtures/historical_bank_supabase_config.toml)
is the one used for this replay (SHA-256
`69548e8b1e3ada9c967cab5b8ec6c1d92178fcc9479946d64ef810b08da01f44`).
To reproduce on a machine with Docker and Supabase CLI 2.84.2, create only the
named `.cache/historical-bank-upgrade-20260929/supabase` workdir, copy that
config as `config.toml`, and start it with `supabase start --workdir
.cache/historical-bank-upgrade-20260929 --yes`. Run
`ruby scripts/tests/clean_migration_replay.rb --historical-bank-qa
--through-version=20260914213600 --with-synthetic-owner` before the seed SQL;
capture the snapshot, then run the same replay script with
`--historical-bank-qa --continue-after=20260914213600`, capture the snapshot
again and compare its output. Finally run the UAT SQL against the named
`supabase_db_collect_historical_bank_qa_20260929` container. The replay tool
checks project identity, compose labels, workdir config, port and predecessor
migration count before writing. Keep CLI start output in ignored local storage:
it can contain local API keys.

The earlier [current-schema boundary test](../historical-bank-boundary-2026-09-29/README.md)
did not cover a real pre-cutover bank record. This rehearsal closes that local
evidence gap. It does **not** prove representative customer-history migration,
incompatible installed clients, governed historical audit access, hosted
grants/RLS, signed artifacts, provider finality, restore/roll-forward, or a
production decision. Those remain in the [task register](../PRODUCTION_READINESS_REMAINING_TASKS_2026-09-28.md).

Evidence SHA-256: seed
`54e1840eb7233af4b8f9810a8c61fefdbc838922d9b0ae87557dedb702e32025`;
snapshot query
`ca64cea60597751a35e51e0b33bbb122ae0db309c2598447ced1edb0d4e32f10`;
UAT
`b18a8ff99f1d158a32cf5c8cd8bbca7ae697267f6c5855899cc023d86315c8e8`;
predecessor report
`4f57e03a64c80fec1131d99d87f2603b1df8af63655f0fd2f8d8c3691576392d`;
successor report
`632d046c0ef71ecf47ea1308c6d84a44f6767bbebbc411e8fa2dad0f13737e31`;
UAT result
`03682df754b62b4d2c1f1807ebb15ee47ca0f9fc6e4f77de6bff4806d38e1dab`.
