package android.system
import java.io.FileDescriptor
import java.nio.channels.FileChannel
import java.nio.file.Path
import java.nio.file.StandardOpenOption
object OsConstants { const val O_RDONLY = 0; const val O_DIRECTORY = 65536 }
object Os {
 private val files = java.util.IdentityHashMap<FileDescriptor, FileChannel>()
 fun open(path: String, flags: Int, mode: Int): FileDescriptor = synchronized(files) {
  val fd = FileDescriptor(); files[fd] = FileChannel.open(Path.of(path), StandardOpenOption.READ); fd
 }
 fun fsync(fd: FileDescriptor) { synchronized(files) { files.getValue(fd).force(true) } }
 fun close(fd: FileDescriptor) { synchronized(files) { files.remove(fd)?.close() } }
}
