package app.cool.mobile.gateway

import org.json.JSONObject
import java.io.File
import java.nio.file.Files
import java.nio.file.LinkOption

/** Read-only durable pause check. Never AtomicFile.openRead: a committed .bak
 * must be inspected without renaming/deleting any raw crash evidence. */
internal object GatewayRecoveryPause {
    fun require(directory:File,crypto:(String)->GatewayCrypto) {
        if(Files.isSymbolicLink(directory.toPath()) || !Files.isDirectory(directory.toPath(),LinkOption.NOFOLLOW_LINKS))throw GatewayStateException("gateway_recovery_pause_required")
        fun value(name:String):JSONObject {
            val base=File(directory,"$name.bin");val backup=File(directory,"$name.bin.bak")
            val file=if(backup.exists())backup else base
            if(Files.isSymbolicLink(file.toPath()) || !file.isFile || file.length() !in 29..(GatewayCrypto.MAX_BYTES+29).toLong())throw GatewayStateException("gateway_recovery_pause_required")
            return JSONObject(String(crypto(name).decrypt(file.readBytes()),Charsets.UTF_8))
        }
        if(File(directory,GatewayRecovery.INACTIVE).exists())throw GatewayStateException("gateway_recovery_inactive")
        val marker=value("journal-marker");requireKeys(marker,setOf("contract_version","established"))
        val journal=value("journal");requireKeys(journal,setOf("contract_version","emergency_paused","attempts"))
        if(strictInteger(marker,"contract_version")!=1L || !strictBoolean(marker,"established") || strictInteger(journal,"contract_version")!=1L ||
            !strictBoolean(journal,"emergency_paused") || journal.getJSONArray("attempts").length()>GatewayJournal.MAX_ATTEMPTS)throw GatewayStateException("gateway_recovery_pause_required")
    }
}
