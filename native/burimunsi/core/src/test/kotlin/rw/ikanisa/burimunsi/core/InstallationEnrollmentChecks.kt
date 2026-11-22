package rw.ikanisa.burimunsi.core

/** Synthetic local enrollment policy tests. No provider, Android device or grant
 * issuance is simulated as an accepted production authentication outcome. */
object InstallationEnrollmentChecks {
    private const val ID="10000000-0000-4000-8000-000000000001"
    private const val OTHER="10000000-0000-4000-8000-000000000002"
    private fun rejects(block:()->Unit){var caught=false;try{block()}catch(_:ContractFailure){caught=true};check(caught)}
    fun run(ok:(String,()->Unit)->Unit){
        val token="a".repeat(64);val local=InstallationGrant.create(ID,token).localRecord()
        ok("saved grant is bound to its exact existing installation"){
            val grant=InstallationGrant.read(ID,local);check(grant.installationId==ID&&grant.token()==token)
            rejects{InstallationGrant.read(OTHER,local)}
        }
        ok("grant credential never enters its ordinary string representation"){
            val grant=InstallationGrant.create(ID,token)
            check(grant.toString()=="InstallationGrant(redacted)"&&!grant.toString().contains(token))
        }
        ok("managed policy takes precedence without opening local credential storage"){
            val managed="b".repeat(64)
            val result=InstallationEnrollment.resolve(ID,true,ID,true,managed){error("must not read local storage")}
            check(result?.token()==managed)
        }
        ok("partial empty wrong-type or mismatched managed grant cannot downgrade to local"){
            for(fields in listOf(
                listOf(true,ID,false,null),listOf(false,null,true,token),listOf(true,null,true,token),
                listOf(true,"",true,token),listOf(true,OTHER,true,token),listOf(true,ID,true,null),
                listOf(true,ID,true,""),listOf(true,ID,true,"A".repeat(64)))){
                var localReads=0
                rejects{InstallationEnrollment.resolve(ID,fields[0] as Boolean,fields[1] as String?,fields[2] as Boolean,fields[3] as String?){localReads++;local}}
                check(localReads==0)
            }
        }
        ok("missing managed fields permit only the same-installation saved record"){
            check(InstallationEnrollment.resolve(ID,false,null,false,null){local}?.token()==token)
            check(InstallationEnrollment.resolve(ID,false,null,false,null){null}==null)
            rejects{InstallationEnrollment.resolve(OTHER,false,null,false,null){local}}
        }
        ok("malformed or oversized local records fail closed"){
            for(record in listOf(token,"burimunsi-local-grant-v2|$ID|$token",local+"|extra",local+"\n","x".repeat(161)))
                rejects{InstallationGrant.read(ID,record)}
        }
        ok("setup tokens cannot be truncated normalized or interpreted as another credential"){
            for(bad in listOf("",token.dropLast(1),token+"a"," "+token,token+"\n","A".repeat(64),"g".repeat(64),"sk-"+token))
                rejects{InstallationGrant.create(ID,bad)}
        }
        ok("invalid installation identity never reads a grant or offers local reset"){
            val status=InstallationEnrollment.inspect("not-an-installation",false,null,false,null){error("must not read")}
            check(status.source==InstallationEnrollmentSource.UNAVAILABLE&&!status.available&&!status.canSave&&!status.canClearLocal)
        }
        ok("corrupt local custody can be explicitly cleared but is not usable or silently overwritten"){
            val status=InstallationEnrollment.inspect(ID,false,null,false,null){throw IllegalStateException("synthetic protected-store failure")}
            check(status.source==InstallationEnrollmentSource.LOCAL_BLOCKED&&!status.available&&!status.canSave&&status.canClearLocal)
        }
        ok("malformed managed policy offers no local save or clear path"){
            val status=InstallationEnrollment.inspect(ID,true,OTHER,true,token){local}
            check(status.source==InstallationEnrollmentSource.MANAGED_BLOCKED&&!status.available&&!status.canSave&&!status.canClearLocal)
        }
        ok("local setup metadata never contains the saved credential"){
            val status=InstallationEnrollment.inspect(ID,false,null,false,null){local}
            check(status.source==InstallationEnrollmentSource.LOCAL&&status.available&&!status.canSave&&status.canClearLocal)
            check(!status.toString().contains(token))
        }
        ok("only absent local custody offers initial save"){
            val status=InstallationEnrollment.inspect(ID,false,null,false,null){null}
            check(status.source==InstallationEnrollmentSource.MISSING&&!status.available&&status.canSave&&!status.canClearLocal)
        }
        ok("signed-in and in-flight authentication cannot edit enrollment"){
            rejects{InstallationEnrollment.requireEditable(true,false,CollectEmailCodeState())}
            rejects{InstallationEnrollment.requireEditable(false,true,CollectEmailCodeState())}
        }
        ok("active or uncertain email code cannot change the grant used by that challenge"){
            val challenge=CollectEmailChallenge("operator@example.invalid",ID,10000,5000)
            rejects{InstallationEnrollment.requireEditable(false,false,CollectEmailCodeState(challenge))}
            rejects{InstallationEnrollment.requireEditable(false,false,CollectEmailCodeState(verificationUnknown=true))}
        }
        ok("cancelled code permits setup editing without resetting its email cooldown"){
            val cancelled=CollectEmailCodeState(nextRequestAt=5000)
            InstallationEnrollment.requireEditable(false,false,cancelled)
            check(cancelled.nextRequestAt==5000L)
        }
    }
}
