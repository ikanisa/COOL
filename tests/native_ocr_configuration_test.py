"""Synthetic native JPEG feature configuration only; no release/provider actions."""
import copy
import hashlib
import json
import unittest
from scripts.self_hosted.configure import native_defaults,native_jpeg_ocr_configuration
from scripts.self_hosted.prepare import PRIVATE_FEATURE_CONTROLS,PROVIDER_SETTINGS

SOURCE='d'*64
NOW=1794828000


def fixture():
    policy={'schema_version':2,'status':'owner_authorized','enabled':True,
        'purpose':'collect_roster_static_jpeg_preview','provider':'openai',
        'responses_endpoint':'https://api.openai.com/v1/responses',
        'decoder_protocol':'collect-native-jpeg-v1','decoder_identity':'urn:collect:decoder:native-jpeg:v1',
        'decoder_build_sha256':'a'*64,'model':'existing-vision-snapshot','collection_id':'group-1',
        'source_sha256':SOURCE,'authorization_evidence_sha256':'b'*64,'technical_checks_sha256':'c'*64,
        'authorized_at':'2026-11-16T10:59:59Z','valid_until':None,'request_consent_required':True,'preview_only':True}
    settings={**PROVIDER_SETTINGS,'BURIMUNSI_NATIVE_ENABLED':'true',
        'BURIMUNSI_SMART_ONBOARDING_ADVANCED_ENABLED':'true','BURIMUNSI_COLLECTION_ID':'group-1',
        'BURIMUNSI_CANONICAL_SCHEDULER_COLLECTION_ID':'group-1',
        'ROSTER_DECODER_PROTOCOL':policy['decoder_protocol'],'ROSTER_DECODER_URL':policy['decoder_identity'],
        'ROSTER_DECODER_SECRET':'','ROSTER_DECODER_BUILD_SHA256':policy['decoder_build_sha256'],
        'ROSTER_AI_MODEL':policy['model'],'MOMO_AI_MODEL':policy['model'],
        'OPENAI_API_KEY':'synthetic-existing-key-1234567890'}
    return policy,settings


def bind(policy,settings):
    raw=json.dumps(policy,ensure_ascii=False,separators=(',',':'))
    settings['ROSTER_AI_APPROVAL_JSON']=raw
    settings['ROSTER_AI_APPROVAL_SHA256']=hashlib.sha256(raw.encode()).hexdigest()


class NativeOcrConfiguration(unittest.TestCase):
    def test_previous_settings_shape_defaults_advanced_feature_off(self):
        previous={key:value for key,value in PROVIDER_SETTINGS.items()
                  if key!='BURIMUNSI_SMART_ONBOARDING_ADVANCED_ENABLED'}
        normalized=native_defaults(previous)
        self.assertEqual(normalized['BURIMUNSI_SMART_ONBOARDING_ADVANCED_ENABLED'],'false')
        self.assertEqual(PRIVATE_FEATURE_CONTROLS['BURIMUNSI_SMART_ONBOARDING_ADVANCED_ENABLED'],'false')
        self.assertFalse(native_jpeg_ocr_configuration(normalized,SOURCE,now=NOW))

    def test_exact_native_policy_admits_only_the_existing_model_and_collection(self):
        policy,settings=fixture();bind(policy,settings)
        self.assertTrue(native_jpeg_ocr_configuration(settings,SOURCE,now=NOW))
        self.assertEqual(settings['ROSTER_AI_MODEL'],settings['MOMO_AI_MODEL'])

    def test_blank_global_filters_keep_authenticated_grant_scope_resolution(self):
        policy,settings=fixture();bind(policy,settings)
        settings['BURIMUNSI_COLLECTION_ID']=''
        settings['BURIMUNSI_CANONICAL_SCHEDULER_COLLECTION_ID']=''
        self.assertTrue(native_jpeg_ocr_configuration(settings,SOURCE,now=NOW))

    def test_declared_policy_and_configuration_must_match(self):
        mutations=[
            lambda p,s:s.update(BURIMUNSI_SMART_ONBOARDING_ADVANCED_ENABLED='false'),
            lambda p,s:s.update(ROSTER_DECODER_URL='https://unqualified.invalid/'),
            lambda p,s:s.update(ROSTER_DECODER_SECRET='new-secret'),
            lambda p,s:s.update(MOMO_AI_MODEL='other'),
            lambda p,s:s.update(BURIMUNSI_COLLECTION_ID='other'),
            lambda p,s:s.update(ROSTER_AI_APPROVAL_SHA256='0'*64),
            lambda p,s:p.update(source_sha256='e'*64),
            lambda p,s:p.update(status='legal_approved'),
            lambda p,s:p.update(request_consent_required=False),
            lambda p,s:p.update(preview_only=False),
            lambda p,s:p.update(organization_id='invented-org'),
            lambda p,s:p.update(valid_until='not-a-date'),
            lambda p,s:p.update(authorized_at='2026-11-16T12:00:00Z'),
            lambda p,s:p.update(valid_until='2026-11-16T10:59:59Z'),
        ]
        for index,mutation in enumerate(mutations):
            with self.subTest(mutation=index):
                policy,settings=fixture();mutation(policy,settings)
                if settings['ROSTER_AI_APPROVAL_SHA256']!='0'*64:bind(policy,settings)
                with self.assertRaises(ValueError):native_jpeg_ocr_configuration(settings,SOURCE,now=NOW)

    def test_disabled_external_decoder_approval_is_still_refused(self):
        settings={**PROVIDER_SETTINGS,'ROSTER_AI_APPROVAL_JSON':'{"schema_version":1}'}
        with self.assertRaises(ValueError):native_jpeg_ocr_configuration(settings,SOURCE,now=NOW)

    def test_duplicate_or_noncanonical_policy_bytes_are_refused(self):
        policy,settings=fixture();bind(policy,settings)
        raw=settings['ROSTER_AI_APPROVAL_JSON']
        for invalid in [raw+' ',raw[:-1]+',"model":"existing-vision-snapshot"}']:
            changed=copy.deepcopy(settings);changed['ROSTER_AI_APPROVAL_JSON']=invalid
            changed['ROSTER_AI_APPROVAL_SHA256']=hashlib.sha256(invalid.encode()).hexdigest()
            with self.assertRaises(ValueError):native_jpeg_ocr_configuration(changed,SOURCE,now=NOW)


if __name__=='__main__':unittest.main()
