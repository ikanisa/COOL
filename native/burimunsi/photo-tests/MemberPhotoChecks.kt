package rw.ikanisa.burimunsi

import java.io.ByteArrayInputStream
import java.io.File
import java.nio.file.Files

/** Actual cache/stream rules on synthetic private files; no Android or camera claim. */
fun main(){
    var count=0
    fun verify(label:String,run:()->Unit){run();count++;println("PASS $label")}
    fun refuses(run:()->Unit){var refused=false;try{run()}catch(_:IllegalArgumentException){refused=true};check(refused)}
    val cache=Files.createTempDirectory("member-photo-checks").toFile()
    try{
        val files=MemberPhotoFiles(cache);val capture=files.create();capture.writeBytes(byteArrayOf(1,2,3))
        verify("rotation restores only an existing owned capture name"){check(MemberPhotoFiles(cache).restore(capture.name)==capture)}
        verify("traversal and arbitrary filenames are never restored"){for(name in listOf("../outside.jpg","/tmp/outside.jpg","other.jpg","capture-fake.jpg"))check(files.restore(name)==null)}
        val outside=File(cache,"outside.jpg").apply{writeText("preserved")}
        val link=File(cache,"member-photos/capture-00000000-0000-0000-0000-000000000000.jpg")
        Files.createSymbolicLink(link.toPath(),outside.toPath())
        verify("a symlink cannot share or erase an unrelated file"){check(files.restore(link.name)==null);files.remove(link.name);check(outside.readText()=="preserved")}
        val orphan=files.create();val unrelated=File(cache,"member-photos/unrelated.txt").apply{writeText("preserved")}
        verify("orphan cleanup preserves the pending capture and unrelated files"){files.removeExcept(setOf(capture.name));check(!orphan.exists()&&capture.exists()&&unrelated.exists())}
        verify("cancel cleanup removes only the owned capture"){check(files.remove(capture.name));check(!capture.exists()&&outside.exists())}
        verify("bounded reader preserves exact bytes at its limit"){check(readMemberDocument(ByteArrayInputStream(byteArrayOf(1,2,3)),3).contentEquals(byteArrayOf(1,2,3)))}
        verify("oversized provider input is refused before it can grow the buffer"){var tooLarge=false;try{readMemberDocument(ByteArrayInputStream(ByteArray(9)),8)}catch(_:MemberDocumentTooLarge){tooLarge=true};check(tooLarge)}
        verify("empty input does not become an OCR document"){refuses{readMemberDocument(ByteArrayInputStream(byteArrayOf()),8)}}
        verify("invalid input bounds are refused"){refuses{readMemberDocument(ByteArrayInputStream(byteArrayOf(1)),0)}}
    }finally{cache.deleteRecursively()}
    println("RESULT: $count member photo file and bounded-input checks passed; no Android execution claim.")
}
