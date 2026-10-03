#!/usr/bin/env python3
"""Read-only, standard-library proposal. Catalog truth and lexical evidence stay separate."""
import argparse
import collections
import dataclasses
import hashlib
import json
import os
from pathlib import Path
import re
import sys
import tempfile
import tomllib

FORMAT = "collect-schema-domain-map-v1"
SEMANTIC_OUTPUTS = ("schema-domain-map.json", "input-manifest.json", "coverage.json", "gaps.json", "DOMAIN_MAP.md")
ROOTS = ("lib", "supabase/functions", "android/app/src/main", "android/app/src/internal_gateway", "ios/Runner",
         "tools/collect-notification-mcp/src", "tools/roster-decoder", "tool", "scripts")
EXTENSIONS = {".dart", ".ts", ".js", ".mjs", ".cjs", ".kt", ".swift", ".py", ".rb", ".sh"}
PRUNE = {"node_modules", "build", ".dart_tool", ".git", ".gradle", "__pycache__", "Pods",
         "generated", "archives", "archive", "observed-output", "fixtures", "testing", "test", "tests", "qa"}
SCHEMA_DOMAINS = {
 "collect_admin_access": "admin-access", "collect_auth_security": "authentication-security",
 "collect_automation": "automation", "collect_gateway": "android-gateway",
 "collect_gateway_archive": "android-gateway", "collect_gateway_dispatch": "android-gateway",
 "collect_gateway_transport": "android-gateway", "collect_hybrid": "receipt-delivery",
 "collect_integrity": "device-integrity", "collect_member_actions": "member-actions",
 "collect_operator_audit": "operator-audit", "collect_ops": "operations-governance",
 "collect_privacy": "privacy", "collect_profile_access": "member-profile",
 "collect_receipt_actions": "receipt-actions", "collect_receipt_history": "receipt-history",
 "collect_receipt_operations": "receipt-operations", "collect_receipt_policy": "receipt-policy",
 "collect_receipt_source_projection": "receipt-source-projection",
 "collect_receipt_retention_controls": "receipt-retention-controls",
 "collect_receipt_successors": "receipt-successors", "collect_receipt_telemetry": "receipt-telemetry",
 "collect_receipt_worker_history": "receipt-worker-history", "collect_security": "authentication-security",
 "collect_supervisor": "receipt-supervisor",
}
PLATFORM_SCHEMAS = {"auth", "cron", "extensions", "graphql", "graphql_public", "net", "pgbouncer",
                    "realtime", "storage", "supabase_migrations", "vault"}
# Ordered naming rules are reviewed taxonomy, not a claim of business ownership.
PUBLIC_RULES = [
 ("receipt-retention-controls", r"receipt_retention_control"),
 ("receipt-successors", r"successor"), ("receipt-worker-history", r"receipt_worker_(history|run|retention)|repeat_run"),
 ("receipt-operations", r"receipt_operations|receipt_operation_|unattended|shadow_run|operating_policy"),
 ("receipt-supervisor", r"supervisor"), ("receipt-policy", r"receipt_policy"),
 ("android-gateway", r"gateway|device_key"), ("device-integrity", r"play_integrity|integrity_admission"),
 ("receipt-telemetry", r"receipt.*telemetry|receipt_overview"),
 ("receipt-history", r"receipt.*history|receipt.*archive"),
 ("receipt-actions", r"receipt.*(cancel|deferr|exception|retry)|exception.*(workflow|followup|escalat)|exception_entity"),
 ("receipt-delivery", r"receipt|hybrid|send_start|observed_outcome|unsent_claim|worker_heartbeat|sendable"),
 ("authentication-security", r"otp|auth_|signed_otp|session|step_up|security|reauth"),
 ("privacy", r"deletion|privacy|policy_(acceptance|document)|support_request|account_request"),
 ("operator-audit", r"audit|operator_approval|sensitive_access|whatsapp_approval|raw_sms_reveal"),
 ("notification", r"notification|fcm|apns"), ("roster", r"roster"),
 ("bank-reconciliation", r"bank|reconciliation|reconcile|statement|provider_finality|finality"),
 ("payments-ledger", r"payment|contribution|allocation|ledger|journal|momo|raw_sms|sms_contract|attested|evidence_link"),
 ("collections-membership", r"collection|group|member_obligation|recurring_period|receiver|invitation"),
 ("member-profile", r"profile|current_member|member_country|people_by_membership|non_member|list_members|support_channels"),
 ("admin-access", r"admin_(role|permission|user)|admin_identity|admin_notes|moderation|admin_access|admin_assert"),
 ("runtime-configuration", r"feature_flag|system_setting|runtime_config|navigation|queue|native_action|action_capabilit|country_rule|brand_entities|realtime_event|system_health|operational_metric"),
]

def sha(data):
    return hashlib.sha256(data).hexdigest()

def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()

def required_bytes(path):
    if path.is_symlink():raise ValueError("symlink input refused: "+str(path))
    try:return path.read_bytes()
    except OSError as error:raise ValueError("missing or unreadable input: "+str(path)) from error

def required_json(path):
    try:return json.loads(required_bytes(path))
    except (json.JSONDecodeError,UnicodeDecodeError) as error:raise ValueError("invalid JSON input: "+str(path)) from error

