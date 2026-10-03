The initial private typecheck bootstrap failed because its mirror lacked the
relative Supabase handler/contract inputs used by existing MCP tests. It also
found one unknown-to-string narrowing error in the new context validator.
Those transitive inputs were copied privately and the narrowing corrected.
The tool transcript retains that first failure; typecheck-02.stdout/stderr
retain the remaining narrowing/test-dependency errors. No canonical source was
modified. typecheck-03 then passed.

recovery-tests-01.stdout/stderr retain the first case failures. Their cause was
comparison of profile identity JSON key order with Python's sorted preparation
manifest. The pure validator now compares the three exact identity fields,
matching the active loader. recovery-tests-02 proved the corrected CLI and
historical UID behavior. recovery-tests-03 retains the complete 22-case pass
before the final two persistence/source-removal cases were added.
