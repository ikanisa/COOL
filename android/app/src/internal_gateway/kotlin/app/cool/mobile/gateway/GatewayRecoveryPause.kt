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
        val version=strictInteger(journal,"contract_version");val rows=journal.getJSONArray("attempts")
        if(strictInteger(marker,"contract_version")!=1L || !strictBoolean(marker,"established") || version !in 1L..2L ||
            !strictBoolean(journal,"emergency_paused") || rows.length()>GatewayJournal.MAX_ATTEMPTS)throw GatewayStateException("gateway_recovery_pause_required")
        // Admit only the existing closed hot-journal readers. Historical v1
        // cannot gain a tagged successor/notice record; v2 requires its exact
        // record kind. This is a read-only pause observation, never authority.
        val ids=HashSet<String>()
        try { for(index in 0 until rows.length()) {
            val row=rows.getJSONObject(index)
            if(version==1L && row.has("record_kind"))throw GatewayStateException("gateway_recovery_pause_required")
            val attempt=if(version==2L)journalAttemptFromJsonV2(row) else archiveAttemptFromJson(row)
            if(!ids.add(attempt.attemptId))throw GatewayStateException("gateway_recovery_pause_required")
        } } catch(_:Exception) { throw GatewayStateException("gateway_recovery_pause_required") }
    }
}
