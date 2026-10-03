from pathlib import Path
import copy,datetime,difflib,hashlib,json
release=Path(__file__).resolve().parent;old=release/'arc09-lint32-tooling-resolution-recovery1';new=release/'arc09-lint32-tooling-resolution-recovery2'
if new.exists():raise SystemExit('recovery2 exists')
def sha(raw):return hashlib.sha256(raw).hexdigest()
fences=json.loads((old/'source-fences.json').read_text())
for row in fences['inputs']:
 raw=Path(row['path']).read_bytes()
 if sha(raw)!=row['sha256'] or len(raw)!=row['bytes']:raise SystemExit('fence drift: '+row['path'])
new.mkdir()
for rel in ['run_resolution.py','read_publisher_provenance.py','minimal-project/settings.gradle']:
 p=new/rel;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes((old/rel).read_bytes())
s=(old/'minimal-project/build.gradle').read_text();original=s
s=s.replace('import java.security.MessageDigest\n','import java.security.MessageDigest\nimport java.nio.file.Files\nimport java.nio.file.StandardCopyOption\n',1)
variant='''def variantRecord = { variant ->
    def external = variant.externalVariant
    [name: variant.displayName, owner: variant.owner.displayName,
        attributes: attributeRecords(variant.attributes),
        capabilities: variant.capabilities.collect { [group: it.group, name: it.name, version: it.version] },
        external_variant: external.present ? [name: external.get().displayName,
            owner: external.get().owner.displayName, attributes: attributeRecords(external.get().attributes),
            capabilities: external.get().capabilities.collect { [group: it.group, name: it.name, version: it.version] },
            further_external_variant_present: external.get().externalVariant.present] : null]
}
// Each completed checkpoint has its own immutable leaf. The latest output is
// atomically replaced from the same directory, so interruption cannot erase it.
def persistCheckpoint = { File output, Map record, String phase ->
    int sequence = record.checkpoints.size()
    if (sequence >= 8) throw new GradleException('Checkpoint count bound exceeded')
    def leaf = new File(output.parentFile, output.name + '.checkpoint-' + sequence + '.json')
    if (leaf.exists()) throw new GradleException('Checkpoint leaf already exists')
    record.phase = phase
    record.counts = [components: record.components.size(), edges: record.edges.size(),
        artifacts: record.artifacts.size(), poms: record.poms.size()]
    record.checkpoints << [sequence: sequence, phase: phase, path: leaf.canonicalPath]
    byte[] encoded = (JsonOutput.prettyPrint(JsonOutput.toJson(record)) + '\\n').getBytes('UTF-8')
    def saved = new FileOutputStream(leaf)
    try { saved.write(encoded); saved.flush(); saved.fd.sync() } finally { saved.close() }
    def pending = new File(output.parentFile, output.name + '.pending-' + sequence)
    if (pending.exists()) throw new GradleException('Pending checkpoint leaf already exists')
    Files.copy(leaf.toPath(), pending.toPath())
    Files.move(pending.toPath(), output.toPath(), StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
}

'''
s=s.replace("tasks.register('resolveExactLintTooling') {",variant+"tasks.register('resolveExactLintTooling') {",1)
s=s.replace("        def target = providers.gradleProperty('collectLintGraphOutput').get()","""        def mode = providers.gradleProperty('collectLintMetadataOnly').getOrElse('false')
        if (!(mode in ['true', 'false'])) throw new GradleException('Unknown metadata-only mode')
        boolean metadataOnly = mode == 'true'
        def target = providers.gradleProperty('collectLintGraphOutput').get()""",1)
s=s.replace('complete_selected_tooling_graph: false, publisher_admission_complete: false,','''metadata_only_requested: metadataOnly, complete_selected_tooling_metadata: false,
            complete_selected_tooling_graph: false, publisher_admission_complete: false,
            selected_variant_filenames_inferred: false,
            artifact_filename_admission: 'Requires selected variant owner/name/attributes plus exact publisher module/POM file evidence; default JAR names are not projected',
            checkpoints: [],''',1)
