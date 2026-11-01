"""Read-only operational health and finite-capacity alarms; never emit row data."""
from __future__ import annotations
import argparse
from datetime import datetime,timezone
import json
from pathlib import Path
import shutil
import ssl
import sys
sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT))
from scripts.self_hosted.release_operator import Operator

def evaluate(fence,services,disk,certificate_days,expected_source,expected_services):
    alarms=[]
    if fence.get('sourceSha256')!=expected_source:alarms.append({'code':'source_mismatch'})
    for name in sorted(set(expected_services)-{s.get('service') for s in services}):alarms.append({'code':'service_missing','service':name})
    for service in services:
        if service.get('state')!='running' or service.get('health') in ('unhealthy','starting'):alarms.append({'code':'service_unavailable','service':service.get('service')})
    if fence.get('mode')!='open':alarms.append({'code':'application_maintenance','mode':fence.get('mode')})
    if fence.get('schedulerStatus',{}).get('coverageVerified') is not True:alarms.append({'code':'scheduler_coverage_unverified'})
    if int(fence.get('retainedUnknownObligations',0))>0 or int(fence.get('retainedUnquantifiedUnknownObligations',0))>0:alarms.append({'code':'unresolved_external_effects'})
    resources=fence.get('resourceLimits',{})
    for actual,limit in [('workingAdmissions','workingAdmissionLimit'),('operationReceipts','operationReceiptLimit'),('schedulerLifecycleProofs','schedulerLifecycleProofLimit')]:
        value,maximum=resources.get(actual),resources.get(limit)
        if isinstance(value,(int,float)) and isinstance(maximum,(int,float)) and maximum>0 and value>=maximum*.8:alarms.append({'code':'finite_capacity_near_limit','resource':actual,'used':value,'limit':maximum})
    if int(fence.get('stoppedLifecycleProofs',0))>=8000:alarms.append({'code':'finite_capacity_near_limit','resource':'stoppedLifecycleProofs','used':fence['stoppedLifecycleProofs'],'limit':10000})
    if disk['free_bytes']<10*1024**3 or disk['free_ratio']<.15:alarms.append({'code':'disk_space_low'})
    if certificate_days<30:alarms.append({'code':'database_tls_expiring','days_remaining':certificate_days})
    return alarms

def health(op):
    status=op.status()
    raw=op.sql("SELECT private.collect_assert_deployment('"+op.meta['profile_sha256']+"');SELECT private.collect_fence_owner_status_v3();").decode().strip().splitlines()
    fence=json.loads(raw[-1]);usage=shutil.disk_usage(op.root/'data');disk={'free_bytes':usage.free,'total_bytes':usage.total,'free_ratio':usage.free/usage.total}
    certificate=ssl._ssl._test_decode_cert(str(op.root/'private/db-tls/server.crt'))
    expiry=datetime.fromtimestamp(ssl.cert_time_to_seconds(certificate['notAfter']),timezone.utc);days=(expiry-datetime.now(timezone.utc)).days
    images=json.loads((op.root/'images.lock.json').read_text())['services']
    alarms=evaluate(fence,status['services'],disk,days,op.meta['source_sha256'],set(images)-{'backup'})
    # Expose counts and stable codes, never principals, tokens, queue bodies,
    # provider responses or ciphertext. A supervisor can alert on nonzero exit.
    return {'format':'collect.selfhost.health.v1','checked_at':datetime.now(timezone.utc).isoformat(),
        'profile_sha256':op.meta['profile_sha256'],'source_sha256':op.meta['source_sha256'],'status':'attention_required' if alarms else 'healthy',
        'services':status['services'],'mode':fence.get('mode'),'active_admissions':fence.get('effectiveActiveAdmissions',fence.get('activeAdmissions')),
        'unresolved_admissions':fence.get('effectiveUnresolvedAdmissions',fence.get('unresolvedAdmissions')),
        'retained_unknown_obligations':fence.get('retainedUnknownObligations'),'scheduler':fence.get('schedulerStatus'),
        'retained_unquantified_unknown_obligations':fence.get('retainedUnquantifiedUnknownObligations'),
        'resources':fence.get('resourceLimits'),'disk':disk,'database_certificate_days':days,'alarms':alarms}

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--release',type=Path,required=True);a=p.parse_args()
    try:
        result=health(Operator(a.release));print(json.dumps(result,sort_keys=True));sys.exit(0 if result['status']=='healthy' else 2)
    except (OSError,ValueError,KeyError,RuntimeError) as error:
        print(json.dumps({'status':'health_unconfirmed','error_class':type(error).__name__,'private_values_disclosed':False}),file=sys.stderr);sys.exit(3)