def admit_catalog_paths(paths):
    if len(paths)!=2 or len({p.resolve() for p in paths})!=2:raise ValueError("two distinct effective catalog paths required")

def domain(schema, name):
    if schema in SCHEMA_DOMAINS:
        return SCHEMA_DOMAINS[schema], "schema-name-taxonomy"
    if schema in PLATFORM_SCHEMAS:
        return "platform:" + schema, "platform-schema-taxonomy"
    if schema == "public":
        for label, pattern in PUBLIC_RULES:
            if re.search(pattern, name, re.I):
                return label, "public-name-taxonomy:" + pattern
    return "unclassified", "no-reviewed-rule"

@dataclasses.dataclass(frozen=True)
class Token:
    kind: str
    value: str
    start: int
    end: int

def lex(text, sql=False):
    """Small lexical scanner, not a language AST or PostgreSQL name resolver."""
    out, i, n = [], 0, len(text)
    while i < n:
        if text[i].isspace(): i += 1; continue
        if text.startswith("/*", i):
            depth, j = 1, i + 2
            while j < n and depth:
                if text.startswith("/*", j): depth += 1; j += 2
                elif text.startswith("*/", j): depth -= 1; j += 2
                else: j += 1
            i = j; continue
        if text.startswith("--" if sql else "//", i) or (not sql and text[i] == "#"):
            j = text.find("\n", i); i = n if j < 0 else j + 1; continue
        if sql and text[i] == "$":
            m = re.match(r"\$(?:[A-Za-z_][A-Za-z_0-9]*)?\$", text[i:])
            if m:
                delimiter = m.group(); j = text.find(delimiter, i + len(delimiter))
                if j >= 0:
                    out.append(Token("string", text[i+len(delimiter):j], i, j+len(delimiter)))
                    i = j+len(delimiter); continue
        if text[i] in "'\"`":
            q, start = text[i], i
            delimiter = q * 3 if text.startswith(q * 3, i) and not sql else q
            i += len(delimiter); value = []
            while i < n:
                if sql and text.startswith(q+q, i): value.append(q); i += 2; continue
                if text.startswith(delimiter, i): i += len(delimiter); break
                if not sql and text[i] == "\\" and i + 1 < n:
                    value.append(text[i:i+2]); i += 2; continue
                value.append(text[i]); i += 1
            out.append(Token("id" if sql and q == '"' else "string", "".join(value), start, i)); continue
        m = re.match(r"[A-Za-z_$][A-Za-z_0-9$]*", text[i:])
        if m:
            out.append(Token("id", m.group(), i, i+len(m.group()))); i += len(m.group()); continue
        out.append(Token("symbol", text[i], i, i+1)); i += 1
    return out

def caller_group(path):
    if path.startswith("lib/admin/"): return "admin-dart"
    if path.startswith("lib/"): return "member-shared-dart"
    if path.startswith("supabase/functions/"): return "edge-typescript"
    if path.startswith("tools/collect-notification-mcp/"): return "operator-worker-tool"
    if path.startswith("android/"): return "android-native"
    if path.startswith("ios/"): return "ios-native"
    return "operational-script-tool"

def source_exclusion(path):
    p = Path(path)
    if p.suffix not in EXTENSIONS: return "non-source-extension"
    if set(p.parts) & PRUNE: return "test-generated-cache-or-evidence-directory"
    if re.search(r"(^|[_\-.])(test|tests|fixture|uat|benchmark|smoke|preview|capture)([_\-.]|$)", p.name, re.I):
        return "test-fixture-uat-preview-or-capture-file"
    if p.name.endswith((".g.dart", ".freezed.dart")) or p.name.startswith("generate_"): return "generated-or-generator-file"
    if "admin_evidence_mode" in p.name: return "synthetic-evidence-adapter"
    return None

def maintained_sources(root):
    admitted, excluded = [], []
    for prefix in ROOTS:
        base = root / prefix
        if not base.exists(): continue
        for parent, dirs, files in os.walk(base, followlinks=False):
            dirs[:] = sorted(d for d in dirs if d not in PRUNE and not (Path(parent) / d).is_symlink())
            for name in sorted(files):
                path = Path(parent) / name; relative = path.relative_to(root).as_posix()
                if path.is_symlink(): excluded.append({"path": relative, "reason": "symlink"}); continue
                reason = source_exclusion(relative)
                if reason: excluded.append({"path": relative, "reason": reason}); continue
                admitted.append(path)
    return sorted(set(admitted)), sorted(excluded, key=lambda x: x["path"])

def function_id(row): return f"{row[0]}.{row[1]}({row[2]})"

def targets(name, catalog, kind="function", default_schema="public"):
    rows = catalog["functions" if kind == "function" else "relations"]
    schema, short = name.split(".", 1) if "." in name else (default_schema, name)
    return [function_id(r) if kind == "function" else f"{r[0]}.{r[1]}" for r in rows if r[0] == schema and r[1] == short]