s=s.replace('        try {\n            def result = configurations.exactLintTooling.incoming.resolutionResult','        persistCheckpoint(output, record, \'before-selected-metadata-resolution\')\n        try {\n            def result = configurations.exactLintTooling.incoming.resolutionResult',1)
s=s.replace('id: id.displayName, selection_reasons: component.selectionReason.descriptions.collect {','id: id.displayName, selected_variants: component.variants.collect { variantRecord(it) },\n                        selection_reasons: component.selectionReason.descriptions.collect {',1)
s=s.replace("record.components << [kind: 'isolated-root-project', id: id.displayName]","record.components << [kind: 'isolated-root-project', id: id.displayName,\n                        selected_variants: component.variants.collect { variantRecord(it) }]",1)
s=s.replace('row.selected_variant = [name: edge.resolvedVariant.displayName,\n                            attributes: attributeRecords(edge.resolvedVariant.attributes)]','row.selected_variant = variantRecord(edge.resolvedVariant)',1)
s=s.replace("            if (record.errors) throw new GradleException('Unresolved selected tooling dependencies')","            persistCheckpoint(output, record, 'selected-components-edges-variants')\n            if (record.errors) throw new GradleException('Unresolved selected tooling dependencies')",1)
start=s.index('            def artifacts = configurations.exactLintTooling.resolvedConfiguration.resolvedArtifacts')
end=s.index('            def modules = components.findAll',start)
artifacts=s[start:end];s=s[:start]+s[end:]
anchor="            if (record.errors) throw new GradleException('POM metadata coverage incomplete')\n"
replacement="""            persistCheckpoint(output, record, 'selected-POM-results')
            if (record.errors) throw new GradleException('POM metadata coverage incomplete')
            record.complete_selected_tooling_metadata = true
            persistCheckpoint(output, record, 'selected-metadata-complete-before-binaries')
            if (metadataOnly) return
"""+artifacts
s=s.replace(anchor,replacement,1)
s=s.replace("            record.counts = [components: record.components.size(), edges: record.edges.size(), artifacts: record.artifacts.size(), poms: record.poms.size()]\n            output.text = JsonOutput.prettyPrint(JsonOutput.toJson(record)) + '\\n'","            persistCheckpoint(output, record, 'finished')",1)
(new/'minimal-project/build.gradle').write_text(s)
runner=(new/'run_resolution.py').read_text();oldrunner=runner
runner=runner.replace("    parser.add_argument('--output', required=True, type=Path)","    parser.add_argument('--output', required=True, type=Path)\n    parser.add_argument('--metadata-only', action='store_true')",1)
runner=runner.replace("    label = 'exact-lint32-tooling-resolution'","    label = 'exact-lint32-tooling-metadata' if args.metadata_only else 'exact-lint32-tooling-resolution'",1)
runner=runner.replace("        '-PcollectLintGraphOutput=' + str(output / 'selected-tooling-graph.json'), 'resolveExactLintTooling']","        '-PcollectLintGraphOutput=' + str(output / 'selected-tooling-graph.json'),\n        '-PcollectLintMetadataOnly=' + ('true' if args.metadata_only else 'false'), 'resolveExactLintTooling']",1)
runner=runner.replace("        if graph.get('complete_selected_tooling_graph') is not True or graph.get('errors'):","        required_complete = 'complete_selected_tooling_metadata' if args.metadata_only else 'complete_selected_tooling_graph'\n        if graph.get(required_complete) is not True or graph.get('metadata_only_requested') is not args.metadata_only or graph.get('errors'):",1)
runner=runner.replace("    driver.save(output / 'readback.json', {'schema_version': 1,","""    checkpoints = []
    checkpoint_paths = sorted(output.glob('selected-tooling-graph.json.checkpoint-*.json'))
    if len(checkpoint_paths) > 8:
        errors.append({'error': 'Checkpoint count exceeds reviewed bound'})
    else:
        for path in checkpoint_paths:
            checkpoint_raw = driver.plain_read(path)
            checkpoint = json.loads(checkpoint_raw)
            checkpoints.append({'path': str(path), 'sha256': digest(checkpoint_raw), 'bytes': len(checkpoint_raw),
                'phase': checkpoint.get('phase'), 'counts': checkpoint.get('counts'),
                'complete_selected_tooling_metadata': checkpoint.get('complete_selected_tooling_metadata'),
                'complete_selected_tooling_graph': checkpoint.get('complete_selected_tooling_graph')})
    driver.save(output / 'readback.json', {'schema_version': 1,""",1)
