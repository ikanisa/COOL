from pathlib import Path
base=Path(__file__).parent
p=base/'proposal/scripts/audits/collect_schema_domain_map.py'
s=p.read_text()
anchor='def sql_transformation_candidates(text, path, version):\n'
helper='''def dollarquoted_replacement_recipes(body, tokens):
    """Recognize a bounded straightline DO subset; this does not execute PL/pgSQL.

    Only body/needle/replacement text variables, dollarquoted literal values,
    literal regprocedure reads and two raise-on-drift guards are admitted.
    Any other statement, branch, expression or write rejects the whole block.
    """
    recipes={};values={};declared=set();j=0
    def spelling(part):return [t.value.lower() if t.kind=="id" else t.value for t in part]
    def dollar(part):
        if len(part)!=1 or part[0].kind!="string":return None
        t=part[0];raw=body[t.start:t.end]
        m=re.match(r"\\$(?:[A-Za-z_][A-Za-z_0-9]*)?\\$",raw)
        return t if m and raw.endswith(m[0]) and raw==m[0]+t.value+m[0] else None
    def statement(start):
        end=next((k for k in range(start,len(tokens)) if tokens[k].kind=="symbol" and tokens[k].value==";"),None)
        return (tokens[start:end],end+1) if end is not None else (None,None)
    if not tokens or spelling(tokens[:1])!=["declare"]:return {}
    j=1
    while j<len(tokens) and spelling(tokens[j:j+1])!=["begin"]:
        part,end=statement(j)
        if part is None or len(part)<2 or part[0].kind!="id" or body[part[0].start:part[0].start+1]=='"':return {}
        name=part[0].value.lower()
        if name not in {"body","needle","replacement"} or name in declared or spelling(part[1:2])!=["text"]:return {}
        declared.add(name)
        if len(part)>2:
            literal=dollar(part[4:]) if spelling(part[2:4])==[":","="] else None
            if name=="body" or literal is None:return {}
            values[name]=literal
        j=end
    if declared!={"body","needle","replacement"} or j>=len(tokens):return {}
    j+=1
    getdef=["body",":","=","pg_get_functiondef","("]
    while j<len(tokens):
        if spelling(tokens[j:]) in [["end"],["end",";"]]:return recipes
        part,end=statement(j)
        if part is None or len(part)!=11 or spelling(part[:5])!=getdef or part[5].kind!="string" or spelling(part[6:])!=[":",":","regprocedure",")"]:return {}
        if body[part[5].start:part[5].start+1]!="'":return {}
        predecessor=part;j=end
        while j<len(tokens) and spelling(tokens[j:j+1]) in [["needle"],["replacement"]]:
            part,end=statement(j)
            if part is None or spelling(part[1:3])!=[":","="]:return {}
            literal=dollar(part[3:]);name=part[0].value.lower()
            if literal is None or name in values:return {}
            values[name]=literal;j=end
        if set(values)!={"needle","replacement"}:return {}
        guard_start=j;part,end=statement(j)
        if part is None:return {}
        condition1=["if","strpos","(","body",",","needle",")","=","0","then","raise","exception"]
        condition2=["if","(","length","(","body",")","-","length","(","replace","(","body",",","needle",",","", ")", ")", ")", "/", "length", "(", "needle", ")", "<", ">", "1", "then", "raise", "exception"]
        prefix=condition1 if spelling(part[:len(condition1)])==condition1 else condition2 if spelling(part[:len(condition2)])==condition2 else None
        tail=part[len(prefix):] if prefix else []
        if len(tail)!=6 or tail[0].kind!="string" or spelling(tail[1:5])!=["using","errcode","=","55000"] or tail[5].value!="unexpected":
            # The exception tail has four tokens after its message: USING,
            # ERRCODE, '=', '55000'; no handler/ELSE or additional effects.
            if not(prefix and len(tail)==5 and tail[0].kind=="string" and tail[4].kind=="string" and spelling(tail[1:])==["using","errcode","=","55000"]):return {}
        j=end
        if spelling(tokens[j:j+3])!=["end","if",";"]:return {}
        j+=3;guard=tokens[guard_start:j]
        part,end=statement(j)
        if part is None or spelling(part)!=["execute","replace","(","body",",","needle",",","replacement",")"]:return {}
        recipes[part[0].start]={"predecessor":predecessor,"needle":values["needle"],"replacement":values["replacement"],"guard":guard}
        values={};j=end
    return {}

'''
# Correct the tightly scoped exception-tail test directly before writing.
start=helper.index('        if len(tail)!=6')
finish=helper.index('        j=end\n',start)
helper=helper[:start]+'''        if not(prefix and len(tail)==5 and tail[0].kind=="string" and tail[4].kind=="string" and spelling(tail[1:])==["using","errcode","=","55000"]):return {}
'''+helper[finish:]
# The literal get_functiondef assignment has ten lexer tokens including body.
helper=helper.replace('len(part)!=11','len(part)!=10')
s=s.replace(anchor,helper+anchor,1)
s=s.replace('"""Syntactic DO hints only. Never execute SQL or reconstruct expected bodies.','"""Syntactic DO hints and bounded literal recipes; never execute SQL.',1)
s=s.replace('base=block.start+len(delimiter[0]);body=block.value;tokens=lex(body,sql=True)\n','base=block.start+len(delimiter[0]);body=block.value;tokens=lex(body,sql=True)\n        literal_recipes=dollarquoted_replacement_recipes(body,tokens)\n',1)
s=s.replace('            result.append({**common,"operation":operation,"target":target,"predecessor":predecessor,\n','''            recipe=literal_recipes.get(t.start)
            literal_recipe={}
            if recipe:
                def literal_evidence(value):
                    return {"value":value.value,"source_span":span(base+value.start,base+value.end),
                            "value_sha256":sha(value.value.encode()),"value_utf8_bytes":len(value.value.encode())}
                literal_recipe={"_literal_replacement_recipe":{
                    "needle":literal_evidence(recipe["needle"]),"replacement":literal_evidence(recipe["replacement"]),
                    "predecessor_assignment_source":span(base+recipe["predecessor"][0].start,base+recipe["predecessor"][-1].end),
                    "guard_source":span(base+recipe["guard"][0].start,base+recipe["guard"][-1].end)}}
            result.append({**common,**literal_recipe,"operation":operation,"target":target,"predecessor":predecessor,
''',1)
anchor='def transformation_candidate_review(obj, definitions, transformations):\n'
helper='''def literal_replacement_computation(candidate, definitions, migration_texts, required_hash):
    """Compute one raw literal prosrc candidate without admitting its lineage."""
    recipe=candidate.get("_literal_replacement_recipe")
    if not recipe:return None
    result={"computation_format":"collect-literal-prosrc-replacement-candidate-v1",
            "evaluation_scope":"raw-literal-prosrc-body-candidate",
            "predecessor_assignment_source":recipe["predecessor_assignment_source"],
            "guard_source":recipe["guard_source"],
            "needle_literal":{k:v for k,v in recipe["needle"].items() if k!="value"},
            "replacement_literal":{k:v for k,v in recipe["replacement"].items() if k!="value"},
            "computed":False,"catalog_prosrc_hash_match":None,
            "installed_predecessor_state_verified":False,"pg_get_functiondef_ddl_evaluated":False,
            "dynamic_SQL_evaluation_performed":False,"lineage_complete":False,"resolved":False}
    predecessor=candidate["predecessor"];target=candidate["target"]
    if candidate["operation"]!="function-definition-replace" or predecessor["signature_types"] is None or any(target[k]!=predecessor[k] for k in ["schema","name","signature_types"]):
        return {**result,"reason":"unsupported-target-or-signature"}
    sources=[d for d in definitions if d["routine_kind"]=="function"
             and (d["schema"],d["name"],d["signature_types"])==(predecessor["schema"],predecessor["name"],predecessor["signature_types"])
             and (d["version"],d["definition_offset"])<(candidate["anonymous_block"]["version"],candidate["anonymous_block"]["start_character_offset"])]
    if len(sources)!=1:return {**result,"reason":"literal-predecessor-not-unique","predecessor_definition_count":len(sources)}
    source=sources[0];text=migration_texts.get((source["path"],source["version"]))
    if text is None:return {**result,"reason":"predecessor-source-bytes-unavailable"}
    admitted=[d for d in sql_definitions(text,source["path"],source["version"]) if d==source]
    body_token=next((t for t in lex(text,sql=True) if t.kind=="string" and t.value==source["body"] and
                     re.match(r"\\$(?:[A-Za-z_][A-Za-z_0-9]*)?\\$",text[t.start:]) and
                     t.start+len(re.match(r"\\$(?:[A-Za-z_][A-Za-z_0-9]*)?\\$",text[t.start:])[0])==source["body_offset"]),None)
    if len(admitted)!=1 or body_token is None or sha(source["body"].encode())!=source["prosrc_sha256"]:
        return {**result,"reason":"predecessor-not-exact-dollarquoted-source"}
    needle=recipe["needle"]["value"];replacement=recipe["replacement"]["value"]
    count=source["body"].count(needle) if needle else 0
    if count!=1:return {**result,"reason":"needle-not-exactly-once-in-literal-prosrc","needle_occurrences":count}
    raw=source["body"].replace(needle,replacement).encode();expected=sha(raw)
    body_start=source["body_offset"];body_end=body_start+len(source["body"])
    proof={"path":source["path"],"version":source["version"],"line":text.count("\\n",0,body_start)+1,
           "start_character_offset":body_start,"end_character_offset":body_end,
           "sha256":source["prosrc_sha256"],"utf8_bytes":len(source["body"].encode()),
           "source_migration_sha256":sha(text.encode()),"declaration_sha256":source["declaration_sha256"]}
    return {**result,"computed":True,"reason":"exact-dollarquoted-literal-body-candidate",
            "predecessor_literal_body":proof,"needle_occurrences":count,
            "computed_prosrc_utf8_bytes":len(raw),"computed_prosrc_sha256":expected,
            "catalog_prosrc_hash_match":expected==required_hash}

'''
s=s.replace(anchor,helper+'def transformation_candidate_review(obj, definitions, transformations, migration_texts=None):\n',1)
s=s.replace('        result.append({**candidate,"catalog_identity":obj["identity"],\n','''        public={k:v for k,v in candidate.items() if not k.startswith("_")}
        computation=literal_replacement_computation(candidate,definitions,migration_texts or {},obj["prosrc_sha256"])
        if computation:
            public["literal_replacement_computation"]=computation
            public["expected_body_computed"]=computation["computed"]
            public["expected_body_hash_match"]=computation["catalog_prosrc_hash_match"]
            if computation["computed"]:
                public["limitations"]=["anonymous effects and installed predecessor state unproved",
                    "raw literal prosrc candidate computed; pg_get_functiondef DDL replacement scope unproved",
                    "predecessor installed state and effective history unproved"]
        result.append({**public,"catalog_identity":obj["identity"],
''',1)
s=s.replace('def function_source_review(obj, definitions, lineage_candidates, matches, transformations=()):','def function_source_review(obj, definitions, lineage_candidates, matches, transformations=(), migration_texts=None):',1)
s=s.replace('transformation_candidate_review(obj,definitions,transformations)}','transformation_candidate_review(obj,definitions,transformations,migration_texts)}',1)
s=s.replace('transformations=[]; versions=[]','transformations=[]; versions=[]; migration_texts={}',1)
s=s.replace('        definitions.extend(sql_definitions(raw.decode("utf-8"),relative,version))','        migration_texts[(relative,version)]=raw.decode("utf-8")\n        definitions.extend(sql_definitions(raw.decode("utf-8"),relative,version))',1)
s=s.replace('function_source_review(obj,admitted_definitions,candidates,matches,admitted_transformations)','function_source_review(obj,admitted_definitions,candidates,matches,admitted_transformations,migration_texts)',1)
p.write_text(s)
print('Private evaluator proposal written')
