import groovy.json.JsonOutput
import java.security.MessageDigest
import org.gradle.api.artifacts.component.ModuleComponentIdentifier
import org.gradle.api.artifacts.component.ModuleComponentSelector
import org.gradle.api.artifacts.result.ResolvedDependencyResult
import org.gradle.api.artifacts.result.UnresolvedDependencyResult
import org.gradle.api.artifacts.result.ResolvedArtifactResult
import org.gradle.maven.MavenModule
import org.gradle.maven.MavenPomArtifact
import org.gradle.api.attributes.Usage
import org.gradle.api.attributes.java.TargetJvmEnvironment
import org.gradle.api.*
import org.gradle.internal.exceptions.DefaultMultiCauseException
def failureDetails = { Throwable failure ->
    def text = new StringWriter()
    def writer = new PrintWriter(text)
    failure.printStackTrace(writer)
    writer.flush()
    [type: failure.class.name, message: failure.message, full_stack_trace: text.toString()]
}

def leaf = new IllegalArgumentException('DEEP_VARIANT_AMBIGUITY')
def wrapped = new RuntimeException('TOP_MODULE_RESOLUTION', leaf)
wrapped.addSuppressed(new IOException('SUPPRESSED_TRANSPORT_DETAIL'))
def detail = failureDetails(wrapped)
assert detail.type == 'java.lang.RuntimeException'
assert detail.message == 'TOP_MODULE_RESOLUTION'
assert detail.full_stack_trace.contains('DEEP_VARIANT_AMBIGUITY')
assert detail.full_stack_trace.contains('SUPPRESSED_TRANSPORT_DETAIL')
assert detail.full_stack_trace.contains('Caused by:')
assert new groovy.json.JsonSlurper().parseText(JsonOutput.toJson(detail)).full_stack_trace == detail.full_stack_trace
println('PASS single nested cause + suppressed detail + JSON roundtrip')
def multi = new DefaultMultiCauseException('MULTI_RESOLUTION', [new IllegalStateException('BRANCH_ANDROID'), new IllegalArgumentException('BRANCH_STANDARD_JVM')])
def branches = failureDetails(multi)
assert branches.full_stack_trace.contains('BRANCH_ANDROID')
assert branches.full_stack_trace.contains('BRANCH_STANDARD_JVM')
println('PASS actual Gradle 9.1.0 multi-cause full trace')
def source = new File(args[0]).getText('UTF-8')
new GroovyClassLoader(this.class.classLoader).parseClass('import org.gradle.api.*\n'+source, 'RecoveryBuild.gradle')
println('PASS proposed complete Gradle build script compilation only; no script execution or Gradle invocation')
assert Usage.JAVA_RUNTIME == 'java-runtime'
assert TargetJvmEnvironment.STANDARD_JVM == 'standard-jvm'
println('PASS actual installed Gradle 9.1.0 attribute constants')

// Execute only the extracted pure helper closures against private fixtures.
def attrStart = source.indexOf('def attributeRecords =')
def helperEnd = source.indexOf("tasks.register('resolveExactLintTooling')")
def imports = 'import groovy.json.JsonOutput\nimport java.nio.file.Files\nimport java.nio.file.StandardCopyOption\nimport org.gradle.api.*\n'
def helperText = imports + source.substring(attrStart, helperEnd) + '\n[persist:persistCheckpoint,variant:variantRecord]'
def helpers = new GroovyShell(this.class.classLoader).evaluate(helperText, 'PureHelpers.groovy')
def fixtures = new File(args[1]); assert fixtures.isDirectory()
def output = new File(fixtures, 'fixture-metadata.json')
def record = [components:[],edges:[],artifacts:[],poms:[],checkpoints:[],complete_selected_tooling_metadata:false,complete_selected_tooling_graph:false]
helpers.persist(output,record,'before-selected-metadata-resolution')
def first = new File(fixtures, output.name + '.checkpoint-0.json').bytes
record.components << [id:'fixture:module:1']
helpers.persist(output,record,'selected-components-edges-variants')
assert new groovy.json.JsonSlurper().parse(output).counts.components == 1
assert new File(fixtures, output.name + '.checkpoint-0.json').bytes == first
assert new groovy.json.JsonSlurper().parseText(new String(first,'UTF-8')).counts.components == 0
assert !new File(fixtures, output.name + '.pending-0').exists()
assert !new File(fixtures, output.name + '.pending-1').exists()
println('PASS fsynced distinct checkpoint leaves + actual same-filesystem atomic latest replacement')
record.poms << [id:'fixture-POM']
record.complete_selected_tooling_metadata=true
helpers.persist(output,record,'selected-metadata-complete-before-binaries')
def current = new groovy.json.JsonSlurper().parse(output)
assert current.complete_selected_tooling_metadata && !current.complete_selected_tooling_graph
assert current.artifacts.empty && current.poms.size()==1 && current.checkpoints.size()==3
println('PASS metadata completion retains zero binaries and full-graph false')
def unchanged=output.bytes
def collision=[components:[],edges:[],artifacts:[],poms:[],checkpoints:[]]
try {helpers.persist(output,collision,'collision');assert false} catch(GradleException expected) {assert expected.message=='Checkpoint leaf already exists'}
assert output.bytes==unchanged
println('PASS checkpoint leaf collision fails without overwriting prior proof')
def bounded=[components:[],edges:[],artifacts:[],poms:[],checkpoints:(0..<8).collect{[sequence:it]}]
try {helpers.persist(output,bounded,'too-many');assert false} catch(GradleException expected) {assert expected.message=='Checkpoint count bound exceeded'}
assert output.bytes==unchanged
println('PASS finite checkpoint bound refuses extra leaf')
def attr=org.gradle.api.attributes.Attribute.of('org.gradle.usage',String)
def attributes=new Expando(); attributes.keySet={->[attr] as Set}; attributes.getAttribute={key->'java-runtime'}
def nested=[displayName:'external-selected',owner:[displayName:'fixture:owner:2'],attributes:attributes,capabilities:[[group:'fixture',name:'external',version:'2']],externalVariant:Optional.of([displayName:'further-hop'])]
def variant=[displayName:'selected-runtime',owner:[displayName:'fixture:owner:1'],attributes:attributes,capabilities:[[group:'fixture',name:'selected',version:'1']],externalVariant:Optional.of(nested)]
def selected=helpers.variant(variant)
assert selected.owner=='fixture:owner:1' && selected.capabilities[0].name=='selected'
assert selected.attributes[0].value=='java-runtime'
assert selected.external_variant.owner=='fixture:owner:2' && selected.external_variant.further_external_variant_present
assert helpers.variant(variant+[externalVariant:Optional.empty()]).external_variant==null
println('PASS selected variant owner/capabilities/attributes and external bridge retention; no filename projection')
