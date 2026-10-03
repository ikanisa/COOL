import ast, hashlib, json, unittest
from pathlib import Path
HERE=Path(__file__).resolve().parent
OLD=HERE.parent/'arc09-lint32-tooling-resolution-recovery1'
BUILD=(HERE/'minimal-project/build.gradle').read_text()
RUN=(HERE/'run_resolution.py').read_text()
def sha(raw): return hashlib.sha256(raw).hexdigest()
class PreparationTests(unittest.TestCase):
 def test_unmodified_settings_publisher_and_lifecycle(self):
  for leaf in ['minimal-project/settings.gradle','read_publisher_provenance.py']:
   self.assertEqual((HERE/leaf).read_bytes(),(OLD/leaf).read_bytes())
  for value in ["controller.run_process(output, label, argv, 180", "tracker.finish()", "command or {}", "daemon['observer_error']", "daemon['owned_daemons_absent']"]:
   self.assertIn(value,RUN)
 def test_exact_root_runtime_attributes_and_guard_bounds(self):
  for value in ["exactLintTooling 'com.android.tools.lint:lint-gradle:32.0.1'", 'Usage.JAVA_RUNTIME', 'TargetJvmEnvironment.STANDARD_JVM', 'components.size() > 160', 'record.edges.size() >= 1024', 'artifacts.size() > 192', 'resolutionStrategy.eachDependency', 'Refused nonfixed version constraint']:
   self.assertIn(value,BUILD)
  for value in ['force(', 'exclude(', 'dependencyLocking', 'useVersion(', 'lintOptions', 'checkReleaseBuilds']:
   self.assertNotIn(value,BUILD)
 def test_metadata_precedes_binary_resolution(self):
  ordered=['before-selected-metadata-resolution','result.allComponents','selected-components-edges-variants','createArtifactResolutionQuery()', 'selected-POM-results','selected-metadata-complete-before-binaries','if (metadataOnly) return','resolvedConfiguration.resolvedArtifacts']
  positions=[BUILD.index(x) for x in ordered]
  self.assertEqual(positions,sorted(positions))
  self.assertIn("if (record.errors) throw new GradleException('POM metadata coverage incomplete')",BUILD)
 def test_metadata_does_not_admit_artifacts(self):
  self.assertIn('selected_variant_filenames_inferred: false',BUILD)
  self.assertIn('complete_selected_tooling_graph: false, publisher_admission_complete: false',BUILD)
  self.assertLess(BUILD.index('if (metadataOnly) return'),BUILD.index('record.complete_selected_tooling_graph = true'))
  self.assertIn("required_complete = 'complete_selected_tooling_metadata' if args.metadata_only else 'complete_selected_tooling_graph'",RUN)
  self.assertIn("graph.get('metadata_only_requested') is not args.metadata_only",RUN)
  self.assertTrue(json.loads((HERE/'commands.json').read_text())['sequential_commands'][1]['metadata_checkpoint_is_not_an_eligible_full_graph'])
 def test_selected_variant_public_provenance_and_external_bridge(self):
  for value in ['component.variants.collect', 'variant.owner.displayName', 'variant.capabilities.collect', 'edge.resolvedVariant', 'external.get().owner.displayName', 'further_external_variant_present']:
   self.assertIn(value,BUILD)
  self.assertNotIn('ResolvedVariantResultInternal',BUILD)
 def test_checkpoint_persistence_and_bounds(self):
  for value in ['sequence >= 8','Checkpoint leaf already exists','saved.getFD().sync()', 'StandardCopyOption.ATOMIC_MOVE', 'StandardCopyOption.REPLACE_EXISTING', "'finished'"]:
   self.assertIn(value,BUILD)
  self.assertIn('len(checkpoint_paths) > 8',RUN)
  self.assertIn("driver.plain_read(path)",RUN)
 def test_sources_fenced_and_python_compiles_without_execution(self):
  rows=json.loads((HERE/'source-fences.json').read_text())['inputs']
  self.assertEqual(len(rows),17)
  for row in rows:
   body=Path(row['path']).read_bytes()
   self.assertEqual(sha(body),row['sha256'],row['path'])
   self.assertEqual(len(body),row['bytes'],row['path'])
  for leaf in ['run_resolution.py','read_publisher_provenance.py']:
   ast.parse((HERE/leaf).read_text(),str(HERE/leaf))
  refs=json.loads((HERE/'reference-fences-before.json').read_text())['sources']
  for row in refs:
   self.assertEqual(sha(Path(row['path']).read_bytes()),row['sha256'])
if __name__=='__main__': unittest.main(verbosity=2)