runner=runner.replace("        'daemon_readback': daemon, 'selected_graph': graph_row, 'errors': errors,","        'daemon_readback': daemon, 'selected_graph': graph_row, 'checkpoints': checkpoints, 'errors': errors,\n        'metadata_only_requested': args.metadata_only,\n        'metadata_only_success_is_not_full_graph_or_publisher_admission': True,",1)
(new/'run_resolution.py').write_text(runner)
patch=''
for rel,original,newtext in [('minimal-project/build.gradle',original,s),('run_resolution.py',oldrunner,runner)]:
 patch+=''.join(difflib.unified_diff(original.splitlines(keepends=True),newtext.splitlines(keepends=True),fromfile='a/'+rel,tofile='b/'+rel))
(new/'metadata-checkpoint.patch').write_text(patch)
updated=copy.deepcopy(fences);updated['captured_at_utc']=datetime.datetime.now(datetime.timezone.utc).isoformat();updated['kind']='private exact-lint metadata-first checkpoint recovery2';updated['recovery1_source_fences_sha256']=sha((old/'source-fences.json').read_bytes())
for row in updated['inputs']:
 if row['path'].startswith(str(old/'minimal-project')+'/'):
  row['recovery1_private_source']=copy.deepcopy(row);row['path']=str(new/'minimal-project'/Path(row['path']).name);raw=Path(row['path']).read_bytes();row['sha256']=sha(raw);row['bytes']=len(raw)
(new/'source-fences.json').write_text(json.dumps(updated,indent=2)+'\n')
commands=copy.deepcopy(json.loads((old/'commands.json').read_text()));commands['status']='UNEXECUTED_PRIVATE_METADATA_FIRST_RECOVERY2';one=commands['sequential_commands'][0];one['argv'][1]=str(new/'run_resolution.py');one['argv'][3]=sha((new/'source-fences.json').read_bytes());one['argv'][5]=str(release/'root-lint32-tooling-metadata-resolution2');one['argv'].append('--metadata-only');one['label']='exact-lint32-tooling-metadata';commands['sequential_commands'][1]['argv'][1]=str(new/'read_publisher_provenance.py');commands['sequential_commands'][1]['metadata_checkpoint_is_not_an_eligible_full_graph']=True;commands['intervening_binary_filename_publisher_binding_and_actual_Gradle_graph_compare_are_root_owned']=True;commands['automatic_advance_from_metadata_to_artifacts']=False
(new/'commands.json').write_text(json.dumps(commands,indent=2)+'\n')
references=[old/'packet-files.json',old/'static-readback.json',old/'minimal-project/build.gradle',old/'run_resolution.py',release/'root-lint32-tooling-resolution-recovery1/exact-lint32-tooling-resolution.json',release/'root-lint32-tooling-resolution-recovery1/exact-lint32-tooling-resolution.stdout',release/'root-lint32-tooling-resolution-recovery1/exact-lint32-tooling-resolution.stderr',release/'root-lint32-tooling-resolution-recovery1/readback.json',release/'root-lint32-tooling-resolution-recovery1/exact-lint32-tooling-resolution.daemon-readback.json',release/'root-lint-recovery1-independent-absence1/readback.json']
(new/'reference-fences-before.json').write_text(json.dumps({'sources':[{'path':str(p),'sha256':sha(p.read_bytes()),'bytes':len(p.read_bytes())} for p in references]},indent=2)+'\n')
# Keep this preparation program inside its own new private boundary.
new_script=new/'prepare-private-derivative2.py';new_script.write_bytes(Path(__file__).read_bytes());Path(__file__).unlink()
print(json.dumps({'directory':str(new),'build_sha256':sha(s.encode()),'runner_sha256':sha(runner.encode()),'fences_sha256':sha((new/'source-fences.json').read_bytes()),'patch_sha256':sha(patch.encode()),'metadata_only_180_seconds':True}))
