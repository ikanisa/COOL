"""Exact frontend input inventory, separate from backend deployment identity."""
from __future__ import annotations
import hashlib
import json
from pathlib import Path

ROOTS=('lib','web','assets','licenses','third_party','content/legal','content/product','tool','test','scripts',
       '.fvmrc','.metadata','analysis_options.yaml','pubspec.yaml','pubspec.lock')
EXCLUDED={'node_modules','.git','.dart_tool','__pycache__','.gradle','build','.DS_Store'}
def inventory(root):
    records={};missing=[]
    def add(path):
        relative=path.relative_to(root).as_posix()
        if path.resolve()!=path or not path.is_file():raise ValueError('Physical regular frontend input required')
        data=path.read_bytes()
        if len(data)>128*1024*1024:raise ValueError('Frontend input exceeds review budget')
        records[relative]={'path':relative,'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()}
    for role in ROOTS:
        path=root/role
        if not path.exists():
            if role!='licenses':missing.append(role)
            continue
        for child in sorted(path.rglob('*') if path.is_dir() else [path]):
            # Flutter emits comparison diagnostics here. Keep golden baselines
            # and test sources bound, but do not make a failed test's output a
            # new build input; diagnostic copies are retained as evidence.
            if child.is_relative_to(root/'test/goldens/failures'):continue
            if any(part in EXCLUDED or part.startswith('._') for part in child.relative_to(root).parts):continue
            if child.is_symlink():raise ValueError('Frontend source links require explicit source export')
            if child.is_file():add(child)
    provenance=root/'web/public/app-screens/capture-provenance.json'
    if provenance.is_file():
        value=json.loads(provenance.read_text())
        for key in ('capture_report','visual_review'):
            name=value.get(key)
            if not isinstance(name,str) or Path(name).is_absolute() or '..' in Path(name).parts:raise ValueError('Exact frontend media evidence path required')
            path=root/name
            if path.is_file():
                if hashlib.sha256(path.read_bytes()).hexdigest()!=value.get(key+'_sha256'):raise ValueError('Referenced media evidence changed')
                add(path)
            else:missing.append(name)
    files=sorted(records.values(),key=lambda item:item['path'])
    if len(files)>40000 or sum(item['bytes'] for item in files)>2*1024**3:raise ValueError('Frontend source inventory exceeds review budget')
    body={'format':'collect.selfhost.frontend-source.v1','complete':not missing,'missing_inputs':sorted(missing),'files':files}
    body['sha256']=hashlib.sha256(json.dumps(body,sort_keys=True,separators=(',',':')).encode()).hexdigest()
    return body
