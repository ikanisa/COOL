from pathlib import Path
import hashlib,json,unittest
HERE=Path(__file__).resolve().parent;OLD=HERE.parent/'arc09-lint32.0.1-cache-preparation1'
class RecoveryPreparationTests(unittest.TestCase):
 def test_original_runner_publisher_and_repository_configuration_are_byte_identical(self):
  for rel in ['run_resolution.py','read_publisher_provenance.py','minimal-project/settings.gradle']:
   with self.subTest(path=rel):self.assertEqual((HERE/rel).read_bytes(),(OLD/rel).read_bytes())
 def test_exact_root_and_all_existing_graph_admission_bounds_are_preserved(self):
  old=(OLD/'minimal-project/build.gradle').read_text();new=(HERE/'minimal-project/build.gradle').read_text()
  for line in old.splitlines():
   if 'fixedVersion' in line or any(token in line for token in ['components.size() > 160','record.edges.size() >= 1024','artifacts.size() > 192','lint-gradle:32.0.1','roots.size() != 1','Selected module/POM count differs','complete_selected_tooling_graph = true']):
    self.assertIn(line,new)
  for forbidden in ['force(','force ','exclude(','constraints {','lockAllConfigurations','write-locks','resolutionStrategy.force','TargetJvmVersion']:
   self.assertNotIn(forbidden,new)
 def test_module_metadata_has_four_observed_variants_and_attributes_choose_one_runtime_jre(self):
  value=json.loads((HERE/'observed-guava-33.3.1-jre.module.json').read_text())
  self.assertEqual(value['component']['version'],'33.3.1-jre');self.assertEqual(len(value['variants']),4)
  def exact_values(attributes):return [v for v in value['variants'] if all(v['attributes'].get(k)==target for k,target in attributes.items())]
  self.assertEqual(len(exact_values({})),4)
  self.assertEqual(len(exact_values({'org.gradle.usage':'java-runtime'})),2)
  self.assertEqual(len(exact_values({'org.gradle.jvm.environment':'standard-jvm'})),2)
  selected=exact_values({'org.gradle.usage':'java-runtime','org.gradle.jvm.environment':'standard-jvm'})
  self.assertEqual([v['name'] for v in selected],['jreRuntimeElements'])
  self.assertEqual(selected[0]['files'][0]['name'],'guava-33.3.1-jre.jar')
 def test_the_only_consumer_requirements_are_runtime_and_standard_jvm(self):
  value=(HERE/'minimal-project/build.gradle').read_text();block=value[value.index('configurations {'):value.index("dependencies { exactLintTooling")]
  self.assertEqual(block.count('attribute('),2)
  self.assertIn('Usage.USAGE_ATTRIBUTE, objects.named(Usage, Usage.JAVA_RUNTIME)',block)
  self.assertIn('TargetJvmEnvironment.TARGET_JVM_ENVIRONMENT_ATTRIBUTE',block)
  self.assertIn('objects.named(TargetJvmEnvironment, TargetJvmEnvironment.STANDARD_JVM)',block)
 def test_the_sequential_180_second_phases_and_cleanup_guards_are_preserved(self):
  old=json.loads((OLD/'commands.json').read_text());new=json.loads((HERE/'commands.json').read_text())
  for key in ['outer_root_observation_allowance_seconds','automatic_retries','no_automatic_AAB_advance','production_release_approval']:
   self.assertEqual(old[key],new[key])
  for before,after in zip(old['sequential_commands'],new['sequential_commands']):
   for key,value in before.items():
    if key!='argv':self.assertEqual(value,after[key])
  self.assertIn('run_process(output, label, argv, 180', (HERE/'run_resolution.py').read_text())
  self.assertIn('tracker.finish()', (HERE/'run_resolution.py').read_text())
 def test_all_external_fences_match_and_only_two_private_paths_are_rebound(self):
  old=json.loads((OLD/'source-fences.json').read_text());new=json.loads((HERE/'source-fences.json').read_text())
  self.assertEqual(len(old['inputs']),17);self.assertEqual(len(new['inputs']),17)
  for before,after in zip(old['inputs'],new['inputs']):
   if '/minimal-project/' not in before['path']:self.assertEqual(before,after)
   else:self.assertEqual(before,after['original_private_source'])
   self.assertEqual(hashlib.sha256(Path(after['path']).read_bytes()).hexdigest(),after['sha256'])
 def test_terse_fields_are_retained_and_full_failure_and_variant_attributes_are_additive(self):
  value=(HERE/'minimal-project/build.gradle').read_text()
  for expression in ['row.unresolved = edge.failure.toString(); record.errors << row.unresolved','record.errors << failure.toString()','row.failure_details = failureDetails(edge.failure)','record.failure_details <<','full_stack_trace: text.toString()','requested_consumer_attributes: attributeRecords','row.selected_variant =']:
   self.assertIn(expression,value)
  self.assertIn('failure.printStackTrace(writer)',value)
  self.assertNotIn('truncate',value)
if __name__=='__main__':unittest.main(verbosity=2)
