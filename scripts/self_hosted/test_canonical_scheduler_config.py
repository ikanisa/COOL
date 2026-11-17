"""Synthetic scheduler configuration only; no live activation or provider access."""
import hashlib
import json
import unittest

from scripts.self_hosted.prepare import PROVIDER_SETTINGS, CANONICAL_SCHEDULER_CONTROLS
from scripts.self_hosted.configure import native_defaults, validated_settings
from scripts.self_hosted.test_native_env_projection import PROFILE, ingress_proof

SOURCE = 'a'*64


def settings():
    group, owner = 'synthetic-group', 'synthetic-worker'
    descriptor = {'contract':'burimunsi.canonical-scheduler.v1','sourceSha256':SOURCE,
                  'collectionId':group,'owner':owner,'receiptLimit':1,'rematchLimit':0}
    approval = hashlib.sha256(json.dumps(descriptor,sort_keys=True,separators=(',',':')).encode()).hexdigest()
    return {**PROVIDER_SETTINGS, **ingress_proof(), 'BURIMUNSI_NATIVE_ENABLED':'true',
            'BURIMUNSI_NATIVE_WORKERS_ENABLED':'true', 'BURIMUNSI_SMS_OBSERVATIONS_ENABLED':'true',
            'BURIMUNSI_NATIVE_AUTO_TRANSACTIONS_ENABLED':'true',
            'MOMO_PROCESSING_PAUSED':'false', 'MOMO_AI_ENABLED':'true', 'MOMO_AI_MODEL':'synthetic-model',
            'OPENAI_API_KEY':'synthetic-key', 'COLLECT_JOBS_MODE':'receipt_processing_v1',
            'COLLECT_JOBS_PROCESSING_APPROVAL_SHA256':'b'*64,
            'BURIMUNSI_CANONICAL_SCHEDULER_ENABLED':'true',
            'BURIMUNSI_CANONICAL_SCHEDULER_COLLECTION_ID':group,
            'BURIMUNSI_CANONICAL_SCHEDULER_OWNER':owner,
            'BURIMUNSI_CANONICAL_SCHEDULER_MANAGED_ACCESS_TOKEN':'abcdefghijklmnop.qrstuvwxyz123456.abcdefghijklmno',
            'BURIMUNSI_CANONICAL_SCHEDULER_APPROVAL_SHA256':approval}


class CanonicalSchedulerConfigurationTests(unittest.TestCase):
    def test_existing_settings_gain_only_disabled_empty_defaults(self):
        old = {k:v for k,v in PROVIDER_SETTINGS.items() if k not in CANONICAL_SCHEDULER_CONTROLS}
        normalized = native_defaults(old)
        self.assertEqual({k:normalized[k] for k in CANONICAL_SCHEDULER_CONTROLS}, CANONICAL_SCHEDULER_CONTROLS)
        self.assertTrue(validated_settings(old, PROFILE, SOURCE)['configuration_only'])

    def test_exact_configuration_is_bound_to_group_owner_and_source(self):
        configured = settings()
        self.assertEqual(configured['BURIMUNSI_CANONICAL_SCHEDULER_APPROVAL_SHA256'],
                         '24391e43b41ddcd13a15750ded18373987d518ced2aec465a33447be796f46fb')
        self.assertTrue(validated_settings(configured, PROFILE, SOURCE)['configuration_only'])
        for changes in ({'MOMO_PROCESSING_PAUSED':'true'}, {'BURIMUNSI_NATIVE_WORKERS_ENABLED':'false'},
                        {'BURIMUNSI_NATIVE_AUTO_TRANSACTIONS_ENABLED':'false'}, {'COLLECT_JOBS_MODE':'maintenance_only'},
                        {'BURIMUNSI_CANONICAL_SCHEDULER_COLLECTION_ID':'different-group'},
                        {'BURIMUNSI_CANONICAL_SCHEDULER_OWNER':'different-worker'},
                        {'BURIMUNSI_CANONICAL_SCHEDULER_MANAGED_ACCESS_TOKEN':'bad'},
                        {'BURIMUNSI_CANONICAL_SCHEDULER_APPROVAL_SHA256':'c'*64},
                        {'BURIMUNSI_COLLECTION_ID':'different-group'}):
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                validated_settings({**configured, **changes}, PROFILE, SOURCE)
        with self.assertRaises(ValueError):
            validated_settings(configured, PROFILE, 'd'*64)


if __name__ == '__main__': unittest.main()