def client_sites(text, path, catalog):
    tokens, sites, consumed = lex(text), [], set()
    function_names = {r[1] for r in catalog["functions"] if r[0] == "public"}
    relation_names = {r[1] for r in catalog["relations"] if r[0] == "public"}
    def add(kind, token, name=None, expression=None, assumption=None):
        match = targets(name, catalog, "relation" if kind in {"relation-sdk", "realtime-table"} else "function") if name else []
        sites.append({"path": path, "line": text.count("\n", 0, token.start)+1, "offset": token.start,
                      "caller_group": caller_group(path), "kind": kind, "symbol": name,
                      "expression": expression, "candidate_targets": match,
                      "resolution": "unique-catalog-name" if len(match) == 1 else "overload-or-name-ambiguous" if match else "unresolved",
                      "schema_assumption": assumption, "authorization": "not-inferred"})
    for i, token in enumerate(tokens):
        if token.kind != "id": continue
        lower = token.value.lower()
        is_rpc = lower == "rpc" or lower.endswith("_rpc") or (token.value == "rpcMap" and path.startswith("lib/admin/"))
        is_from = token.value == "from" and i > 0 and tokens[i-1].value == "."
        is_invoke = token.value == "invoke" and i > 1 and tokens[i-2].value == "functions"
        if not (is_rpc or is_from or is_invoke): continue
        if is_rpc and i > 0 and tokens[i-1].value in {"function", "def"}: continue
        if is_from and i > 1:
            receiver = tokens[i-2].value
            if receiver == ">":
                depth, previous = 1, i-3
                while previous >= 0 and depth:
                    if tokens[previous].value == ">": depth += 1
                    if tokens[previous].value == "<": depth -= 1
                    previous -= 1
                if previous >= 0: receiver = tokens[previous].value
            if receiver in {"Map", "List", "Set", "Array", "Buffer", "BigInt", "Uint8Array", "Uint32Array", "Float32Array", "DateTime"}: continue
        j = i + 1
        if j < len(tokens) and tokens[j].value == "<":
            depth = 1; j += 1
            while j < len(tokens) and depth:
                if tokens[j].value == "<": depth += 1
                if tokens[j].value == ">": depth -= 1
                j += 1
        if j >= len(tokens) or tokens[j].value != "(" or j + 1 >= len(tokens): continue
        first = j + 1
        # rpc(deps, "literal", args) is the maintained roster helper convention.
        if tokens[first].value == "deps" and first+2 < len(tokens) and tokens[first+1].value == ",": first += 2
        if first+1 < len(tokens) and tokens[first+1].value == ":": continue  # declaration, not invocation
        if tokens[first].value in {"String", "Object", "Map", "dynamic"} and first+1 < len(tokens) and tokens[first+1].kind == "id": continue
        kind = "rpc-call" if is_rpc else "relation-sdk" if is_from else "edge-invoke"
        arg = tokens[first]
        literal = arg.kind == "string" and not re.search(r"\$[A-Za-z_{]", arg.value)
        if literal and first+1 < len(tokens) and tokens[first+1].value in {",", ")"}:
            add(kind, token, arg.value, assumption="SDK-default-public-unless-client-schema-overridden" if not is_invoke else None)
            consumed.add(first)
            if is_invoke: sites[-1]["resolution"] = "edge-route-not-database-object"; sites[-1]["candidate_targets"] = []
        else:
            add("dynamic-"+kind, token, expression=text[arg.start:min(arg.start+100, len(text))].split("\n")[0])
    for i, token in enumerate(tokens):
        if token.kind != "string" or i in consumed: continue
        if token.value in function_names:
            add("function-literal-reference", token, token.value, assumption="public-name-candidate-only")
        elif token.value in relation_names and i > 1 and tokens[i-1].value == ":" and tokens[i-2].value == "table":
            add("realtime-table", token, token.value, assumption="table-name-only-schema-review-required")
        elif re.search(r"\$[A-Za-z_{]", token.value):
            pattern=re.escape(token.value)
            pattern=re.sub(r"\\\$\\\{.*?\\\}",".*",pattern)
            pattern=re.sub(r"\\\$[A-Za-z_][A-Za-z_0-9]*",".*",pattern)
            identifier_template=bool(re.fullmatch(r"[a-z_][A-Za-z_0-9$.{}]*",token.value))
            if "/rest/v1/rpc/" in token.value or (identifier_template and (token.value.startswith("admin_") or any(re.fullmatch(pattern,name) for name in function_names))):
                add("dynamic-symbol-template", token, expression=token.value[:160])
        if "/functions/v1/" in token.value:
            add("edge-http-route-reference", token, expression=token.value[:160]); sites[-1]["resolution"] = "edge-route-not-database-object"
    # Schema override sites remain explicit and invalidate automatic public resolution.
    if any(t.value == "schema" and i > 0 and tokens[i-1].value == "." and i+1 < len(tokens) and tokens[i+1].value == "(" for i,t in enumerate(tokens)):
        for site in sites:
            if site["schema_assumption"]: site["resolution"] = "schema-override-review-required"
    return sites

