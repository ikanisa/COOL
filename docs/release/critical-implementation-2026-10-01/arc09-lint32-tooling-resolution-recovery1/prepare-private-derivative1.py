from pathlib import Path
import copy,datetime,difflib,hashlib,json
root=Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL');release=root/'docs/release/critical-implementation-2026-10-01';old=release/'arc09-lint32.0.1-cache-preparation1';new=release/'arc09-lint32-tooling-resolution-recovery1'
if new.exists():raise SystemExit('recovery path exists')
def sha(raw):return hashlib.sha256(raw).hexdigest()
fences=json.loads((old/'source-fences.json').read_text())
for row in fences['inputs']:
 raw=Path(row['path']).read_bytes()
 if sha(raw)!=row['sha256'] or len(raw)!=row['bytes']:raise SystemExit('old fence drift: '+row['path'])
new.mkdir()
for rel in ['run_resolution.py','read_publisher_provenance.py','minimal-project/settings.gradle']:
 p=new/rel;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes((old/rel).read_bytes())
s=(old/'minimal-project/build.gradle').read_text();original=s
s=s.replace('import org.gradle.maven.MavenPomArtifact\n','import org.gradle.maven.MavenPomArtifact\nimport org.gradle.api.attributes.Usage\nimport org.gradle.api.attributes.java.TargetJvmEnvironment\n',1)
s=s.replace('configurations { exactLintTooling { transitive = true } }','''configurations {
    exactLintTooling {
        transitive = true
        attributes {
            attribute(Usage.USAGE_ATTRIBUTE, objects.named(Usage, Usage.JAVA_RUNTIME))
            attribute(TargetJvmEnvironment.TARGET_JVM_ENVIRONMENT_ATTRIBUTE,
                objects.named(TargetJvmEnvironment, TargetJvmEnvironment.STANDARD_JVM))
        }
    }
}''',1)
helper='''// Throwable/Gradle multi-cause printing retains the full nested failure trace.
// Preserve the original terse error fields as well for existing readers.
def failureDetails = { Throwable failure ->
    def text = new StringWriter()
    def writer = new PrintWriter(text)
    failure.printStackTrace(writer)
    writer.flush()
    [type: failure.class.name, message: failure.message, full_stack_trace: text.toString()]
}
def attributeRecords = { attributes ->
    attributes.keySet().sort { it.name }.collect { key ->
        def value = attributes.getAttribute(key)
        [name: key.name, type: key.type.name,
            value: value instanceof org.gradle.api.Named ? value.name : String.valueOf(value)]
    }
}

'''
s=s.replace("tasks.register('resolveExactLintTooling') {",helper+"tasks.register('resolveExactLintTooling') {",1)
s=s.replace('components: [], edges: [], artifacts: [], poms: [], errors: [],','components: [], edges: [], artifacts: [], poms: [], errors: [], failure_details: [],\n            requested_consumer_attributes: attributeRecords(configurations.exactLintTooling.attributes),',1)
s=s.replace('if (edge instanceof ResolvedDependencyResult) row.selected = edge.selected.id.displayName','''if (edge instanceof ResolvedDependencyResult) {
                        row.selected = edge.selected.id.displayName
                        row.selected_variant = [name: edge.resolvedVariant.displayName,
                            attributes: attributeRecords(edge.resolvedVariant.attributes)]
                    }''',1)
s=s.replace('row.unresolved = edge.failure.toString(); record.errors << row.unresolved','''row.unresolved = edge.failure.toString(); record.errors << row.unresolved
                        row.failure_details = failureDetails(edge.failure)
                        record.failure_details << [from: row.from, requested: row.requested,
                            detail: row.failure_details]''',1)
s=s.replace('record.errors << failure.toString()\n','record.errors << failure.toString()\n            record.failure_details << [phase: \'selected-tooling-collection\', detail: failureDetails(failure)]\n',1)
(new/'minimal-project/build.gradle').write_text(s)
patch=''.join(difflib.unified_diff(original.splitlines(keepends=True),s.splitlines(keepends=True),fromfile='a/minimal-project/build.gradle',tofile='b/minimal-project/build.gradle'));(new/'resolver-configuration.patch').write_text(patch)
updated=copy.deepcopy(fences);updated['captured_at_utc']=datetime.datetime.now(datetime.timezone.utc).isoformat();updated['kind']='private exact-lint isolated-consumer-attribute recovery';updated['original_preparation_source_fences_sha256']=sha((old/'source-fences.json').read_bytes());updated['source_context_rebinding']={'unchanged_external_inputs':15,'only_private_project_paths_replaced':2,'observed_old_external_input_drift':[],'retrospective_old_failure_cause_unavailable':True}
for row in updated['inputs']:
 if row['path'].startswith(str(old/'minimal-project')+'/'):
  row['original_private_source']=copy.deepcopy(row);row['path']=str(new/'minimal-project'/Path(row['path']).name);raw=Path(row['path']).read_bytes();row['sha256']=sha(raw);row['bytes']=len(raw)
