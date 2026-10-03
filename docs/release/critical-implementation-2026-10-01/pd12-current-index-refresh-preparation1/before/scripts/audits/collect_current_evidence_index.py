#!/usr/bin/env python3
"""Read-only current-index bindings. This does not execute or confer acceptance."""
import argparse
import errno
import fnmatch
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import time

FORMAT='collect-current-candidate-evidence-index-v1'
MAX_FILE=128*1024*1024
MAX_TOTAL=2*1024*1024*1024
MAX_ENTRIES=50000
MAX_SECONDS=60

class EvidenceIndexError(ValueError):pass

def deny(code):raise EvidenceIndexError(code)
def digest(raw):return hashlib.sha256(raw).hexdigest()
def parts(path):
    if not isinstance(path,str) or not path or '\\' in path or any(ord(c)<32 for c in path):deny('unsafe-path')
    parsed=PurePosixPath(path)
    if parsed.is_absolute() or str(parsed)!=path or any(p in {'','..','.'} for p in parsed.parts):deny('unsafe-path')
    return parsed.parts

class Reader:
    def __init__(self):self.used=0;self.entries=0;self.deadline=time.monotonic()+MAX_SECONDS
    def budget(self,count=0):
        self.used+=count
        if self.used>MAX_TOTAL or time.monotonic()>self.deadline:deny('read-budget')
    def read(self,root,path):
        self.entries+=1
        if self.entries>MAX_ENTRIES:deny('entry-budget')
        self.budget();path_parts=parts(path);fd=os.open(root,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW)
        directory_identity=lambda entry:(entry.st_dev,entry.st_ino,entry.st_mode)
        directories=[directory_identity(os.fstat(fd))]
        try:
            for part in path_parts[:-1]:
                child=os.open(part,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW,dir_fd=fd);os.close(fd);fd=child
                directories.append(directory_identity(os.fstat(fd)))
            leaf=os.open(path_parts[-1],os.O_RDONLY|os.O_NOFOLLOW,dir_fd=fd)
            try:
                before=os.fstat(leaf)
                if not stat.S_ISREG(before.st_mode) or before.st_size>MAX_FILE:deny('unsupported-or-large-file')
                chunks=[]
                while True:
                    block=os.read(leaf,1024*1024)
                    if not block:break
                    self.budget(len(block));chunks.append(block)
                after=os.fstat(leaf)
                identity=lambda entry:(entry.st_dev,entry.st_ino,entry.st_size,entry.st_mode,entry.st_mtime_ns,entry.st_ctime_ns)
                if identity(before)!=identity(after):deny('file-changed-during-read')
                current=os.stat(path_parts[-1],dir_fd=fd,follow_symlinks=False)
                if identity(before)!=identity(current):deny('file-path-changed-during-read')
                check=os.open(root,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW)
                try:
                    if directory_identity(os.fstat(check))!=directories[0]:deny('directory-path-changed-during-read')
                    for depth,part in enumerate(path_parts[:-1],1):
                        child=os.open(part,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW,dir_fd=check);os.close(check);check=child
                        if directory_identity(os.fstat(check))!=directories[depth]:deny('directory-path-changed-during-read')
                    current=os.stat(path_parts[-1],dir_fd=check,follow_symlinks=False)
                    if identity(before)!=identity(current):deny('file-path-changed-during-read')
                finally:os.close(check)
                return b''.join(chunks)
            finally:os.close(leaf)
        finally:os.close(fd)

def json_value(raw):
    def unique(pairs):
        result={}
        for key,value in pairs:
            if key in result:deny('duplicate-JSON-key')
            result[key]=value
        return result
    try:return json.loads(raw.decode(),object_pairs_hook=unique,parse_constant=lambda _:deny('nonfinite-JSON'))
    except (UnicodeError,json.JSONDecodeError,RecursionError):deny('invalid-JSON')

def pointer(value,path):
    if path=='':return value
    if not isinstance(path,str) or not path.startswith('/'):deny('invalid-JSON-pointer')
    for segment in path[1:].split('/'):
        key=segment.replace('~1','/').replace('~0','~')
        try:value=value[int(key)] if isinstance(value,list) else value[key]
        except (ValueError,KeyError,IndexError,TypeError):deny('missing-JSON-pointer')
    return value

def rows(document,spec):
    value=pointer(document,spec['pointer']);shape=spec['shape']
    if shape=='map-metadata' and isinstance(value,dict):
        if any(not isinstance(metadata,dict) or 'path' in metadata for metadata in value.values()):deny('invalid-metadata-map')
        return [{'path':p,**metadata} for p,metadata in value.items()]
    if shape=='map-digest' and isinstance(value,dict):
        return [{'path':p,'sha256':checksum} for p,checksum in value.items()]
    if shape=='list-metadata' and isinstance(value,list):
        if any(not isinstance(entry,dict) for entry in value):deny('invalid-metadata-list')
        return value
    if shape=='checksum-lines' and isinstance(value,str):
        parsed=[]
        for line in value.splitlines():
            match=re.fullmatch(r'([0-9a-f]{64})  (.+)',line)
            if not match:deny('invalid-checksum-line')
            parsed.append({'path':match[2],'sha256':match[1]})
        return parsed
    deny('unsupported-manifest-shape')

