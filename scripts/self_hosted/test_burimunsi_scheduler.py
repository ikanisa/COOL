import io
import json
import os
from pathlib import Path
import tempfile
import unittest

from scripts.self_hosted.burimunsi_scheduler import endpoint, tick


class Response(io.BytesIO):
    status = 200
    def __enter__(self): return self
    def __exit__(self, *args): self.close()


class Opener:
    def __init__(self, source, canonical=False, auto=None, ledger=None):
        self.source, self.requests, self.canonical, self.auto, self.ledger = source, [], canonical, auto, ledger
    def open(self, request, timeout):
        self.requests.append((request, timeout))
        if len(self.requests) == 1:
            return Response(json.dumps({'database': 'available', 'release': self.source}).encode())
        result = {}
        if self.auto is not None: result['native_auto_processing'] = {'status': self.auto}
        if self.ledger is not None: result['native_sms_ledger'] = {'status': self.ledger}
        if self.canonical: result['canonical_processing'] = {'status': 'complete'}
        return Response(json.dumps(result).encode())


class SchedulerTests(unittest.TestCase):
    def test_only_local_jobs_endpoint_is_allowed(self):
        endpoint('http://127.0.0.1:55101/functions/v1/collect-jobs')
        for value in ('https://127.0.0.1:55101/functions/v1/collect-jobs',
                      'http://example.com:55101/functions/v1/collect-jobs',
                      'http://127.0.0.1:55101/functions/v1/collect-jobs?secret=x',
                      'http://localhost:55101/functions/v1/collect-jobs'):
            with self.assertRaises(ValueError): endpoint(value)

    def test_tick_requires_matching_live_release_and_uses_private_job_token(self):
        with tempfile.TemporaryDirectory() as root:
            release = Path(root); (release / 'private').mkdir()
            (release / 'release.json').write_text(json.dumps({'source_sha256': 'a' * 64}))
            keys = release / 'private' / 'keys.json'
            keys.write_text(json.dumps({'COLLECT_JOB_TOKEN': 'x' * 48})); os.chmod(keys, 0o600)
            opener = Opener('a' * 64)
            result = tick(release, 'http://127.0.0.1:55101/functions/v1/collect-jobs', opener)
            self.assertEqual(result['status'], 'complete')
            self.assertEqual(len(opener.requests), 2)
            self.assertEqual(opener.requests[1][0].get_header('Authorization'), 'Bearer ' + 'x' * 48)
            self.assertNotIn('x' * 48, json.dumps(result))
            wrong = Opener('b' * 64)
            with self.assertRaises(ValueError): tick(release, 'http://127.0.0.1:55101/functions/v1/collect-jobs', wrong)
            self.assertEqual(len(wrong.requests), 1)
            os.chmod(keys, 0o644)
            with self.assertRaises(ValueError): tick(release, 'http://127.0.0.1:55101/functions/v1/collect-jobs', Opener('a' * 64))

    def test_enabled_canonical_tick_carries_only_the_bound_receipt_contract(self):
        with tempfile.TemporaryDirectory() as root:
            release = Path(root); (release / 'private').mkdir()
            (release / 'release.json').write_text(json.dumps({'source_sha256': 'a' * 64}))
            keys = release / 'private' / 'keys.json'
            keys.write_text(json.dumps({'COLLECT_JOB_TOKEN': 'x' * 48})); os.chmod(keys, 0o600)
            settings = release / 'private' / 'provider-settings.json'
            values = {'BURIMUNSI_CANONICAL_SCHEDULER_ENABLED':'true', 'COLLECT_JOBS_MODE':'receipt_processing_v1',
                      'MOMO_PROCESSING_PAUSED':'false', 'MOMO_AI_MODEL':'synthetic-model',
                      'COLLECT_JOBS_PROCESSING_APPROVAL_SHA256':'b'*64,
                      'BURIMUNSI_CANONICAL_SCHEDULER_MANAGED_ACCESS_TOKEN':'must-not-be-sent'}
            settings.write_text(json.dumps(values)); os.chmod(settings, 0o600)
            opener = Opener('a'*64, canonical=True)
            result = tick(release, 'http://127.0.0.1:55101/functions/v1/collect-jobs', opener)
            body = json.loads(opener.requests[1][0].data)
            self.assertEqual(body['processing_admission'], {'contract':'collect.receipt-processing.v1',
                'source_sha256':'a'*64,'approval_sha256':'b'*64,'model_id':'synthetic-model','batch_limit':1})
            self.assertNotIn('must-not-be-sent', json.dumps(body))
            self.assertEqual(result['canonical_processing'], 'complete')
            values['MOMO_PROCESSING_PAUSED'] = 'true'; settings.write_text(json.dumps(values))
            denied = Opener('a'*64, canonical=True)
            with self.assertRaises(ValueError): tick(release, 'http://127.0.0.1:55101/functions/v1/collect-jobs', denied)
            self.assertEqual(len(denied.requests), 1)

    def test_native_sms_success_requires_the_ledger_drain_to_complete(self):
        with tempfile.TemporaryDirectory() as root:
            release = Path(root); (release / 'private').mkdir()
            (release / 'release.json').write_text(json.dumps({'source_sha256': 'a' * 64}))
            keys = release / 'private' / 'keys.json'
            keys.write_text(json.dumps({'COLLECT_JOB_TOKEN': 'x' * 48})); keys.chmod(0o600)
            settings = release / 'private' / 'provider-settings.json'
            settings.write_text(json.dumps({'BURIMUNSI_NATIVE_AUTO_TRANSACTIONS_ENABLED':'true'})); settings.chmod(0o600)
            for state in (None, 'unconfirmed', 'disabled'):
                with self.assertRaises(ValueError):
                    tick(release, 'http://127.0.0.1:55101/functions/v1/collect-jobs', Opener('a'*64, auto='complete', ledger=state))
            for state in (None, 'unconfirmed', 'disabled'):
                with self.assertRaises(ValueError):
                    tick(release, 'http://127.0.0.1:55101/functions/v1/collect-jobs', Opener('a'*64, auto=state, ledger='complete'))
            result = tick(release, 'http://127.0.0.1:55101/functions/v1/collect-jobs', Opener('a'*64, auto='complete', ledger='complete'))
            self.assertEqual(result['native_auto_processing'], 'complete')
            self.assertEqual(result['native_sms_ledger'], 'complete')

    def test_disabled_native_tick_rejects_runtime_configuration_drift(self):
        with tempfile.TemporaryDirectory() as root:
            release = Path(root); (release / 'private').mkdir()
            (release / 'release.json').write_text(json.dumps({'source_sha256': 'a' * 64}))
            keys = release / 'private' / 'keys.json'
            keys.write_text(json.dumps({'COLLECT_JOB_TOKEN': 'x' * 48})); keys.chmod(0o600)
            settings = release / 'private' / 'provider-settings.json'
            settings.write_text(json.dumps({'BURIMUNSI_NATIVE_AUTO_TRANSACTIONS_ENABLED':'false'})); settings.chmod(0o600)
            result = tick(release, 'http://127.0.0.1:55101/functions/v1/collect-jobs', Opener('a'*64))
            self.assertEqual(result['native_auto_processing'], 'disabled')
            self.assertEqual(result['native_sms_ledger'], 'disabled')
            for auto, ledger in (('complete', None), (None, 'complete'), ('complete', 'complete')):
                with self.assertRaisesRegex(ValueError, 'disabled state'):
                    tick(release, 'http://127.0.0.1:55101/functions/v1/collect-jobs', Opener('a'*64, auto=auto, ledger=ledger))


if __name__ == '__main__': unittest.main()
