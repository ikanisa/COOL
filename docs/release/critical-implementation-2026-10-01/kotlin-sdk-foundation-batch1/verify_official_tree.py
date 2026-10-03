#!/usr/bin/env python3
"""Reconstruct every tree identity from the exact public recursive Git tree."""
import copy, hashlib, json, re, sys
from pathlib import Path
P=Path(__file__).resolve().parent
EXPECTED_TREE="0af5ce62e3cd8dc4f9441177c3f7db1b26f423fa"
MODES={"040000":"tree","100644":"blob","100755":"blob","120000":"blob","160000":"commit"}
def git_object(kind,body):
    return hashlib.sha1(kind.encode()+b" "+str(len(body)).encode()+b"\0"+body).hexdigest()
def authenticate(document):
    if document.get("sha")!=EXPECTED_TREE or document.get("truncated") is not False:
        raise ValueError("root identity/truncation mismatch")
    nodes={}; children={"":[]}; aliases={}; case_aliases=[]
    for item in document["tree"]:
        path=item["path"]
        if not isinstance(path,str) or not path or path.startswith("/") or "\\" in path or any(ord(c)<32 for c in path):
            raise ValueError("unsafe tree path")
        parts=path.split("/")
        if any(part in ["", ".", "..", ".git"] for part in parts):
            raise ValueError("unsafe tree component")
        if path in nodes:raise ValueError("duplicate tree path")
        if MODES.get(item.get("mode"))!=item.get("type") or not re.fullmatch("[0-9a-f]{40}",item.get("sha","")):
            raise ValueError("invalid tree mode/type/object")
        folded=path.casefold()
        if folded in aliases and aliases[folded]!=path:case_aliases.append([aliases[folded],path])
        else:aliases[folded]=path
        nodes[path]=item
        parent,_,name=path.rpartition("/")
        children.setdefault(parent,[]).append((name,item))
        if item["type"]=="tree":children.setdefault(path,[])
    for path in nodes:
        parent=path.rpartition("/")[0]
        if parent and (parent not in nodes or nodes[parent]["type"]!="tree"):
            raise ValueError("missing/non-tree parent")
    computed={}
    for directory in sorted(children,key=lambda x:(x.count("/"),len(x)),reverse=True):
        entries=children[directory]
        entries=sorted(entries,key=lambda pair:pair[0].encode()+ (b"/" if pair[1]["type"]=="tree" else b""))
        body=b""
        for name,item in entries:
            if item["type"]=="tree" and computed.get((directory+"/" if directory else "")+name)!=item["sha"]:
                raise ValueError("child tree identity mismatch")
            body+=item["mode"].lstrip("0").encode()+b" "+name.encode()+b"\0"+bytes.fromhex(item["sha"])
        digest=git_object("tree",body)
        expected=nodes[directory]["sha"] if directory else EXPECTED_TREE
        if digest!=expected:raise ValueError("tree object reconstruction mismatch: "+(directory or "/"))
        computed[directory]=digest
    return nodes,{"reconstructed_tree_objects":len(computed),"entries":len(nodes),"regular_blobs":sum(n["mode"] in ["100644","100755"] for n in nodes.values()),"symlinks":sum(n["mode"]=="120000" for n in nodes.values()),"gitlinks":sum(n["mode"]=="160000" for n in nodes.values()),"casefold_aliases":case_aliases}
def main():
    source=P/"public-origin/official-recursive-tree-attempt3.body"
    receipt=json.loads((P/"official-tree-attempt3-origin.json").read_text())
    if not receipt.get("passed"):raise ValueError("complete official API tree transfer not established")
    raw=source.read_bytes()
    if hashlib.sha256(raw).hexdigest()!=receipt["body_sha256"]:raise ValueError("tree transfer drift")
    doc=json.loads(raw);nodes,summary=authenticate(doc)
    selected={"official-LICENSE":"LICENSE","engine.version":"bin/internal/engine.version","update_dart_sdk.sh":"bin/internal/update_dart_sdk.sh","update_engine_version.sh":"bin/internal/update_engine_version.sh","cache.dart":"packages/flutter_tools/lib/src/cache.dart","flutter_cache.dart":"packages/flutter_tools/lib/src/flutter_cache.dart","resolve_dependencies.gradle.kts":"packages/flutter_tools/gradle/resolve_dependencies.gradle.kts","sdk-build.gradle.kts":"packages/flutter_tools/gradle/build.gradle.kts","DependencyVersionChecker.kt":"packages/flutter_tools/gradle/src/main/kotlin/DependencyVersionChecker.kt","DependencyVersionCheckerTest.kt":"packages/flutter_tools/gradle/src/test/kotlin/DependencyVersionCheckerTest.kt"}
    bindings={}
    for local,path in selected.items():
        raw=(P/"public-origin"/local).read_bytes();item=nodes[path]
        if item["mode"] not in ["100644","100755"] or git_object("blob",raw)!=item["sha"] or len(raw)!=item["size"]:
            raise ValueError("selected exact source blob mismatch: "+path)
        bindings[path]={"retained_file":local,"mode":item["mode"],"git_blob_sha1":item["sha"],"bytes":len(raw),"sha256":hashlib.sha256(raw).hexdigest()}
    negatives=[]
    for name,mutation in [("actual_source_blob_identity_drift",lambda d:d["tree"][next(i for i,x in enumerate(d["tree"]) if x["path"]=="LICENSE")].update(sha="0"*40)),("actual_license_entry_loss",lambda d:d["tree"].__delitem__(next(i for i,x in enumerate(d["tree"]) if x["path"]=="LICENSE"))),("actual_duplicate_tree_path",lambda d:d["tree"].append(copy.deepcopy(d["tree"][0]))),("actual_unsafe_path",lambda d:d["tree"][0].update(path="../outside")),("truncated_publisher_tree",lambda d:d.update(truncated=True))]:
        changed=copy.deepcopy(doc);mutation(changed)
        try:authenticate(changed)
        except ValueError as error:negatives.append({"case":name,"rejected":True,"error":str(error)})
        else:raise ValueError("negative accepted: "+name)
    raw=(P/"public-origin/official-LICENSE").read_bytes();drift=raw+b"modified"
    if git_object("blob",drift)==nodes["LICENSE"]["sha"]:raise ValueError("changed license bytes unexpectedly matched")
    negatives.append({"case":"actual_retained_license_byte_drift","rejected":True,"error":"changed bytes do not match publisher tree blob"})
    result={"passed":True,"expected_root_tree":EXPECTED_TREE,"source_commit":"ad70ec4617166f1c38e5d2bfd388af71fda14f06","tree_transfer_sha256":hashlib.sha256(source.read_bytes()).hexdigest(),"summary":summary,"selected_regular_file_bindings":bindings,"negative_results":negatives,"scope":"Complete official Git tree metadata reconstruction and selected raw source/license exact-byte binding. Full pristine worktree contents, symlink target containment, bundle extraction, crypto signature verification, execution and ABI acceptance remain separate."}
    (P/"official-tree-validation.json").write_text(json.dumps(result,indent=2,sort_keys=True)+"\n")
    print(json.dumps({"passed":True,"summary":summary,"selected_files":len(bindings),"negatives":len(negatives)}))
if __name__=="__main__":main()
