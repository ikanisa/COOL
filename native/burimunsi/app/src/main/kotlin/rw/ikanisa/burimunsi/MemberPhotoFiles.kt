package rw.ikanisa.burimunsi

import java.io.File
import java.io.InputStream
import java.io.ByteArrayOutputStream
import java.nio.file.Files
import java.util.UUID

internal class MemberDocumentTooLarge:IllegalArgumentException("member_document_too_large")

/** Only this flow's private cache files may be restored or removed. */
internal class MemberPhotoFiles(cache:File){
    private val folder=File(cache,"member-photos")
    private val namePattern=Regex("capture-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\\.jpg")
    init{check(folder.mkdirs()||folder.isDirectory);check(!Files.isSymbolicLink(folder.toPath()))}
    fun create():File=File(folder,"capture-${UUID.randomUUID()}.jpg").also{check(it.createNewFile())}
    fun restore(name:String?):File?{
        if(name==null||!namePattern.matches(name))return null
        val file=File(folder,name)
        if(Files.isSymbolicLink(file.toPath())||file.canonicalFile.parentFile!=folder.canonicalFile)return null
        return file.takeIf{it.isFile}
    }
    fun remove(name:String?):Boolean=restore(name)?.let{it.delete()||!it.exists()}?:true
    fun removeExcept(keep:Set<String>){folder.listFiles()?.forEach{if(namePattern.matches(it.name)&&it.name !in keep)remove(it.name)}}
}

/** A provider cannot make the app buffer an unbounded photo or document. */
internal fun readMemberDocument(input:InputStream,maxBytes:Int,checkCurrent:()->Unit):ByteArray{
    require(maxBytes>0)
    val output=object:ByteArrayOutputStream(){fun wipe(){buf.fill(0)}}
    val chunk=ByteArray(8192)
    try{
        while(true){
            checkCurrent()
            val count=input.read(chunk)
            checkCurrent()
            if(count<0)break
            require(count>0)
            if(count>maxBytes-output.size())throw MemberDocumentTooLarge()
            output.write(chunk,0,count)
        }
        return output.toByteArray().also{require(it.isNotEmpty())}
    }finally{chunk.fill(0);output.wipe();output.close()}
}