def sql_definitions(text, path, version):
    """Body hashes bind candidates to pg_proc.prosrc; arguments are never inferred."""
    result, tokens = [], lex(text, sql=True)
    for i,token in enumerate(tokens):
        if token.kind!="id" or token.value.lower()!="create":continue
        j=i+1
        if j+1<len(tokens) and [tokens[j].value.lower(),tokens[j+1].value.lower()]==["or","replace"]:j+=2
        if j+1>=len(tokens) or tokens[j].value.lower() not in {"function","procedure"}:continue
        j+=1
        if tokens[j].kind!="id":continue
        schema,short="public",tokens[j].value;j+=1
        if j+1<len(tokens) and tokens[j].value=="." and tokens[j+1].kind=="id":schema,short=short,tokens[j+1].value;j+=2
        if j>=len(tokens) or tokens[j].value!="(":continue
        body_token=None
        while j+1<len(tokens) and tokens[j].value!=";":
            if tokens[j].kind=="id" and tokens[j].value.lower()=="as" and tokens[j+1].kind=="string":body_token=tokens[j+1];break
            j+=1
        if body_token is None:continue
        delimiter=re.match(r"\$(?:[A-Za-z_][A-Za-z_0-9]*)?\$",text[body_token.start:])
        offset=body_token.start+(len(delimiter.group()) if delimiter else 1)
        result.append({"path":path,"line":text.count("\n",0,token.start)+1,"schema":schema,"name":short,
                       "version":version,"prosrc_sha256":sha(body_token.value.encode()),"body":body_token.value,"body_offset":offset})
    return result

def sql_sites(definition, catalog):
    text, sites = definition["body"], []
    tokens = lex(text, sql=True)
    functions = collections.defaultdict(list); relations = collections.defaultdict(list)
    for row in catalog["functions"]: functions[(row[0],row[1])].append(function_id(row))
    for row in catalog["relations"]: relations[(row[0],row[1])].append(f"{row[0]}.{row[1]}")
    for i,t in enumerate(tokens):
        if t.kind != "id": continue
        if t.value.lower() == "execute":
            sites.append({"kind": "dynamic-sql-execute", "line_in_body": text.count("\n",0,t.start)+1,
                          "candidate_targets": [], "resolution": "requires-expression-and-search-path-review"}); continue
        schema, name, j = None,t.value,i+1
        if j+1 < len(tokens) and tokens[j].value == "." and tokens[j+1].kind == "id":
            schema,name,j = name,tokens[j+1].value,j+2
        elif i > 0 and tokens[i-1].value == ".": continue
        is_call = j < len(tokens) and tokens[j].value == "("
        preceding = tokens[i-1].value.lower() if i else ""
        relation_context = preceding in {"from", "join", "update", "into", "table", "truncate"}
        lookup = functions if is_call and not relation_context else relations if relation_context else None
        if lookup is None: continue
        possible = lookup.get((schema,name),[]) if schema else [v for (s,n),values in lookup.items() if n==name for v in values]
        if not possible and schema not in {"public", *SCHEMA_DOMAINS}: continue
        sites.append({"kind": "sql-function-name" if lookup is functions else "sql-relation-name", "symbol": f"{schema+'.' if schema else ''}{name}",
                      "line_in_body": text.count("\n",0,t.start)+1, "candidate_targets": possible,
                      "resolution": "unique-qualified-name" if schema and len(possible)==1 else "overload-review-required" if schema and possible else "search-path-review-required" if possible else "unresolved"})
    return sites

def acl_entries(values):
    entries = []
    for value in values:
        m = re.fullmatch(r'(.*)=(.*)/(.*)', value)
        if not m: raise ValueError("malformed catalog ACL")
        role, privileges, grantor = m.groups()
        entries.append({"grantee": role or "PUBLIC", "privilege_codes": privileges, "grantor": grantor, "raw": value})
    return entries

def admit(catalog):
    required = {"format", "server", "database", "migrations", "schemas", "relations", "functions", "columns", "roles", "memberships", "default_acls", "types", "dependencies", "settings", "policies", "triggers", "indexes", "constraints", "extensions", "event_triggers"}
    if not isinstance(catalog,dict) or not required <= catalog.keys() or catalog["format"] != "collect-recovery-catalog-v1": raise ValueError("unsupported or incomplete catalog")
    sizes = {"schemas":3,"relations":10,"functions":13,"columns":11,"roles":11,"memberships":6,"default_acls":4,"types":9,"dependencies":7}
    for key,size in sizes.items():
        if not isinstance(catalog[key],list) or any(not isinstance(r,list) or len(r)!=size for r in catalog[key]): raise ValueError("catalog row shape: "+key)
    if not isinstance(catalog["database"],dict) or not {"acl","owner","name"} <= catalog["database"].keys(): raise ValueError("catalog database shape")
    for key,indexes in {"schemas":(0,),"relations":(0,1),"functions":(0,1,2),"types":(0,1),"columns":(0,1,2),"roles":(0,)}.items():
        ids=[tuple(r[i] for i in indexes) for r in catalog[key]]
        if len(ids)!=len(set(ids)): raise ValueError("duplicate catalog identity: "+key)
    if catalog["migrations"] != sorted(set(catalog["migrations"])): raise ValueError("migration catalog ordering/duplicates")

