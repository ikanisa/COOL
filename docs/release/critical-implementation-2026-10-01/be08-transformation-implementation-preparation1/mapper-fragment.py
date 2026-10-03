def transformation_signature(arguments):
    """Candidate identity only; do not expand the admitted lineage type grammar."""
    text="("+arguments+")";tokens=lex(text,sql=True)
    tokens=[Token(t.kind,"timestamp with time zone" if t.kind=="id" and
                  t.value.lower()=="timestamptz" and text[t.start:t.start+1]!='"' else t.value,
                  t.start,t.end) for t in tokens]
    signature,closing=sql_signature(text,tokens,0)
    return signature if closing==len(tokens)-1 else None

def sql_transformation_candidates(text, path, version):
    """Syntactic DO hints only. Never execute SQL or reconstruct expected bodies.

    Exact spans refer to character offsets in the original UTF-8 source text.
    All anonymous-effect fences remain in sql_lineage_uncertainty unchanged.
    """
    result=[];outer=lex(text,sql=True)
    safe_name=r"[a-z_][a-z_0-9]*"
    def reference(value):
        m=re.fullmatch(r"("+safe_name+r")\.("+safe_name+r")\((.*)\)",value,re.S)
        if not m:return None
        return {"schema":m[1],"name":m[2],"signature_types":transformation_signature(m[3]),
                "literal_regprocedure":value}
    def arguments(tokens,opening):
        if opening>=len(tokens) or tokens[opening].value!="(":return None,None
        parts=[];start=opening+1;depth=1
        for j in range(start,len(tokens)):
            t=tokens[j]
            if t.kind=="symbol" and t.value=="(":depth+=1
            elif t.kind=="symbol" and t.value==")":
                depth-=1
                if not depth:return [*parts,tokens[start:j]],j
            elif t.kind=="symbol" and t.value=="," and depth==1:
                parts.append(tokens[start:j]);start=j+1
        return None,None
    def get_reference(tokens):
        # Refuse OIDs, regproc, search_path-dependent and expression-built names.
        if len(tokens)!=7 or [t.value.lower() for t in tokens[:2]]!=["pg_get_functiondef","("]:
            return None
        if tokens[2].kind!="string" or [t.value.lower() for t in tokens[3:]]!=[":",":","regprocedure",")"]:
            return None
        return reference(tokens[2].value)
    for i,token in enumerate(outer):
        if token.kind!="id" or token.value.lower()!="do" or (i and outer[i-1].value!=";"):
            continue
        if i+2>=len(outer) or outer[i+1].kind!="string" or outer[i+2].value!=";":continue
        block=outer[i+1];raw=text[block.start:block.end]
        delimiter=re.match(r"\$(?:[A-Za-z_][A-Za-z_0-9]*)?\$",raw)
        if not delimiter or not raw.endswith(delimiter[0]):continue
        base=block.start+len(delimiter[0]);body=block.value;tokens=lex(body,sql=True)
        def span(start,end):
            return {"path":path,"version":version,"line":text.count("\n",0,start)+1,
                    "start_character_offset":start,"end_character_offset":end,
                    "sha256":sha(text[start:end].encode())}
        block_span=span(token.start,outer[i+2].end)
        def expression(part):
            return {"source_span":span(base+part[0].start,base+part[-1].end),
                    "evaluation_performed":False} if part else None
        common={"candidate_format":"collect-function-transformation-candidate-v1",
                "source_migration_sha256":sha(text.encode()),"anonymous_block":block_span,
                "expected_body_computed":False,"expected_body_hash_match":None,
                "lineage_complete":False,"resolved":False,"dynamic_SQL_evaluation_performed":False}
        assignments={}
        for j,t in enumerate(tokens):
            # Store only the nearest textual assignment, not a PL/pgSQL dataflow result.
            assignment=j+2 if j+1<len(tokens) and tokens[j+1].value.lower()=="text" else j+1
            if t.kind=="id" and body[t.start:t.start+1]!='"' and assignment+1<len(tokens) and [x.value for x in tokens[assignment:assignment+2]]==[":","="]:
                end=next((k for k in range(assignment+2,len(tokens)) if tokens[k].kind=="symbol" and tokens[k].value==";"),len(tokens))
                assignments[t.value.lower()]=tokens[assignment+2:end]
            if t.kind!="id" or t.value.lower()!="execute" or j+2>=len(tokens) or tokens[j+1].value.lower()!="replace":continue
            parts,closing=arguments(tokens,j+2)
            if parts is None or len(parts)!=3 or closing+1>=len(tokens) or tokens[closing+1].value!=";":continue
            predecessor=get_reference(parts[0])
            if predecessor is None and len(parts[0])==1 and parts[0][0].kind=="id":
                predecessor=get_reference(assignments.get(parts[0][0].value.lower(),[]))
            if predecessor is None:continue
            target=dict(predecessor);operation="function-definition-replace"
            # Header spelling is a hint: body collisions and pg_get_functiondef
            # canonical header bytes remain unproved; no body equality is asserted.
            if all(len(p)==1 and p[0].kind=="string" for p in parts[1:]):
                needle,replacement=(p[0].value for p in parts[1:])
                header="FUNCTION "+predecessor["schema"]+"."+predecessor["name"]+"("
                destination=re.fullmatch(r"FUNCTION ("+safe_name+r")\.("+safe_name+r")\(",replacement)
                if needle==header and destination:
                    operation="function-definition-header-copy"
                    target={"schema":destination[1],"name":destination[2],
                            "signature_types":predecessor["signature_types"]}
            assigned=[]
            for part in parts[1:]:
                source=assignments.get(part[0].value.lower()) if len(part)==1 and part[0].kind=="id" else None
                assigned.append(expression(source) if source else None)
            result.append({**common,"operation":operation,"target":target,"predecessor":predecessor,
                "identity_binding":"literal-regprocedure-signature" if target["signature_types"] is not None else "name-only-unsupported-signature",
                "operation_source":span(base+t.start,base+tokens[closing+1].end),
                "replace_argument_expressions":[expression(p) for p in parts],
                "nearest_textual_replacement_assignments":assigned,
                "limitations":["anonymous effects and variable/control-flow state unproved",
                               "replacement scope and literal/E-string decoding unproved",
                               "predecessor installed state and effective history unproved"]})
        # Finite inventory form used by roster recovery. Exact template spelling
        # binds the hint; pg_proc overloads, ordered names/defaults and guards
        # remain catalog-dependent and are not evaluated or admitted here.
        inventory=[];suffix=None;formats={}
        values=[t.value for t in tokens]
        for j,t in enumerate(tokens):
            if values[j:j+8]==["entries","text","[","]",":","=","array","["]:
                end=next((k for k in range(j+8,len(tokens)) if tokens[k].value=="]"),None)
                items=tokens[j+8:end] if end is not None else []
                if items and len(items)%2 and all(x.kind=="string" and re.fullmatch(safe_name,x.value) if k%2==0 else x.value=="," for k,x in enumerate(items)):
                    inventory=sorted({x.value for x in items if x.kind=="string"})
            if values[j:j+7]==["alias_name",":","=","f",".","proname","|"] and j+9<len(tokens) and values[j+7]=="|" and tokens[j+8].kind=="string" and values[j+9]==";":
                suffix=tokens[j+8].value if re.fullmatch(safe_name,tokens[j+8].value) else None
            if values[j:j+3]==["execute","format","("]:
                parts,closing=arguments(tokens,j+2)
                if parts and len(parts[0])==1 and parts[0][0].kind=="string" and closing+1<len(tokens) and values[closing+1]==";":
                    formats[parts[0][0].value]=(j,closing,parts)
        move="alter function public.%I(%s) set schema collect_hybrid"
        rename="alter function collect_hybrid.%I(%s) rename to %I"
        template="create function public.%I(%s) returns jsonb language plpgsql security definer set search_path='' as $fn$\n   begin %s return collect_hybrid.%I(%s); end $fn$ "
        query=["n",".","nspname","=","public","and","p",".","proname","=","any","(","entries",")"]
        if not(inventory and suffix and all(f in formats for f in [move,rename,template]) and any(values[j:j+len(query)]==query for j in range(len(values)))):continue
        expected=[["f",".","proname"],["f",".","identity_args"]]
        if [[t.value for t in p] for p in formats[move][2][1:]]!=expected:continue
        if [[t.value for t in p] for p in formats[rename][2][1:]]!=[*expected,["alias_name"]]:continue
        wrapper_arguments=[["f",".","proname"],["f",".","declaration"],["guard_sql"],["alias_name"],["arguments"]]
        if [[t.value for t in p] for p in formats[template][2][1:]]!=wrapper_arguments:continue
        for name in inventory:
            predecessor={"schema":"public","name":name,"signature_types":None}
            for operation,target,keys in [
                ("finite-inventory-private-move-rename",{"schema":"collect_hybrid","name":name+suffix,"signature_types":None},[move,rename]),
                ("finite-inventory-generated-wrapper",dict(predecessor),[template])]:
                result.append({**common,"operation":operation,"target":target,"predecessor":predecessor,
                    "identity_binding":"name-only-catalog-dependent-predecessor",
                    "operation_sources":[span(base+tokens[formats[k][0]].start,base+tokens[formats[k][1]+1].end) for k in keys],
                    "format_template_sha256":[sha(k.encode()) for k in keys],"literal_inventory":inventory,
                    "literal_alias_suffix":suffix,
                    "limitations":["catalog-derived predecessor overloads/arguments/defaults unproved",
                                   "guard branches and format semantics not evaluated",
                                   "anonymous effects and installed history unproved"]})
    return sorted(result,key=lambda c:(c["anonymous_block"]["start_character_offset"],
                   c.get("operation_source",c["anonymous_block"])["start_character_offset"],
                   c["operation"],c["target"]["schema"],c["target"]["name"]))

def transformation_candidate_review(obj, definitions, transformations):
    """Attach identity candidates without participating in any match decision."""
    signature=transformation_signature(obj["catalog_row"][2]);result=[]
    for candidate in transformations:
        target=candidate["target"]
        if (target["schema"],target["name"])!=(obj["schema"],obj["name"]):continue
        if target["signature_types"] is not None and target["signature_types"]!=signature:continue
        predecessor=candidate["predecessor"]
        source_candidates=[{k:v for k,v in d.items() if k not in {"body","body_offset","definition_offset"}}
            for d in definitions if (d["schema"],d["name"])==(predecessor["schema"],predecessor["name"])
            and d["signature_types"] is not None and predecessor["signature_types"] is not None
            and d["signature_types"]==predecessor["signature_types"]
            and (d["version"],d["definition_offset"])<(candidate["anonymous_block"]["version"],candidate["anonymous_block"]["start_character_offset"])]
        result.append({**candidate,"catalog_identity":obj["identity"],
                       "required_final_prosrc_sha256":obj["prosrc_sha256"],
                       "predecessor_source_definition_candidates":source_candidates,
                       "predecessor_candidates_are_installed_state":False})
    return result
