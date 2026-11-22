import org.jetbrains.kotlin.cli.jvm.compiler.KotlinCoreEnvironment
import org.jetbrains.kotlin.cli.jvm.compiler.EnvironmentConfigFiles
import org.jetbrains.kotlin.psi.KtPsiFactory
import java.io.File

/** Uses the installed Kotlin parser. This is syntax validation, NOT Android compilation. */
fun main(args:Array<String>){
    val disposable=Disposer.newDisposable()
    var failures=0;var total=0
    try{
        val configuration=psiConfiguration()
        val environment=KotlinCoreEnvironment.createForProduction(disposable,configuration,EnvironmentConfigFiles.JVM_CONFIG_FILES)
        val factory=KtPsiFactory(environment.project,false)
        for(root in args.map(::File))for(path in (if(root.isDirectory)root.walkTopDown().filter{it.isFile&&it.extension=="kt"}else sequenceOf(root))){
            val source=path.readText();val file=factory.createFile(path.name,source);total++
            for(error in PsiTreeUtil.collectElementsOfType(file,PsiErrorElement::class.java)){
                val line=source.take(error.textOffset).count{it=='\n'}+1
                System.err.println("${path.path}:$line: ${error.errorDescription}");failures++
            }
        }
        check(failures==0){"$failures Kotlin syntax errors in $total files"}
        println("PASS Kotlin PSI syntax: $total files; no Android type checking or Compose execution.")
    }finally{Disposer.dispose(disposable)}
}
