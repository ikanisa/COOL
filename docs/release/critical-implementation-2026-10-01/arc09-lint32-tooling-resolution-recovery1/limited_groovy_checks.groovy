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
