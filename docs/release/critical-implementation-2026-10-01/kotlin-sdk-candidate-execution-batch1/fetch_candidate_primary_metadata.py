#!/usr/bin/env python3
"""Bounded public publisher metadata only; no private source/cache substitution."""
import concurrent.futures
import datetime
import hashlib
import json
import signal
import time
import urllib.error
import urllib.request
from pathlib import Path

HERE=Path(__file__).resolve().parent
JVM='https://plugins.gradle.org/m2/org/jetbrains/kotlin/jvm/org.jetbrains.kotlin.jvm.gradle.plugin/2.4.20/org.jetbrains.kotlin.jvm.gradle.plugin-2.4.20.pom'
COMP='https://repo.maven.apache.org/maven2/org/jetbrains/kotlin/kotlin-compiler-embeddable/2.4.20/kotlin-compiler-embeddable-2.4.20'
REQUESTS={'jvm-marker-pom':JVM,'jvm-marker-pom-sha1':JVM+'.sha1','compiler-pom':COMP+'.pom','compiler-pom-sha1':COMP+'.pom.sha1','compiler-module':COMP+'.module','compiler-jar-sha1':COMP+'.jar.sha1'}


def fetch(pair):
    name,url=pair;start=time.monotonic();record={'url':url,'request_timeout_seconds':30,'recorded_utc':datetime.datetime.now(datetime.timezone.utc).isoformat()}
    request=urllib.request.Request(url,headers={'User-Agent':'Collect-public-publisher-origin-verification/1.0','Accept-Encoding':'identity'})
    try:
        with urllib.request.urlopen(request,timeout=30) as response:
            body=response.read(4*1024**2+1)
            if len(body)>4*1024**2:raise ValueError('publisher metadata byte bound')
            record.update({'http_status':response.status,'final_url':response.url,'content_type':response.headers.get('Content-Type'),'bytes':len(body),'sha256':hashlib.sha256(body).hexdigest(),'sha1':hashlib.sha1(body).hexdigest()})
            (HERE/'public-origin'/name).write_bytes(body)
    except urllib.error.HTTPError as error:
        body=error.read(4096)
        record.update({'http_status':error.code,'failure':True,'failure_body_sha256':hashlib.sha256(body).hexdigest()})
        (HERE/'public-origin'/(name+'.failure-body')).write_bytes(body)
    except Exception as error:
        record.update({'failure':True,'exception_type':type(error).__name__,'public_error':str(error)})
    record['actual_seconds']=round(time.monotonic()-start,3)
    return name,record


if __name__=='__main__':
    def expired(signum,frame):raise TimeoutError('actual fixed120s metadata deadline expired')
    signal.signal(signal.SIGALRM,expired);signal.alarm(120)
    started=time.monotonic()
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
        records=dict(pool.map(fetch,REQUESTS.items()))
    signal.alarm(0)
    (HERE/'public-origin/candidate-origin-index.json').write_text(json.dumps({'records':records,'actual_total_seconds':round(time.monotonic()-started,3),'actual_process_deadline_seconds':120,'no_private_source_sent':True,'SDK_executed_by_fetcher':False},indent=2,sort_keys=True)+'\n')
    print(json.dumps({n:{k:r[k] for k in ('http_status','failure','actual_seconds') if k in r} for n,r in records.items()}))