def verify(index,workspace):
    if not isinstance(index,dict) or index.get('format')!=FORMAT:deny('unsupported-index')
    if not re.fullmatch('[0-9a-f]{64}',index['candidate']['source_manifest_sha256']):deny('invalid-candidate-digest')
    # These are the current proposal's explicit unknowns. Files/execution receipts
    # cannot independently grant visual, rights, hosted or package acceptance.
    expected_unknown={'full_visual_acceptance':'unverified','font_distribution_rights':'unverified',
                      'hosted_candidate_parity':'unverified','complete_packaged_SBOM':'unverified',
                      'production_release_approval':False}
    if index['acceptance_boundaries']!=expected_unknown:deny('unsupported-acceptance-claim')
    reader=Reader();documents={};errors=[];set_results={};facts=[]
    for name,record in index['documents'].items():
        raw=reader.read(workspace,record['path'])
        if digest(raw)!=record['sha256'] or len(raw)!=record['bytes']:deny('document-fence-mismatch:'+name)
        documents[name]=json_value(raw) if record.get('content','json')=='json' else raw.decode()
    for binding in index['candidate']['identity_bindings']:
        if pointer(documents[binding['document']],binding['pointer'])!=index['candidate']['source_manifest_sha256']:
            deny('candidate-source-identity-mismatch')
    for relation in index.get('scope_relations',[]):
        original=pointer(documents[relation['original_document']],relation['original_pointer'])
        projected=pointer(documents[relation['projected_document']],relation['projected_pointer'])
        excluded=relation['excluded_exact_paths']
        if len(excluded)!=len(set(excluded)) or any(p not in original for p in excluded):deny('invalid-scope-exclusion')
        if projected!={p:v for p,v in original.items() if p not in set(excluded)}:deny('scope-projection-mismatch')
    resources={name:(workspace if path=='.' else Path(path)) for name,path in index['resources'].items()}
    if any(not root.is_absolute() or root.is_symlink() for root in resources.values()):deny('unsafe-resource-root')
    for name,spec in index['file_sets'].items():
        entries=rows(documents[spec['document']],spec)
        if len(entries)!=spec['expected_count']:deny('manifest-count-mismatch:'+name)
        root=resources[spec['resource']];seen=set();matched=0;unknown=[];failed=[]
        for entry in entries:
            entry=dict(entry)
            override=spec.get('digest_overrides',{}).get(entry['path'])
            if override:
                entry['sha256']=pointer(documents[override['document']],override['pointer'])
                entry.pop('bytes',None);entry.pop('size',None)
            path=entry['path']
            if Path(path).is_absolute():
                try:path=Path(path).relative_to(root).as_posix()
                except ValueError:deny('manifest-path-outside-resource:'+name)
            path='/'.join((*parts(spec['prefix']),*parts(path))) if spec['prefix'] else '/'.join(parts(path))
            if path in seen:deny('duplicate-manifest-path:'+name)
            seen.add(path)
            if entry.get('kind','regular')!='regular' or not isinstance(entry.get('sha256'),str):
                # No guessed directory/link/unsupported physical proof.
                unknown.append({'path':path,'reason':'non-regular-or-unhashed-entry'});continue
            if not re.fullmatch('[0-9a-f]{64}',entry['sha256']):deny('invalid-manifest-digest:'+name)
            size=entry.get('bytes',entry.get('size'))
            if size is not None and (type(size)!=int or size<0):deny('invalid-manifest-size:'+name)
            try:
                raw=reader.read(root,path)
                if digest(raw)!=entry['sha256'] or (size is not None and len(raw)!=size):failed.append({'path':path,'reason':'bytes-or-hash-drift'})
                else:matched+=1
            except OSError as error:
                if spec.get('unproved_symlink_bindings',False) and error.errno==errno.ELOOP:
                    unknown.append({'path':path,'reason':'unproved-symlink-physical-binding'})
                else:failed.append({'path':path,'reason':'missing-or-unsafe-file'})
        closed=spec.get('closed_inventory')
        inventory_status='unknown-captured-list-only'
        if closed:
            # Optional, explicit producer-reviewed set scope. A finite source
            # root/pattern set can detect additions; no arbitrary SQL/code runs.
            if spec['prefix'] or closed.get('basis_document') not in documents:deny('invalid-closed-inventory')
            discovered=set();count=0
            for directory in closed['directories']:
                start=root.joinpath(*parts(directory))
                if start.is_symlink():deny('symlink-inventory-root')
                for current,dirs,names in os.walk(start,followlinks=False):
                    reader.budget();count+=len(names)
                    if count>MAX_ENTRIES:deny('inventory-entry-budget')
                    if any((Path(current)/d).is_symlink() for d in dirs):deny('symlink-inventory-directory')
                    for leaf in names:
                        path=(Path(current)/leaf).relative_to(root).as_posix()
                        if any(fnmatch.fnmatchcase(path,p) for p in closed['include_patterns']):discovered.add(path)
            additions=sorted(discovered-seen);omissions=sorted(seen-discovered)
            if additions or omissions:failed.append({'reason':'closed-inventory-set-drift','additions':additions,'omissions':omissions})
            inventory_status='closed-declared-set-matched' if not additions and not omissions else 'closed-declared-set-drift'
        set_results[name]={'role':spec['role'],'binding_domain':spec.get('binding_domain','captured-artifact'),'entries':len(entries),'matched':matched,'failed':failed,'unknown_entries':unknown,
                          'inventory_status':inventory_status,'source_or_artifact_scope':spec['scope']}
        errors.extend({'file_set':name,**failure} for failure in failed)
    for fact in index['facts']:
        source=documents[fact['document']]
        if fact['kind']=='json-pointer':actual=pointer(source,fact['pointer']);same=type(actual)==type(fact['expected']) and actual==fact['expected']
        elif fact['kind']=='text-includes':actual=fact['expected'] in source;same=actual is True
        else:deny('unsupported-fact-check')
        if not same:errors.append({'fact':fact['id'],'reason':'pinned-receipt-value-mismatch'})
        facts.append({'id':fact['id'],'matches_pinned_source':same})
    evidence=[]
    by_id={e['id']:e for e in index['evidence']}
    if len(by_id)!=len(index['evidence']):deny('duplicate-evidence-id')
    def cycle(name,ancestors):
        if name in ancestors:deny('supersession-cycle')
        if name not in by_id:deny('unknown-superseded-record')
        for old in by_id[name]['supersedes']:cycle(old,{*ancestors,name})
    for name in by_id:cycle(name,set())
    for item in index['evidence']:
        if any(old not in by_id for old in item['supersedes']):deny('unknown-superseded-record')
        if item.get('independent_receipt') not in {*documents,None}:deny('unknown-independent-receipt')
        if item['validation_status']=='retained-independent-scoped-readback' and item.get('independent_receipt') is None:deny('independent-status-without-receipt')
        result_binding=item['result_binding']
        actual_result=pointer(documents[result_binding['document']],result_binding['pointer'])
        if type(actual_result)!=type(item['observed_result']) or actual_result!=item['observed_result']:
            errors.append({'evidence':item['id'],'reason':'result-claim-not-bound-to-pinned-receipt'})
        selected=[set_results[s] for s in item['file_sets']]
        selected_inputs=[s for s in selected if s['role'] in {'source','transitive-input'}]
        evidence.append({'id':item['id'],'declared_result':item['observed_result'],'context':item['context'],
                         'independent_receipt_retained':item.get('independent_receipt') is not None,
                         'validation_status':item['validation_status'],
                         'listed_bindings':'drift' if any(s['failed'] for s in selected) else 'incomplete' if any(s['unknown_entries'] for s in selected) else 'matched' if selected else 'unverified',
                         'input_set_completeness':'closed-declared-scope' if selected_inputs and all(s['inventory_status']=='closed-declared-set-matched' for s in selected_inputs) else 'unknown',
                         'scope':item['scope'],'limitations':item['limitations'],'supersedes':item['supersedes']})
    return {'format':'collect-current-candidate-evidence-readback-v1','candidate':index['candidate'],
            'status':'binding-drift-or-contradiction' if errors else 'listed-bindings-checked-with-explicit-limits',
            'file_sets':set_results,'facts':facts,'evidence':evidence,'errors':errors,
            'acceptance_boundaries':expected_unknown,'PD12_closed':False,
            'integration_state':index.get('integration_state','unverified'),
            'pending_areas':index.get('pending_areas',[]),
            'summary_corrections_unapplied':index.get('summary_corrections_unapplied',[]),
            'closure_interpretation':'Integrator review and actual original-criterion proof remain required; file existence or matched retained lists do not close PD12.'}

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--root',type=Path,required=True);parser.add_argument('--index',type=Path,required=True)
    args=parser.parse_args();root=args.root.absolute()
    try:
        relative=args.index.absolute().relative_to(root).as_posix()
        result=verify(json_value(Reader().read(root,relative)),root)
    except (EvidenceIndexError,OSError,KeyError,TypeError,ValueError) as error:
        print(json.dumps({'status':'verification-not-completed','error':str(error),'PD12_closed':False,'production_release_approval':False},sort_keys=True))
        return 2
    print(json.dumps(result,indent=2,sort_keys=True));return 1 if result['errors'] else 0

if __name__=='__main__':raise SystemExit(main())
