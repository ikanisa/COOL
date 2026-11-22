package app.cool.mobile.security

import org.junit.Assert.*
import org.junit.Test
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.StandardCopyOption
import java.util.concurrent.Callable
import java.util.concurrent.Executors
import javax.crypto.Cipher
import javax.crypto.spec.SecretKeySpec

class ReceiptSmsPendingJournalTest {
    private val owner="d1000000-0000-4000-8000-000000000001"
    private val other="d1000000-0000-4000-8000-000000000002"
    private val session="d2000000-0000-4000-8000-000000000001"
    private val next="d2000000-0000-4000-8000-000000000002"
    private val third="d2000000-0000-4000-8000-000000000003"
    private fun group(n:Int)="d3000000-0000-4000-8000-"+n.toString().padStart(12,'0')
    private fun request(n:Int)="d5000000-0000-4000-8000-"+n.toString().padStart(12,'0')
    private fun row(n:Int=1,choice:Boolean=true,auth:String=session,user:String=owner,head:Long=0L)=
        ReceiptSmsPendingRecord(user,auth,group(n),request(n),0,head,choice)
    private class Disk(val root:Path):ReceiptSmsPendingCustody {
        val key=SecretKeySpec(ByteArray(32){(it+1).toByte()},"AES")
        val cipher=ReceiptSmsPendingCipher{key}
        fun path(owner:String)=root.resolve(owner+".enc")
        override fun read(owner:String)=if(Files.exists(path(owner)))cipher.decrypt(owner,Files.readAllBytes(path(owner))) else null
        override fun write(owner:String,bytes:ByteArray) {
            val temporary=root.resolve(owner+".new");Files.write(temporary,cipher.encrypt(owner,bytes))
            java.nio.channels.FileChannel.open(temporary,java.nio.file.StandardOpenOption.WRITE).use{it.force(true)}
            Files.move(temporary,path(owner),StandardCopyOption.REPLACE_EXISTING,StandardCopyOption.ATOMIC_MOVE)
            check(read(owner)!!.contentEquals(bytes))
        }
    }
    private fun fixture(body:(Disk)->Unit) {
        val path=Files.createTempDirectory("receipt-sms-v2-test-")
        try{body(Disk(path))}finally{Files.walk(path).use{p->p.sorted(Comparator.reverseOrder()).forEach(Files::delete)}}
    }
    @Test fun reconstructionRetainsBothRevisionsAndNeverReplacesAnotherAccount()=fixture{disk->
        val old=row(head=9007199254740990L);ReceiptSmsPendingJournal(disk).claim(old);ReceiptSmsPendingJournal(disk).claim(row(user=other))
        val bytes=Files.readAllBytes(disk.path(owner));val rebuilt=ReceiptSmsPendingJournal(Disk(disk.root))
        assertEquals(old,rebuilt.read(owner,group(1)).pending.single())
        assertEquals(old,rebuilt.claim(old.copy(requestId=request(9),optIn=false)).pending.single())
        assertArrayEquals(bytes,Files.readAllBytes(disk.path(owner)));assertEquals(other,rebuilt.read(other,group(1)).pending.single().userId)
    }
    @Test fun parallelOrdinaryClaimsHaveOneDurableWinner()=fixture{disk->
        val pool=Executors.newFixedThreadPool(8)
        try{val results=pool.invokeAll((1..24).map{n->Callable{ReceiptSmsPendingJournal(Disk(disk.root)).claim(row().copy(requestId=request(n),optIn=n%2==0)).pending.single()}}).map{it.get()}
            assertEquals(1,results.distinct().size);assertEquals(results.first(),ReceiptSmsPendingJournal(disk).read(owner,group(1)).pending.single())
        }finally{pool.shutdownNow()}
    }
    @Test fun explicitFreshWithdrawalRetainsEveryOriginalBeforeDispatchAndReservesHistory()=fixture{disk->
        val journal=ReceiptSmsPendingJournal(disk);val original=row();journal.claim(original)
        val fence=original.copy(sessionId=next,requestId=request(2),optIn=false)
        val both=journal.claim(fence,true);assertEquals(listOf(original,fence).toSet(),both.pending.toSet())
        val rebuilt=ReceiptSmsPendingJournal(Disk(disk.root));assertEquals(both.pending.toSet(),rebuilt.read(owner,group(1)).pending.toSet())
        val completed=rebuilt.complete(fence,1L);assertTrue(completed.pending.isEmpty())
        assertEquals(ReceiptSmsSuperseded(original,1L),completed.superseded.single())
        val replay=rebuilt.complete(fence,1L);assertEquals(completed,replay)
    }
    @Test fun sameSessionCannotClaimAnotherFenceAndOptInCannotBeARecoveryFence()=fixture{disk->
        val journal=ReceiptSmsPendingJournal(disk);val original=row();journal.claim(original)
        val bytes=Files.readAllBytes(disk.path(owner))
        assertEquals(original,journal.claim(original.copy(requestId=request(2),optIn=false),true).pending.single())
        assertThrows(Exception::class.java){journal.claim(original.copy(sessionId=next,requestId=request(3)),true)}
        assertArrayEquals(bytes,Files.readAllBytes(disk.path(owner)))
    }
    @Test fun repeatedReloginFencePreservesAllUnknownIdentitiesAndAnAckArchivesThem()=fixture{disk->
        val journal=ReceiptSmsPendingJournal(disk);val original=row();val fence=original.copy(sessionId=next,requestId=request(2),optIn=false)
        journal.claim(original);journal.claim(fence,true)
        val latest=fence.copy(sessionId=third,requestId=request(3));assertEquals(3,journal.claim(latest,true).pending.size)
        val result=journal.complete(latest,1);assertTrue(result.pending.isEmpty());assertEquals(setOf(original,fence),result.superseded.map{it.request}.toSet())
    }
    @Test fun oldAcknowledgementCannotRemoveNewerCounterRequest()=fixture{disk->
        val journal=ReceiptSmsPendingJournal(disk);val original=row();journal.claim(original)
        val newer=original.copy(sessionId=next,requestId=request(2),expectedDecisionRevision=1,optIn=false);journal.claim(newer,true)
        val result=journal.complete(original,1);assertEquals(newer,result.pending.single());assertTrue(result.superseded.isEmpty())
    }
    @Test fun higherHeadDispositionPreservesUnknownOutcomeButEqualHeadNeverQualifies()=fixture{disk->
        val journal=ReceiptSmsPendingJournal(disk);val original=row();journal.claim(original);val bytes=Files.readAllBytes(disk.path(owner))
        assertThrows(Exception::class.java){journal.supersede(owner,group(1),listOf(original),0)}
        assertArrayEquals(bytes,Files.readAllBytes(disk.path(owner)))
        assertThrows(Exception::class.java){journal.supersede(owner,group(1),listOf(original.copy(requestId=request(9))),1)}
        val result=journal.supersede(owner,group(1),listOf(original),1);assertTrue(result.pending.isEmpty());assertEquals(original,result.superseded.single().request)
    }
    @Test fun anotherInstanceAcknowledgementAllowsExactReplayOrExplicitUnknownArchival()=fixture{disk->
        val first=ReceiptSmsPendingJournal(disk);val otherInstance=ReceiptSmsPendingJournal(Disk(disk.root));val original=row()
        first.claim(original);otherInstance.complete(original,1L);assertTrue(first.read(owner,group(1)).pending.isEmpty())
        val replayed=first.claim(original);assertEquals(original,replayed.pending.single())
        assertTrue(otherInstance.complete(original,1L).pending.isEmpty())
        assertThrows(Exception::class.java){first.supersede(owner,group(1),listOf(original),0L)}
        val archived=first.supersede(owner,group(1),listOf(original),1L)
        assertEquals(ReceiptSmsSuperseded(original,1L),archived.superseded.single())
        assertEquals(archived,otherInstance.supersede(owner,group(1),listOf(original),1L))
    }
    @Test fun staleArchivalCannotOverwriteUnobservedOrChangedNewerRequest()=fixture{disk->
        val journal=ReceiptSmsPendingJournal(disk);val original=row();journal.claim(original);journal.complete(original,1)
        val newer=original.copy(requestId=request(2),expectedDecisionRevision=1,optIn=false);journal.claim(newer)
        val before=Files.readAllBytes(disk.path(owner))
        assertThrows(Exception::class.java){journal.supersede(owner,group(1),listOf(original),1)}
        assertThrows(Exception::class.java){journal.supersede(owner,group(1),listOf(original,newer.copy(optIn=true)),1)}
        assertArrayEquals(before,Files.readAllBytes(disk.path(owner)))
        val archived=journal.supersede(owner,group(1),listOf(original,newer),1)
        assertEquals(newer,archived.pending.single());assertEquals(original,archived.superseded.single().request)
        val replayAck=journal.complete(original,1);assertEquals(newer,replayAck.pending.single());assertTrue(replayAck.superseded.isEmpty())
    }
    @Test fun missingKnownRequestNeedsHigherHeadAndArchiveCapacityWithoutSilentDiscard()=fixture{disk->
        val journal=ReceiptSmsPendingJournal(disk);val missing=row(head=1)
        assertThrows(Exception::class.java){journal.supersede(owner,group(1),listOf(missing),1)}
        val history=(100..131).map{ReceiptSmsSuperseded(row(it,choice=false),1)}
        disk.write(owner,ReceiptSmsPendingCodec.encode(owner,ReceiptSmsRecoveryState(superseded=history)))
        val before=Files.readAllBytes(disk.path(owner))
        assertThrows(Exception::class.java){journal.supersede(owner,group(1),listOf(missing),2)}
        assertArrayEquals(before,Files.readAllBytes(disk.path(owner)))
    }
    @Test fun recoveryCapacityIsCheckedBeforeClaimAndAnotherGroupCannotConsumeReservedHistory()=fixture{disk->
        val original=row();val history=(100..129).map{ReceiptSmsSuperseded(row(it,choice=false),1)}
        disk.write(owner,ReceiptSmsPendingCodec.encode(owner,ReceiptSmsRecoveryState(listOf(original,row(2,choice=false)),history)))
        val journal=ReceiptSmsPendingJournal(disk);val fence=original.copy(sessionId=next,requestId=request(3),optIn=false);journal.claim(fence,true)
        val bytes=Files.readAllBytes(disk.path(owner))
        assertThrows(Exception::class.java){journal.supersede(owner,group(2),listOf(row(2,choice=false)),1)}
        assertArrayEquals(bytes,Files.readAllBytes(disk.path(owner)));assertEquals(1,journal.complete(fence,1).superseded.size);assertEquals(31,ReceiptSmsPendingCodec.decode(owner,disk.read(owner)!!).superseded.size)
    }
    @Test fun exhaustedHistoryRefusesRecoveryWithoutDiscardingAnything()=fixture{disk->
        val original=row();val history=(100..130).map{ReceiptSmsSuperseded(row(it,choice=false),1)}
        disk.write(owner,ReceiptSmsPendingCodec.encode(owner,ReceiptSmsRecoveryState(listOf(original),history)))
        val before=Files.readAllBytes(disk.path(owner))
        assertThrows(Exception::class.java){ReceiptSmsPendingJournal(disk).claim(original.copy(sessionId=next,requestId=request(2),optIn=false),true)}
        assertArrayEquals(before,Files.readAllBytes(disk.path(owner)))
    }
    @Test fun corruptionFailsReadClaimAndCompleteWithoutReplacingCiphertext()=fixture{disk->
        val journal=ReceiptSmsPendingJournal(disk);journal.claim(row());val bytes=Files.readAllBytes(disk.path(owner));bytes[bytes.lastIndex]=(bytes.last().toInt() xor 1).toByte();Files.write(disk.path(owner),bytes)
        assertThrows(Exception::class.java){journal.read(owner,group(1))};assertThrows(Exception::class.java){journal.claim(row(2))};assertThrows(Exception::class.java){journal.complete(row(),1)}
        assertArrayEquals(bytes,Files.readAllBytes(disk.path(owner)))
    }
    @Test fun unsupportedOldPayloadIsPreservedInsteadOfInventingDecisionRevision()=fixture{disk->
        val cipher=Cipher.getInstance("AES/GCM/NoPadding");cipher.init(Cipher.ENCRYPT_MODE,disk.key);cipher.updateAAD(("collect.receipt-sms-pending.v1\u0000"+owner).toByteArray())
        val legacy=byteArrayOf(0x52,0x53,0x43,0x31,0,0,0,0);val envelope=byteArrayOf(1)+cipher.iv+cipher.doFinal(legacy);Files.write(disk.path(owner),envelope)
        assertThrows(Exception::class.java){ReceiptSmsPendingJournal(disk).claim(row())};assertArrayEquals(envelope,Files.readAllBytes(disk.path(owner)))
    }
    @Test fun cipherAuthenticatesOwnerKeyAndEnvelope() {
        val cipher=ReceiptSmsPendingCipher{SecretKeySpec(ByteArray(32){7},"AES")};val bytes=ReceiptSmsPendingCodec.encode(owner,ReceiptSmsRecoveryState(listOf(row())))
        val first=cipher.encrypt(owner,bytes);val second=cipher.encrypt(owner,bytes);assertFalse(first.contentEquals(second));assertArrayEquals(bytes,cipher.decrypt(owner,first))
        assertThrows(Exception::class.java){cipher.decrypt(other,first)}
        assertThrows(Exception::class.java){ReceiptSmsPendingCipher{SecretKeySpec(ByteArray(32){9},"AES")}.decrypt(owner,first)}
        for(i in listOf(0,1,13,first.lastIndex)){val bad=first.copyOf();bad[i]=(bad[i].toInt() xor 1).toByte();assertThrows(Exception::class.java){cipher.decrypt(owner,bad)}}
    }
    @Test fun unavailableCustodyAndUncertainAcknowledgementNeverBecomeEmptyOrReplacement()=fixture{disk->
        var writes=0;val unavailable=ReceiptSmsPendingJournal(object:ReceiptSmsPendingCustody{
            override fun read(owner:String):ByteArray?=error("Controlled key unavailable")
            override fun write(owner:String,bytes:ByteArray){writes++}
        });assertThrows(Exception::class.java){unavailable.claim(row())};assertEquals(0,writes)
        val uncertain=ReceiptSmsPendingJournal(object:ReceiptSmsPendingCustody{
            override fun read(owner:String)=disk.read(owner)
            override fun write(owner:String,bytes:ByteArray){disk.write(owner,bytes);error("Controlled directory acknowledgement failure")}
        });assertThrows(Exception::class.java){uncertain.claim(row())}
        assertEquals(row(),ReceiptSmsPendingJournal(Disk(disk.root)).read(owner,group(1)).pending.single())
    }
    @Test fun strictDualRevisionMetadataAndCanonicalBinaryBounds() {
        val record=row(head=9007199254740990L);assertEquals(record,ReceiptSmsPendingRecord.fromWire(record.wire()))
        for(bad in listOf(record.wire()+ ("phone" to "private"),record.wire()+("expected_decision_revision" to 0.0),record.wire()+("expected_decision_revision" to 9007199254740991L),record.wire()-"expected_decision_revision",record.wire()+("schema_version" to 1)))
            assertThrows(Exception::class.java){ReceiptSmsPendingRecord.fromWire(bad)}
        val bytes=ReceiptSmsPendingCodec.encode(owner,ReceiptSmsRecoveryState(listOf(record)))
        assertThrows(Exception::class.java){ReceiptSmsPendingCodec.decode(owner,bytes+byteArrayOf(0))}
        assertThrows(Exception::class.java){ReceiptSmsPendingCodec.decode(other,bytes)}
        val bad=bytes.copyOf();bad[165]=2;assertThrows(Exception::class.java){ReceiptSmsPendingCodec.decode(owner,bad)}
    }
}
