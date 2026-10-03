import copy
import unittest
from verify_legacy_bank_scheduler_upgrade import verify, COMMAND_SHA256, NAME


def fixture():
    history = {"rows": 3, "sha256": "a" * 64}
    job = {"id": 1, "name": NAME, "schedule": "30 21 * * *", "owner": "postgres", "database": "postgres", "host": "localhost", "port": 5432, "active": True, "command_sha256": COMMAND_SHA256, "metadata_sha256": "b" * 64}
    before = {"migration_count": 142, "migration_max": "20260930100000", "business_tables": {"public.money": {"rows": 21, "sha256": "c" * 64}}, "cron_history": history, "canonical_history": history, "cron_jobs": [job], "retirement_audit": [], "postcommit_observations": [], "final_verifications": []}
    after = copy.deepcopy(before)
    after.update(migration_count=143, migration_max="20260930110000")
    after["cron_jobs"][0].update(active=False, metadata_sha256="d" * 64)
    after["retirement_audit"] = [{"job_id": 1, "job_name": NAME, "job_owner": "postgres", "database_name": "postgres", "schedule": "30 21 * * *", "command_sha256": COMMAND_SHA256, "inactive_metadata_sha256": "d" * 64, "was_active": True, "retirement_version": "20260930110000", "retirement_reason": "rwanda_momo_only_bank_scheduler_retired", "state": "paused_pending_verification", "paused_by": "postgres", "paused_at": "2026-09-30T01:00:00+00:00", "paused_xid": 10, "history_rows": 3, "history_sha256": "a" * 64}]
    after["postcommit_observations"] = [{"job_id": 1, "observed_at": "2026-09-30T01:00:01+00:00", "observed_by": "postgres", "observation_xid": 11, "readback_sha256": "e" * 64}]
    after["final_verifications"] = [{"job_id": 1, "state": "retired_verified", "verified_at": "2026-09-30T01:00:32+00:00", "verified_by": "postgres", "verification_xid": 12, "readback_sha256": "f" * 64, "observation_readback_sha256": "e" * 64, "observation_seconds": 31}]
    return before, after


class UpgradeComparatorTest(unittest.TestCase):
    def test_complete_preserves_business_history_and_job_identity(self):
        before, after = fixture()
        self.assertTrue(verify(before, after)["ok"])

    def test_pause_is_not_verified(self):
        before, after = fixture()
        after["postcommit_observations"] = []
        after["final_verifications"] = []
        self.assertTrue(verify(before, after, "paused")["ok"])
        with self.assertRaises(ValueError):
            verify(before, after)

    def test_rejects_each_distinct_corruption(self):
        def bad_job(a): a["cron_jobs"][0].update(command_sha256="0" * 64)
        def active(a): a["cron_jobs"][0].update(active=True)
        def history(a): a["cron_history"] = {"rows": 4, "sha256": "0" * 64}
        def money(a): a["business_tables"]["public.money"]["rows"] = 22
        def same_xid(a): a["final_verifications"][0]["verification_xid"] = 11
        def short_interval(a): a["final_verifications"][0].update(verified_at="2026-09-30T01:00:20+00:00", observation_seconds=19)
        def fake_interval(a): a["final_verifications"][0]["observation_seconds"] = 50
        def wrong_observation(a): a["final_verifications"][0]["observation_readback_sha256"] = "0" * 64
        def wrong_owner(a): a["retirement_audit"][0]["paused_by"] = "supabase_admin"
        def duplicate(a): a["retirement_audit"].append(copy.deepcopy(a["retirement_audit"][0]))
        def rename(a): a["cron_jobs"][0]["name"] = "different"
        def missing(a): a["cron_jobs"] = []
        def premature(a): a["final_verifications"][0]["state"] = "paused_pending_verification"
        def malformed_hash(a): a["final_verifications"][0]["readback_sha256"] = "z" * 64
        def per_job_history(a): a["canonical_history"] = {"rows": 2, "sha256": "0" * 64}
        def unbound_metadata(a): a["retirement_audit"][0]["inactive_metadata_sha256"] = "0" * 64
        for mutate in [bad_job, active, history, money, same_xid, short_interval, fake_interval, wrong_observation, wrong_owner, duplicate, rename, missing, premature, malformed_hash, per_job_history, unbound_metadata]:
            with self.subTest(mutation=mutate.__name__):
                before, after = fixture()
                mutate(after)
                with self.assertRaises(ValueError):
                    verify(before, after)


if __name__ == "__main__":
    unittest.main()
