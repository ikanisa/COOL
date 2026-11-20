package android.os
object SystemClock {
 @Volatile var fixed:Long?=null
 var afterRead:(()->Unit)?=null
 fun elapsedRealtime():Long {
  val value=fixed?:System.nanoTime()/1_000_000
  afterRead?.invoke()
  return value
 }
}
