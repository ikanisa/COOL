package android.security.keystore
import java.security.spec.AlgorithmParameterSpec
class KeyGenParameterSpec : AlgorithmParameterSpec {
 class Builder(alias: String, purposes: Int) {
  fun setBlockModes(vararg modes: String) = this
  fun setEncryptionPaddings(vararg values: String) = this
  fun setKeySize(size: Int) = this
  fun setUserAuthenticationRequired(value: Boolean) = this
  fun setAlgorithmParameterSpec(value: AlgorithmParameterSpec) = this
  fun setDigests(vararg values: String) = this
  fun build() = KeyGenParameterSpec()
 }
}
object KeyProperties {
 const val KEY_ALGORITHM_AES = "AES"
 const val KEY_ALGORITHM_EC = "EC"
 const val PURPOSE_ENCRYPT = 1
 const val PURPOSE_DECRYPT = 2
 const val PURPOSE_SIGN = 4
 const val PURPOSE_VERIFY = 8
 const val DIGEST_SHA256 = "SHA-256"
 const val BLOCK_MODE_GCM = "GCM"
 const val ENCRYPTION_PADDING_NONE = "NoPadding"
}