def normalize_objects(catalog):
    result=[]
    for kind, owner_index, acl_index in [("schema",1,2),("relation",4,7),("function",4,10),("type",3,7)]:
        key={"schema":"schemas","relation":"relations","function":"functions","type":"types"}[kind]
        for row in catalog[key]:
            schema,name=row[0], row[1] if kind != "schema" else row[0]
            label,rule=domain(schema,name)
            identity=function_id(row) if kind=="function" else schema if kind=="schema" else f"{schema}.{name}"
            record={"kind":kind,"identity":identity,"schema":schema,"name":name,"domain":label,"domain_basis":rule,
                    "database_owner":row[owner_index],"catalog_acl":acl_entries(row[acl_index]),"catalog_row":row,
                    "maintenance_owner":"platform-package-review" if schema in PLATFORM_SCHEMAS else "migration-maintainer-review-required",
                    "business_authorization":"not-inferred-from-ACL-or-owner"}
            if kind=="function": record.update(security_definer=row[5],prosrc_sha256=row[11],definition_sha256=row[12])
            if kind=="relation": record.update(relation_kind=row[2],rls_enabled=row[5],rls_forced=row[6])
            result.append(record)
    return result

def normalized_grants(catalog, objects):
    """One target/domain/owner-bound record per ACL entry, including column/default ACLs."""
    grants=[]; relation_map={o["identity"]:o for o in objects if o["kind"]=="relation"}
    for obj in objects:
        for entry in obj["catalog_acl"]:
            grants.append({"target_kind":obj["kind"],"target_identity":obj["identity"],"domain":obj["domain"],
                           "database_owner":obj["database_owner"],"acl_scope":"object",**entry})
    for row in catalog["columns"]:
        parent=relation_map[f"{row[0]}.{row[1]}"]
        for entry in acl_entries(row[8]):
            grants.append({"target_kind":"column","target_identity":f"{row[0]}.{row[1]}.{row[3]}","domain":parent["domain"],
                           "database_owner":parent["database_owner"],"acl_scope":"column",**entry})
    for row in catalog["default_acls"]:
        label,basis=domain(row[1],row[1])
        for entry in acl_entries(row[3]):
            grants.append({"target_kind":"default-acl","target_identity":f"{row[0]}:{row[1]}:{row[2]}","domain":label,
                           "database_owner":row[0],"acl_scope":"default-future-object-only",**entry})
    for entry in acl_entries(catalog["database"]["acl"]):
        grants.append({"target_kind":"database","target_identity":catalog["database"]["name"],"domain":"platform:database",
                       "database_owner":catalog["database"]["owner"],"acl_scope":"database",**entry})
    return grants

