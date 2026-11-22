package rw.ikanisa.burimunsi.data

import rw.ikanisa.burimunsi.core.Values
import rw.ikanisa.wire.ResponseTransport
import rw.ikanisa.wire.StrictJson
import rw.ikanisa.wire.WireMediaType
import rw.ikanisa.wire.objectValue
import java.net.HttpURLConnection
import java.net.URL

/** Reads only Collect's public runtime configuration. This is intentionally
 * independent of operator login so the existing sign-in Help works too.
 * No session, device credential or user-selected URL is sent. */
class SupportContactClient(origin:String,prefix:String,publicKey:String="",
    private val connect:(URL)->HttpURLConnection={it.openConnection() as HttpURLConnection}) {
    private val base=Values.apiOrigin(origin)
    private val publicKey=validatedSupabasePublicKey(base,prefix,publicKey).also {
        if(base.host.equals("rrlduytparvsjfmegalh.supabase.co",ignoreCase=true))require(it.isNotEmpty())
    }
    private val path=prefix.also{require(it.isEmpty()||it=="/functions/v1/collect-api")}+
        "/v1/rpc/get_public_runtime_config"

    /** An absent, ambiguous, invalid or temporarily unreachable contact is unavailable. */
    fun read():String? {
        var connection:HttpURLConnection?=null
        return try {
            val target=base.resolve(path)
            require(target.scheme==base.scheme&&target.host==base.host&&target.port==base.port&&target.rawPath==path)
            connection=connect(target.toURL())
            connection.requestMethod="POST";connection.instanceFollowRedirects=false
            connection.connectTimeout=15_000;connection.readTimeout=20_000;connection.useCaches=false
            connection.setRequestProperty("Accept","application/json")
            connection.setRequestProperty("Accept-Encoding","identity")
            if(publicKey.isNotEmpty())connection.setRequestProperty("apikey",publicKey)
            connection.setRequestProperty("Content-Type","application/json; charset=utf-8")
            val body="{}".toByteArray(Charsets.UTF_8)
            connection.doOutput=true;connection.setFixedLengthStreamingMode(body.size)
            connection.outputStream.use{it.write(body)}
            if(connection.responseCode!=200)return null
            val meta=ResponseTransport.metadata(connection.headerFields,65_536)
            if(!WireMediaType.isUtf8(meta.contentType))return null
            val active=connection
            val bytes=ResponseTransport.read(connection.inputStream,65_536,meta.contentLength,beforeRead={active.readTimeout=it})
            val value=try{objectValue(StrictJson.parse(bytes,65_536))}finally{bytes.fill(0)}
            phone(value)
        }catch(_:Exception){null}finally{connection?.disconnect()}
    }

    private fun phone(config:Map<String,Any?>):String? {
        val channels=config["support_channels"] as? List<*> ?:return null
        if(channels.size>100)return null
        var chosen:String?=null
        for(entry in channels){
            val channel=entry as? Map<*,*> ?:return null
            if(channel["key"]!="support.whatsapp")continue
            val active=channel["is_active"]
            if(active==false)continue
            if(active!=null&&active!=true)return null
            if(channel["channel_type"]!=null&&channel["channel_type"]!="whatsapp")return null
            val raw=channel["value"] as? String ?:return null
            val normalized=normalize(raw)?:return null
            if(chosen!=null)return null // Do not choose between competing channels.
            chosen=normalized
        }
        return chosen
    }

    private fun normalize(raw:String):String? {
        if(raw.length !in 8..40||raw!=raw.trim())return null
        // Collect historically stores Rwanda numbers with or without formatting;
        // an explicitly international number is also valid for WhatsApp.
        val rw=runCatching{Values.phone(raw)}.getOrNull()
        if(rw!=null)return rw
        if(!Regex("\\+?[1-9][0-9]{7,14}").matches(raw))return null
        return "+"+raw.removePrefix("+")
    }
}