(new/'source-fences.json').write_text(json.dumps(updated,indent=2)+'\n')
commands=copy.deepcopy(json.loads((old/'commands.json').read_text()))
commands['status']='UNEXECUTED_ROOT_REVIEW_RECOVERY';commands['original_failure_graph_sha256']='874a4c20281347dd0c53a677f094c8d5ea61aee6321cf2aa261d3905defd1061'
commands['sequential_commands'][0]['argv'][1]=str(new/'run_resolution.py');commands['sequential_commands'][0]['argv'][3]=sha((new/'source-fences.json').read_bytes());commands['sequential_commands'][0]['argv'][5]=str(release/'root-lint32-tooling-resolution-recovery1')
commands['sequential_commands'][1]['argv'][1]=str(new/'read_publisher_provenance.py');commands['sequential_commands'][1]['argv'][-1]=str(release/'root-lint32-publisher-recovery-readback1')
(new/'commands.json').write_text(json.dumps(commands,indent=2)+'\n')
metadata=Path('/Users/jeanbosco/Library/Caches/COOL-ARC09/native-consumer1/gradle-home/caches/modules-2/files-2.1/com.google.guava/guava/33.3.1-jre/c99293bbf166d01849489fc6f94a101f79072aa7/guava-33.3.1-jre.module')
(new/'observed-guava-33.3.1-jre.module.json').write_bytes(metadata.read_bytes())
reference_paths=[metadata,old/'packet-files.json',old/'source-fences.json',old/'minimal-project/build.gradle',release/'root-lint32-tooling-resolution1/selected-tooling-graph.json',release/'root-lint32-tooling-resolution1/readback.json',release/'root-lint32-tooling-resolution1/exact-lint32-tooling-resolution.json']
dist=Path('/Users/jeanbosco/Library/Caches/COOL-ARC09/native-consumer1/gradle-home/wrapper/dists/gradle-9.1.0-all/7wzd0jkjit61aq2p43wpjgij9/gradle-9.1.0')
reference_paths.extend([dist/'src/jvm-services/org/gradle/api/internal/artifacts/JavaEcosystemSupport.java',dist/'src/stdlib-java-extensions/org/gradle/internal/exceptions/DefaultMultiCauseException.java',dist/'src/core-api/org/gradle/api/artifacts/ResolveException.java'])
reference_rows=[{'path':str(p),'sha256':sha(p.read_bytes()),'bytes':len(p.read_bytes())} for p in reference_paths]
(new/'reference-source-fences-before.json').write_text(json.dumps({'sources':reference_rows,'module_source_status':'observed cached publisher metadata; independent publisher reacquisition not performed','Gradle_version':'9.1.0','primary_docs':[{'url':'https://docs.gradle.org/current/userguide/variant_attributes.html','scope':'standard JVM consumer attribute meanings; current docs later than installed version'},{'url':'https://docs.gradle.org/current/javadoc/org/gradle/api/artifacts/ResolveException.html','scope':'multi-cause trace API; installed 9.1.0 source read separately'}],'web_fetch_limitations':['Versioned 9.1.0 web documentation and direct Maven Central .module URL were unavailable through the web tool; no claim of live publisher byte verification.']},indent=2)+'\n')
print(json.dumps({'directory':str(new),'proposed_build_sha256':sha(s.encode()),'source_fences_sha256':sha((new/'source-fences.json').read_bytes()),'patch_sha256':sha(patch.encode()),'runner_unchanged':(new/'run_resolution.py').read_bytes()==(old/'run_resolution.py').read_bytes(),'publisher_reader_unchanged':(new/'read_publisher_provenance.py').read_bytes()==(old/'read_publisher_provenance.py').read_bytes(),'private_settings_unchanged':(new/'minimal-project/settings.gradle').read_bytes()==(old/'minimal-project/settings.gradle').read_bytes()}))
