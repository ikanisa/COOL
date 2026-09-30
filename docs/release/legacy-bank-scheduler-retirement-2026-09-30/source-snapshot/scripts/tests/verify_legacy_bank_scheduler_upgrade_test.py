import copy
import unittest
from verify_legacy_bank_scheduler_upgrade import COMMAND_SHA256, NAME, verify


class SchedulerUpgradeVerificationTest(unittest.TestCase):
    def setUp(self):
        job = {"id": 6, "name": NAME, "schedule": "30 21 * * *", "owner": "supabase_admin", "database": "postgres", "host": "localhost", "port": 5432, "active": True, "command_sha256": COMMAND_SHA256}
        unrelated = dict(job, id=7, name="another-job", command_sha256="b" * 64)
        self.before = {"migration_count": 142, "migration_max": "20260930100000", "business_tables": {"public.payments": {"rows": 3, "sha256": "a" * 64}}, "cron_history": {"rows": 4, "sha256": "c" * 64}, "cron_jobs": [job, unrelated], "retirement_audit": []}
        self.after = copy.deepcopy(self.before)
        self.after.update(migration_count=143, migration_max="20260930110000")
        self.after["cron_jobs"][0]["active"] = False
        self.after["retirement_audit"] = [{"job_id": 6, "job_name": NAME, "job_owner": "supabase_admin", "database_name": "postgres", "schedule": "30 21 * * *", "command_sha256": COMMAND_SHA256, "was_active": True, "retirement_version": "20260930110000", "retirement_reason": "rwanda_momo_only_bank_scheduler_retired", "retired_by": "supabase_admin", "retired_at": "2026-09-30T00:00:00+00:00"}]

    def test_accepts_only_disabled_canonical_job_with_preserved_history(self):
        self.assertEqual(verify(self.before, self.after)["retired_jobs"], 1)

    def test_rejects_changed_financial_row_hash(self):
        self.after["business_tables"]["public.payments"]["sha256"] = "d" * 64
        with self.assertRaisesRegex(ValueError, "financial"):
            verify(self.before, self.after)

    def test_rejects_history_changes(self):
        self.after["cron_history"]["rows"] = 3
        with self.assertRaisesRegex(ValueError, "history"):
            verify(self.before, self.after)

    def test_rejects_unrelated_job_changes(self):
        self.after["cron_jobs"][1]["active"] = False
        with self.assertRaisesRegex(ValueError, "beyond"):
            verify(self.before, self.after)

    def test_rejects_missing_receipt(self):
        self.after["retirement_audit"] = []
        with self.assertRaisesRegex(ValueError, "coverage"):
            verify(self.before, self.after)

    def test_rejects_missing_job(self):
        self.after["cron_jobs"].pop(0)
        with self.assertRaisesRegex(ValueError, "removed"):
            verify(self.before, self.after)

    def test_rejects_wrong_original_identity(self):
        self.before["cron_jobs"][0]["command_sha256"] = "e" * 64
        with self.assertRaisesRegex(ValueError, "command"):
            verify(self.before, self.after)

    def test_rejects_forged_previous_activity(self):
        self.after["retirement_audit"][0]["was_active"] = False
        with self.assertRaisesRegex(ValueError, "activity"):
            verify(self.before, self.after)

    def test_accepts_already_disabled_original_job(self):
        self.before["cron_jobs"][0]["active"] = False
        self.after["retirement_audit"][0]["was_active"] = False
        self.assertTrue(verify(self.before, self.after)["ok"])


if __name__ == "__main__":
    unittest.main()