def build(root, catalog_paths, output, replay_migrations=None):
    inputs=[]; catalogs=[]
    admit_catalog_paths(catalog_paths)
    for path in catalog_paths:
        raw=required_bytes(path); value=json.loads(raw); admit(value)
        catalogs.append(value); inputs.append({"path":str(path.relative_to(root)) if path.is_relative_to(root) else str(path),"sha256":sha(raw),"kind":"effective-catalog"})
    catalog=catalogs[0]
    if any(canonical(c) != canonical(catalog) for c in catalogs[1:]): raise ValueError("peer final catalogs differ")
    sources,excluded=maintained_sources(root); sites=[]
    for path in sources:
        raw=required_bytes(path); relative=path.relative_to(root).as_posix()
        inputs.append({"path":relative,"sha256":sha(raw),"kind":"maintained-caller-source","caller_group":caller_group(relative)})
        sites.extend(client_sites(raw.decode("utf-8"),relative,catalog))
    migration_files=sorted((root/"supabase/migrations").glob("*.sql")); definitions=[]; versions=[]
    for path in migration_files:
        if path.is_symlink(): raise ValueError("migration symlink")
        m=re.fullmatch(r"([0-9]+)_.+\.sql",path.name)
        if not m: raise ValueError("migration filename")
        version=m.group(1); versions.append(version); raw=required_bytes(path); relative=path.relative_to(root).as_posix()
        inputs.append({"path":relative,"sha256":sha(raw),"kind":"original-migration","version":version,"represented_in_catalog":version in catalog["migrations"]})
        definitions.extend(sql_definitions(raw.decode("utf-8"),relative,version))
    if versions != sorted(set(versions)): raise ValueError("migration source ordering/duplicates")
    replay_bound=None
    if replay_migrations is not None:
        captured=sorted(replay_migrations.glob("*.sql"))
        if [p.name for p in captured]!=[p.name for p in migration_files]:raise ValueError("replayed migration set differs")
        for captured_path,source_path in zip(captured,migration_files):
            captured_raw=required_bytes(captured_path)
            if captured_raw!=required_bytes(source_path):raise ValueError("replayed migration byte drift: "+source_path.name)
            inputs.append({"path":captured_path.relative_to(root).as_posix() if captured_path.is_relative_to(root) else str(captured_path),"sha256":sha(captured_raw),"kind":"replayed-original-migration","version":source_path.name.split("_",1)[0]})
        replay_bound=True
    objects=normalize_objects(catalog); matched=[]; sql_references=[]
    by_body=collections.defaultdict(list)
    for d in definitions:
        if d["version"] in catalog["migrations"]: by_body[(d["schema"],d["name"],d["prosrc_sha256"])].append(d)
    for obj in objects:
        if obj["kind"]!="function":continue
        matches=by_body[(obj["schema"],obj["name"],obj["prosrc_sha256"])]
        obj["matched_body_sources"]=[{k:v for k,v in d.items() if k not in {"body","body_offset"}} for d in matches]
        obj["source_status"]="catalog-prosrc-hash-matched" if matches else "no-exact-body-source-match"
        if matches:
            d=matches[-1]
            for site in sql_sites(d,catalog):
                sql_references.append({"caller_function":obj["identity"],"source_path":d["path"],"source_line":d["line"],**site})
            matched.append(obj["identity"])
    config_path=root/"supabase/config.toml"; config_raw=required_bytes(config_path); config=tomllib.loads(config_raw.decode())
    inputs.append({"path":"supabase/config.toml","sha256":sha(config_raw),"kind":"local-platform-config"})
    for relative in ["scripts/sql/collect_recovery_source_catalog.sql","scripts/sql/receipt_transport_platform_prerequisites.sql","scripts/supabase_schema_inventory.sh","scripts/audits/collect_migration_history_review.rb"]:
        p=root/relative
        if p.exists(): inputs.append({"path":relative,"sha256":sha(required_bytes(p)),"kind":"catalog-or-platform-setup"})
    this_script=Path(__file__).resolve()
    inputs.append({"path":this_script.relative_to(root).as_posix() if this_script.is_relative_to(root) else str(this_script),"sha256":sha(required_bytes(this_script)),"kind":"generator-proposal"})
    reviewed=[];seams_path=this_script.with_name("reviewed-caller-seams.json")
    if this_script.is_relative_to(root):
        seams_raw=required_bytes(seams_path);seams=json.loads(seams_raw)
        if seams.get("format")!="collect-reviewed-caller-seams-v1":raise ValueError("reviewed seams format")
        for case in seams["cases"]:
            p=root/case["path"];raw=required_bytes(p);source=raw.decode()
            if sha(raw)!=case["source_sha256"] or case["anchor"] not in source:raise ValueError("reviewed source seam drift: "+case["id"])
            if source.count("\n",0,source.index(case["anchor"]))+1!=case["line"]:raise ValueError("reviewed seam line drift")
            entry=dict(case);entry["candidate_targets"]=[target for name in case["reviewed_public_name_candidates"] for target in targets(name,catalog)]
            if any(not targets(name,catalog) for name in case["reviewed_public_name_candidates"]):raise ValueError("reviewed symbol absent from catalog: "+case["id"])
            reviewed.append(entry)
        inputs.append({"path":seams_path.relative_to(root).as_posix(),"sha256":sha(seams_raw),"kind":"reviewed-caller-seams"})
    inputs=sorted({(r["kind"],r["path"]):r for r in inputs}.values(),key=lambda x:(x["kind"],x["path"]))
    source_only=sorted(set(versions)-set(catalog["migrations"])); catalog_only=sorted(set(catalog["migrations"])-set(versions))
    current=not(source_only or catalog_only)
    caller_index=collections.defaultdict(list)
    for idx,site in enumerate(sites):
        for target in site["candidate_targets"]:caller_index[target].append(idx)
    sql_index=collections.defaultdict(list)
    for idx,site in enumerate(sql_references):
        for target in site["candidate_targets"]:sql_index[target].append(idx)
    for obj in objects:
        obj["caller_site_indexes"]=caller_index[obj["identity"]];obj["sql_reference_indexes"]=sql_index[obj["identity"]]
    summary={"catalog_migrations":len(catalog["migrations"]),"source_migrations":len(versions),"source_only_migrations":source_only,
             "catalog_only_migrations":catalog_only,"catalog_matches_current_migration_names":current,"peer_catalogs_equal":True,
             "replayed_migration_bytes_match":replay_bound,"reviewed_caller_seams":len(reviewed),
             "catalog_objects_by_kind":dict(collections.Counter(o["kind"] for o in objects)),
             "maintained_source_files":len(sources),"caller_sites_by_kind":dict(collections.Counter(s["kind"] for s in sites)),
             "functions_with_exact_body_hash_match":len(matched),"functions_without_exact_body_hash_match":len(catalog["functions"])-len(matched),
             "sql_reference_sites":len(sql_references),"unclassified_objects":sum(o["domain"]=="unclassified" for o in objects),
             "function_objects_without_literal_caller_or_sql_candidate":sum(o["kind"]=="function" and not o["caller_site_indexes"] and not o["sql_reference_indexes"] for o in objects),
             "dynamic_or_unresolved_caller_sites":sum(s["kind"].startswith("dynamic-") or s["resolution"] in {"unresolved","schema-override-review-required","overload-or-name-ambiguous"} for s in sites),
             "business_owner_assignments_verified":False,"runtime_call_graph_complete":False,"acceptance":"draft-with-open-mappings" if current and replay_bound else "source-hash-binding-unattested-draft" if current else "stale-catalog-draft"}
    grants=normalized_grants(catalog,objects);summary["normalized_grant_entries"]=len(grants)
    domain_summaries=[]
    for label in sorted({o["domain"] for o in objects}):
        rows=[o for o in objects if o["domain"]==label];caller_indexes={i for o in rows for i in o["caller_site_indexes"]}
        domain_summaries.append({"domain":label,"objects_by_kind":dict(collections.Counter(o["kind"] for o in rows)),
          "database_owners":sorted({o["database_owner"] for o in rows}),"schema_names":sorted({o["schema"] for o in rows}),
          "candidate_caller_groups":sorted({sites[i]["caller_group"] for i in caller_indexes}),
          "candidate_caller_files":sorted({sites[i]["path"] for i in caller_indexes}),
          "matched_function_body_source_files":sorted({s["path"] for o in rows for s in o.get("matched_body_sources",[])}),
          "maintenance_owner":"review-required","business_owner":"unassigned"})
    doc={"format":FORMAT,"summary":summary,"input_manifest_sha256":sha(canonical(inputs)),"objects":objects,"grants":grants,"caller_sites":sites,"sql_reference_sites":sql_references,"reviewed_caller_seams":reviewed,
         "domain_summaries":domain_summaries,
         "catalog_supporting_records":{k:v for k,v in catalog.items() if k not in {"schemas","relations","functions","types"}},
         "local_platform_setup":{"api_schemas":config.get("api",{}).get("schemas"),"api_extra_search_path":config.get("api",{}).get("extra_search_path"),
           "function_verify_jwt":{k:v.get("verify_jwt","platform-default-unverified") for k,v in config.get("functions",{}).items()},
           "role_and_client_interpretation":"SDK member/Admin callers use current user sessions; shared serviceClient uses service key; wrappers and native Edge routes require path review. No deployed config or authorization is asserted."}}
    output.mkdir(parents=True,exist_ok=True)
    for name,value in [("schema-domain-map.json",doc),("input-manifest.json",{"format":"collect-schema-domain-inputs-v1","inputs":inputs,"excluded_files":excluded,"scan_roots":ROOTS,"pruned_directories":sorted(PRUNE)}),
                       ("coverage.json",summary),("gaps.json",{"unclassified_objects":[{k:o[k] for k in ["kind","identity","database_owner","domain_basis"]} for o in objects if o["domain"]=="unclassified"],
                        "unresolved_callers":[s for s in sites if s["kind"].startswith("dynamic-") or s["resolution"] in {"unresolved","schema-override-review-required","overload-or-name-ambiguous"}],
                        "functions_without_exact_body_match":[o["identity"] for o in objects if o["kind"]=="function" and o["source_status"]=="no-exact-body-source-match"],
                        "sql_resolution_review":[s for s in sql_references if s["resolution"]!="unique-qualified-name"],
                        "unrepresented_migration_sources":[r for r in inputs if r["kind"]=="original-migration" and not r["represented_in_catalog"]]})]:
        (output/name).write_text(json.dumps(value,indent=2,sort_keys=True,ensure_ascii=False)+"\n")
    lines=["# Effective catalog domain and caller inventory", "",f"Acceptance: **{summary['acceptance']}**. This is lexical inventory and catalog evidence; all domain maintenance owners require review.","",
           f"Catalog migrations: {len(catalog['migrations'])}; source migrations: {len(versions)}. Source-only versions: {', '.join(source_only) or 'none'}.","",
           "| Domain | Schemas | Relations | Functions | Types | Database owner | Caller candidates |", "|---|---:|---:|---:|---:|---|---|"]
    for row in domain_summaries:
        counts=collections.Counter(row["objects_by_kind"])
        lines.append(f"| {row['domain']} | {counts['schema']} | {counts['relation']} | {counts['function']} | {counts['type']} | {', '.join(row['database_owners'])} | {', '.join(row['candidate_caller_groups']) or 'none found'} |")
    lines.extend(["",f"Maintained sources: {len(sources)}. Caller sites: {len(sites)}. Exact catalog body hash matches: {len(matched)}/{len(catalog['functions'])} functions.",
                  f"Unclassified objects: {summary['unclassified_objects']}. Dynamic/unresolved callers: {summary['dynamic_or_unresolved_caller_sites']}.","",
                  "See schema-domain-map.json for every catalog row, owner, ACL, source hash binding, caller index and SQL candidate. See gaps.json for unresolved work. PostgreSQL dependencies are preserved independently; they are not a complete procedural call graph.",""])
    (output/"DOMAIN_MAP.md").write_text("\n".join(lines))
    return summary

