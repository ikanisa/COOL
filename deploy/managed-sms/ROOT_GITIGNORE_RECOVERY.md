# Root .gitignore incident and recovery

On 13 November 2026, while adding a managed-sms-local ignore exception, the
agent ran a write in the repository root and overwrote the pre-existing modified
`.gitignore`. The mistakenly written three-line content is preserved separately
as `ROOT_GITIGNORE_OVERWRITE.backup` (SHA-256
`03ccf230babea1c188485c31a3630d63eb6da059ad1f6ac4cc7cc66909f6feeb`).

The coordinator first directed restoration of the active-branch HEAD version as
a provisional safety baseline. Subsequent targeted recovery located the saved
prior file at:

`/Volumes/PRO-G40/Projects/COLLECT-Production/2026-11-10/runtime-io-diagnosis-001/independent-custody-001/current-changes/.gitignore`

That file is 4,969 bytes and its SHA-256 is
`92b6fcf2fd59ae62e18c7f4932d400bcc74571cc5c639a0ffcfcad4f1b60796e`, exactly
matching the pre-existing custody observation in
`independent-custody-001/result.private.json`. The active `.gitignore` was
restored from that copy and the same size and hash were verified. Its mode
remains 755. The recovered sole content difference from HEAD is the existing
`supabase/.temp/` ignore rule. The file's modification time reflects the
restoration; it was not backdated.
