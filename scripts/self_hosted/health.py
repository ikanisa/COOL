"""Read-only operational health and finite-capacity alarms; never emit row data.

The unresolved-admission, retained-obligation and unconfirmed-service-health
alarm codes are additive to health.v1. External monitors that enumerate codes
must recognize them or use the nonzero exit.
"""
from __future__ import annotations
import argparse
from datetime import datetime,timezone
import json
from pathlib import Path
import re
import shutil
import ssl
import sys
sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT))
from scripts.self_hosted.release_operator import Operator

def capacity_alarms(fence):
    """Read the current fence budget without treating absent counters as zero."""
    resources=fence.get('resourceLimits')
    if not isinstance(resources,dict):return [{'code':'capacity_unconfirmed'}]
    limits={'admissionBudgetVersion':4,'workingAdmissionLimit':100000,
        'activeWorkLimit':8,'operationReceiptLimit':10000,'schedulerLifecycleProofLimit':10000}
    counts=('workingAdmissions','activeAndUnresolvedAdmissions','operationReceipts','schedulerLifecycleProofs')
    valid=(all(type(resources.get(name)) is int and resources[name]==value for name,value in limits.items())
        and all(type(resources.get(name)) is int and resources[name]>=0 for name in counts)
        and type(fence.get('stoppedLifecycleProofs')) is int and fence['stoppedLifecycleProofs']>=0
        and type(resources.get('capacityBlocked')) is bool
        and type(resources.get('operationReceiptSaturated')) is bool)
    if not valid:
        alarms=[{'code':'capacity_unconfirmed'}]
        if resources.get('capacityBlocked') is True:alarms.append({'code':'finite_capacity_blocked'})
        return alarms
    working=resources['workingAdmissions'];active=resources['activeAndUnresolvedAdmissions']
    receipts=resources['operationReceipts'];scheduler=resources['schedulerLifecycleProofs']
    stopped=fence['stoppedLifecycleProofs']
    blocked=working>=100000 or active>=8 or receipts>=9998 or scheduler>=10000
    alarms=[]
    if active>working or resources['capacityBlocked']!=blocked or resources['operationReceiptSaturated']!=(receipts>=10000):
        alarms.append({'code':'capacity_unconfirmed'})
    # A reported block remains actionable even if its component counters disagree.
    if blocked or resources['capacityBlocked']:alarms.append({'code':'finite_capacity_blocked'})
    # 9,998 blocks new admission; 10,000 is the underlying receipt limit.
    for name,used,threshold in [('workingAdmissions',working,100000),
            ('operationReceipts',receipts,9998),('schedulerLifecycleProofs',scheduler,10000),
            ('stoppedLifecycleProofs',stopped,10000)]:
        if used*5>=threshold*4:
            # Keep the existing v1 output shape and report the hard receipt
            # limit even though admission stops at the lower threshold.
            alarm={'code':'finite_capacity_near_limit','resource':name,'used':used,
                'limit':10000 if name=='operationReceipts' else threshold}
            alarms.append(alarm)
    if stopped>=10000:alarms.append({'code':'finite_capacity_blocked','resource':'stoppedLifecycleProofs'})
    return alarms

def capacity_detail(fence,expected_source):
    """Return static count headroom only when the current budget is verified.

    Counts come from one owner-status read, not an atomic cross-counter
    snapshot, authorization, forecast, or guarantee of control completion.
    """
    if not isinstance(expected_source,str) or not re.fullmatch(r'[a-f0-9]{64}',expected_source) or fence.get('sourceSha256')!=expected_source or any(
            alarm['code']=='capacity_unconfirmed' for alarm in capacity_alarms(fence)):
        return {'status':'unconfirmed','resources':[]}
    resource=fence['resourceLimits']
    counts=[('workingAdmissions',resource['workingAdmissions'],100000),
        ('activeAndUnresolvedAdmissions',resource['activeAndUnresolvedAdmissions'],8),
        ('operationReceipts',resource['operationReceipts'],9998),
        ('schedulerLifecycleProofs',resource['schedulerLifecycleProofs'],10000),
        ('stoppedLifecycleProofs',fence['stoppedLifecycleProofs'],10000)]
    entries=[{'resource':name,'used':used,'threshold':threshold,
        'remaining':max(0,threshold-used)} for name,used,threshold in counts]
    # The lower operation threshold is for admission; the immutable record
    # limit is distinct and some control actions reserve additional entries.
    entries[2]['hard_limit']=10000
    return {'status':'confirmed','observation':'owner_status_read',
        'authorizes_operations':False,'resources':entries}

