package app.cool.mobile.gateway

import android.security.keystore.KeyGenParameterSpec
import java.io.InputStream
import java.io.OutputStream
import java.security.*
import java.security.cert.Certificate
import java.security.spec.AlgorithmParameterSpec
import java.util.Collections
import java.util.Date
import javax.crypto.KeyGeneratorSpi
import javax.crypto.SecretKey

/** Synthetic JCA provider for actual product AndroidKeyStore callers. It does
 * not exercise hardware, StrongBox, Android OS policy or non-exportable keys. */
object GatewaySyntheticKeyStore {
    private val values = mutableMapOf<String, Pair<Key, Certificate?>>()
    var signingGenerations = 0
    var storageGenerations = 0
    var failBeforeGeneration: String? = null
    var failAfterGeneration: String? = null
    var beforeGeneration: (String) -> Unit = {}
    fun install() {
        check(Security.getProvider("AndroidKeyStore") == null)
        Security.addProvider(SyntheticProvider())
    }
    fun reset() = synchronized(values) {
        values.clear(); signingGenerations = 0; storageGenerations = 0; failBeforeGeneration = null; failAfterGeneration = null; beforeGeneration = {}
    }
    fun remove() { Security.removeProvider("AndroidKeyStore"); reset() }
    fun lose(alias: String) = synchronized(values) { values.remove(alias); Unit }
    fun aliasNames(): Set<String> = synchronized(values) { values.keys.toSet() }
    fun legacySigning() { putSigning(realPair()) }
    fun legacyStorage() { putStorage(realSecret()) }
    private fun realPair() = KeyPairGenerator.getInstance("EC", "SunEC").run {
        initialize(java.security.spec.ECGenParameterSpec("secp256r1")); generateKeyPair()
    }
    private fun realSecret() = javax.crypto.KeyGenerator.getInstance("AES", "SunJCE").run { init(256); generateKey() }
    private fun putSigning(pair: KeyPair) = synchronized(values) {
        values[GatewayKeyCreationCustody.SIGNING_ALIAS] = pair.private to object : Certificate("Synthetic") {
            override fun getPublicKey() = pair.public
            override fun getEncoded() = pair.public.encoded
            override fun verify(key: PublicKey) = Unit
            override fun verify(key: PublicKey, provider: String) = Unit
            override fun toString() = "Synthetic public-key certificate"
        }
    }
    private fun putStorage(key: SecretKey) = synchronized(values) { values[GatewayKeyCreationCustody.STORAGE_ALIAS] = key to null }
    private fun before(alias: String) {
        beforeGeneration(alias)
        if (failBeforeGeneration == alias) { failBeforeGeneration = null; throw ProviderException("Synthetic generator failed before creation") }
    }
    private fun after(alias: String) {
        if (failAfterGeneration == alias) { failAfterGeneration = null; throw ProviderException("Synthetic generator failed after creation") }
    }
    class SyntheticProvider : Provider("AndroidKeyStore", "1.0", "Synthetic offline JCA test provider") {
        init {
            put("KeyStore.AndroidKeyStore", SyntheticStore::class.java.name)
            put("KeyPairGenerator.EC", SyntheticPairGenerator::class.java.name)
            put("KeyGenerator.AES", SyntheticSecretGenerator::class.java.name)
        }
    }
    class SyntheticPairGenerator : KeyPairGeneratorSpi() {
        private var alias: String? = null
        override fun initialize(keysize: Int, random: SecureRandom) = throw InvalidAlgorithmParameterException("Expected Android spec")
        override fun initialize(params: AlgorithmParameterSpec, random: SecureRandom) { alias = (params as KeyGenParameterSpec).keystoreAlias }
        override fun generateKeyPair(): KeyPair {
            val name = alias ?: error("Missing alias"); check(name == GatewayKeyCreationCustody.SIGNING_ALIAS)
            signingGenerations++; before(name); val pair = realPair(); putSigning(pair); after(name); return pair
        }
    }
    class SyntheticSecretGenerator : KeyGeneratorSpi() {
        private var alias: String? = null
        override fun engineInit(random: SecureRandom) = throw InvalidAlgorithmParameterException("Expected Android spec")
        override fun engineInit(size: Int, random: SecureRandom) = throw InvalidAlgorithmParameterException("Expected Android spec")
        override fun engineInit(params: AlgorithmParameterSpec, random: SecureRandom) { alias = (params as KeyGenParameterSpec).keystoreAlias }
        override fun engineGenerateKey(): SecretKey {
            val name = alias ?: error("Missing alias"); check(name == GatewayKeyCreationCustody.STORAGE_ALIAS)
            storageGenerations++; before(name); val key = realSecret(); putStorage(key); after(name); return key
        }
    }
    class SyntheticStore : KeyStoreSpi() {
        override fun engineLoad(input: InputStream?, password: CharArray?) = Unit
        override fun engineStore(output: OutputStream?, password: CharArray?) = Unit
        override fun engineGetKey(alias: String, password: CharArray?): Key? = synchronized(values) { values[alias]?.first }
        override fun engineGetCertificate(alias: String): Certificate? = synchronized(values) { values[alias]?.second }
        override fun engineGetCertificateChain(alias: String): Array<Certificate>? = engineGetCertificate(alias)?.let { arrayOf(it) }
        override fun engineGetCreationDate(alias: String): Date? = if (engineContainsAlias(alias)) Date(0) else null
        override fun engineContainsAlias(alias: String) = synchronized(values) { values.containsKey(alias) }
        override fun engineAliases() = Collections.enumeration(aliasNames())
        override fun engineSize() = synchronized(values) { values.size }
        override fun engineIsKeyEntry(alias: String) = engineContainsAlias(alias)
        override fun engineIsCertificateEntry(alias: String) = false
        override fun engineGetCertificateAlias(cert: Certificate): String? = synchronized(values) { values.entries.firstOrNull { it.value.second == cert }?.key }
        override fun engineDeleteEntry(alias: String) { throw KeyStoreException("Product must not delete retained aliases") }
        override fun engineSetKeyEntry(alias: String, key: Key, password: CharArray?, chain: Array<out Certificate>?) { throw KeyStoreException("Product must not replace keys") }
        override fun engineSetKeyEntry(alias: String, key: ByteArray, chain: Array<out Certificate>?) { throw KeyStoreException("Product must not import keys") }
        override fun engineSetCertificateEntry(alias: String, cert: Certificate) { throw KeyStoreException("Product must not replace certificates") }
    }
}