def verify_bundle(root, output):
    """Read back admitted bytes and recompute every semantic artifact from those inputs."""
    manifest=required_json(output/"input-manifest.json");doc=required_json(output/"schema-domain-map.json")
    if not isinstance(manifest,dict) or manifest.get("format")!="collect-schema-domain-inputs-v1" or not isinstance(manifest.get("inputs"),list):raise ValueError("input manifest shape")
    if not isinstance(doc,dict) or doc.get("format")!=FORMAT:raise ValueError("generated inventory shape")
    inputs=manifest["inputs"]
    if any(not isinstance(i,dict) or not all(isinstance(i.get(k),str) for k in ["path","kind","sha256"]) for i in inputs):raise ValueError("input manifest entry shape")
    if len({(i["kind"],i["path"]) for i in inputs})!=len(inputs):raise ValueError("duplicate input manifest entry")
    if doc.get("input_manifest_sha256")!=sha(canonical(inputs)):raise ValueError("manifest binding changed")
    source_paths,_=maintained_sources(root)
    if {p.relative_to(root).as_posix() for p in source_paths}!={i["path"] for i in inputs if i["kind"]=="maintained-caller-source"}:raise ValueError("maintained caller source set drift")
    if {p.relative_to(root).as_posix() for p in (root/"supabase/migrations").glob("*.sql")}!={i["path"] for i in inputs if i["kind"]=="original-migration"}:raise ValueError("migration source set drift")
    for item in inputs:
        p=Path(item["path"]);p=p if p.is_absolute() else root/p
        if sha(required_bytes(p))!=item["sha256"]:raise ValueError("input drift: "+item["path"])
    paths=[Path(i["path"]) if Path(i["path"]).is_absolute() else root/i["path"] for i in inputs if i["kind"]=="effective-catalog"]
    admit_catalog_paths(paths)
    catalog=required_json(paths[0]);admit(catalog)
    for path in paths[1:]:
        peer=required_json(path);admit(peer)
        if canonical(peer)!=canonical(catalog):raise ValueError("peer catalog changed")
    objects=doc["objects"]
    identities={(o["kind"],o["identity"]) for o in objects}
    if len(identities)!=len(objects):raise ValueError("duplicate mapped object")
    for kind,key in [("schema","schemas"),("relation","relations"),("function","functions"),("type","types")]:
        raw=[o["catalog_row"] for o in objects if o["kind"]==kind]
        if raw!=catalog[key]:raise ValueError("catalog object coverage loss: "+kind)
    if doc["grants"]!=normalized_grants(catalog,objects):raise ValueError("ACL coverage loss")
    for key,rows in doc["catalog_supporting_records"].items():
        if rows!=catalog[key]:raise ValueError("supporting record coverage loss: "+key)
    if set(doc["catalog_supporting_records"])!=set(catalog)-{"schemas","relations","functions","types"}:raise ValueError("supporting category omitted")
    target_ids={o["identity"] for o in objects}
    for key in ["caller_sites","sql_reference_sites"]:
        if key in doc and not isinstance(doc[key],list):raise ValueError("generated category shape: "+key)
        for site in doc.get(key,[]):
            if any(t not in target_ids for t in site["candidate_targets"]):raise ValueError("invented target")
    for case in doc.get("reviewed_caller_seams",[]):
        source=required_bytes(root/case["path"])
        if sha(source)!=case["source_sha256"] or case["anchor"] not in source.decode():raise ValueError("reviewed seam source drift")
        if any(t not in target_ids for t in case["candidate_targets"]):raise ValueError("invented reviewed seam target")
    replay_paths=[Path(i["path"]) if Path(i["path"]).is_absolute() else root/i["path"] for i in inputs if i["kind"]=="replayed-original-migration"]
    replay_parents={p.parent for p in replay_paths}
    if len(replay_parents)>1:raise ValueError("replay migration inputs have multiple directories")
    replay_directory=next(iter(replay_parents)) if replay_parents else None
    # Recompute in an independent temporary output. No stored mapping, counter,
    # classification, resolution or gap supplies the expected result.
    with tempfile.TemporaryDirectory(prefix="collect-domain-map-recompute-") as tmp:
        expected=Path(tmp)/"generated"
        summary=build(root,paths,expected,replay_directory)
        for name in SEMANTIC_OUTPUTS:
            actual_bytes=required_bytes(output/name);expected_bytes=required_bytes(expected/name)
            if name.endswith(".json"):
                try:equal=canonical(json.loads(actual_bytes))==canonical(json.loads(expected_bytes))
                except (ValueError,UnicodeDecodeError) as error:raise ValueError("invalid generated JSON: "+name) from error
            else:equal=actual_bytes==expected_bytes
            if not equal:raise ValueError("semantic recomputation mismatch: "+name)
    return {"status":"PASS", "input_files_verified":len(inputs),"catalog_objects_verified":len(objects),"catalog_categories_preserved":len(catalog),"grants_verified":len(doc["grants"]),"semantic_output_files_verified":len(SEMANTIC_OUTPUTS),"verification_method":"full-independent-recomputation","catalog_matches_current_migration_names":summary["catalog_matches_current_migration_names"],"replayed_migration_bytes_match":summary["replayed_migration_bytes_match"],"acceptance":summary["acceptance"]}

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument("--root",type=Path,default=Path.cwd())
    parser.add_argument("--catalog",type=Path,action="append");parser.add_argument("--output",type=Path,required=True)
    parser.add_argument("--replay-migrations",type=Path)
    parser.add_argument("--require-current",action="store_true");parser.add_argument("--verify",action="store_true");args=parser.parse_args()
    if not args.verify and not args.catalog:parser.error("--catalog is required for generation")
    try:summary=verify_bundle(args.root.resolve(),args.output.resolve()) if args.verify else build(args.root.resolve(),[p.resolve() for p in args.catalog],args.output.resolve(),args.replay_migrations.resolve() if args.replay_migrations else None)
    except (ValueError,UnicodeDecodeError,KeyError,TypeError,OSError,json.JSONDecodeError) as e:print(str(e),file=sys.stderr);return 2
    print(json.dumps(summary,sort_keys=True))
    return 2 if args.require_current and (not summary["catalog_matches_current_migration_names"] or summary["replayed_migration_bytes_match"] is not True) else 0

if __name__=="__main__":sys.exit(main())