def evaluate(fence,services,disk,certificate_days,expected_source,expected_services):
    alarms=[]
    if fence.get('sourceSha256')!=expected_source:alarms.append({'code':'source_mismatch'})
    for name in sorted(set(expected_services)-{s.get('service') for s in services}):alarms.append({'code':'service_missing','service':name})
    for service in services:
        if service.get('state')!='running' or service.get('health') in ('unhealthy','starting'):alarms.append({'code':'service_unavailable','service':service.get('service')})
        elif service.get('health')!='healthy':alarms.append({'code':'service_health_unconfirmed','service':service.get('service')})
    if fence.get('mode')!='open':alarms.append({'code':'application_maintenance','mode':fence.get('mode')})
    if fence.get('schedulerStatus',{}).get('coverageVerified') is not True:alarms.append({'code':'scheduler_coverage_unverified'})
    retained=[fence.get('retainedUnknownObligations'),fence.get('retainedUnquantifiedUnknownObligations')]
    valid=[type(value) is int and value>=0 for value in retained]
    if not all(valid):alarms.append({'code':'retained_unknown_obligations_unconfirmed'})
    if any(ok and value>0 for ok,value in zip(valid,retained)):alarms.append({'code':'unresolved_external_effects'})
    unresolved=fence.get('effectiveUnresolvedAdmissions')
    if type(unresolved) is not int or unresolved<0:alarms.append({'code':'unresolved_admissions_unconfirmed'})
    elif unresolved>0:alarms.append({'code':'unresolved_admissions','count':unresolved})
    alarms.extend(capacity_alarms(fence))
    if disk['free_bytes']<10*1024**3 or disk['free_ratio']<.15:alarms.append({'code':'disk_space_low'})
    if certificate_days<30:alarms.append({'code':'database_tls_expiring','days_remaining':certificate_days})
    return alarms

def health(op,*,include_capacity_detail=False):
    status=op.status()
    raw=op.sql("SELECT private.collect_assert_deployment('"+op.meta['profile_sha256']+"');SELECT private.collect_fence_owner_status_v3();").decode().strip().splitlines()
    if not raw:raise ValueError('Controller status unconfirmed')
    fence=json.loads(raw[-1])
    if not isinstance(fence,dict):raise ValueError('Controller status unconfirmed')
    usage=shutil.disk_usage(op.root/'data');disk={'free_bytes':usage.free,'total_bytes':usage.total,'free_ratio':usage.free/usage.total}
    certificate=ssl._ssl._test_decode_cert(str(op.root/'private/db-tls/server.crt'))
    expiry=datetime.fromtimestamp(ssl.cert_time_to_seconds(certificate['notAfter']),timezone.utc);days=(expiry-datetime.now(timezone.utc)).days
    images=json.loads((op.root/'images.lock.json').read_text())['services']
    alarms=evaluate(fence,status['services'],disk,days,op.meta['source_sha256'],set(images)-{'backup'})
    # Expose counts and stable codes, never principals, tokens, queue bodies,
    # provider responses or ciphertext. A supervisor can alert on nonzero exit.
    result={'format':'collect.selfhost.health.v1','checked_at':datetime.now(timezone.utc).isoformat(),
        'profile_sha256':op.meta['profile_sha256'],'source_sha256':op.meta['source_sha256'],'status':'attention_required' if alarms else 'healthy',
        'services':status['services'],'mode':fence.get('mode'),'active_admissions':fence.get('effectiveActiveAdmissions',fence.get('activeAdmissions')),
        'unresolved_admissions':fence.get('effectiveUnresolvedAdmissions'),
        'retained_unknown_obligations':fence.get('retainedUnknownObligations'),'scheduler':fence.get('schedulerStatus'),
        'retained_unquantified_unknown_obligations':fence.get('retainedUnquantifiedUnknownObligations'),
        'resources':fence.get('resourceLimits'),'disk':disk,'database_certificate_days':days,'alarms':alarms}
    if include_capacity_detail:
        result['capacity_detail']=capacity_detail(fence,op.meta['source_sha256'])
    return result

def main(argv=None):
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--release',type=Path,required=True)
    p.add_argument('--capacity-detail',action='store_true',help='Include owner-status capacity counts and headroom; does not authorize operations')
    a=p.parse_args(argv)
    try:
        result=health(Operator(a.release),include_capacity_detail=a.capacity_detail);print(json.dumps(result,sort_keys=True));return 0 if result['status']=='healthy' else 2
    except (OSError,ValueError,KeyError,RuntimeError) as error:
        print(json.dumps({'status':'health_unconfirmed','error_class':type(error).__name__,'private_values_disclosed':False}),file=sys.stderr);return 3

if __name__=='__main__':
    sys.exit(main())
