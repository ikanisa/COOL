package android.util
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.nio.file.Files
import java.nio.file.StandardCopyOption
object AtomicFileFaults { var failFinishOnce = false; var failFileOnce: String? = null; var writeCount = 0 }
class AtomicFile(val baseFile: File) {
 private val stage get() = File(baseFile.path + ".new")
 fun openRead(): FileInputStream {
  val backup = File(baseFile.path + ".bak")
  if (backup.exists()) Files.move(backup.toPath(), baseFile.toPath(), StandardCopyOption.REPLACE_EXISTING)
  return FileInputStream(baseFile)
 }
 fun startWrite(): FileOutputStream = FileOutputStream(stage)
 fun finishWrite(stream: FileOutputStream) {
  AtomicFileFaults.writeCount++; if (AtomicFileFaults.failFinishOnce || AtomicFileFaults.failFileOnce == baseFile.name) { AtomicFileFaults.failFileOnce = null; AtomicFileFaults.failFinishOnce = false; throw java.io.IOException("Synthetic atomic finish failure") }
  stream.fd.sync(); stream.close()
  Files.move(stage.toPath(), baseFile.toPath(), StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
 }
 fun failWrite(stream: FileOutputStream) { try { stream.close() } finally { stage.delete() } }
}
object Base64 {
 const val NO_WRAP = 2
 fun decode(value: String, flags: Int): ByteArray = java.util.Base64.getDecoder().decode(value)
 fun encodeToString(value: ByteArray, flags: Int): String = java.util.Base64.getEncoder().encodeToString(value)
}
