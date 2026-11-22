package rw.ikanisa.burimunsi.data

import org.json.JSONObject
import rw.ikanisa.burimunsi.core.Operator
import rw.ikanisa.burimunsi.core.SessionAuthority
import rw.ikanisa.burimunsi.core.SessionWitness

/** Internal request boundary. NativeRepository alone owns and changes the session. */
internal interface NativeSessionRequests {
    val authority: SessionAuthority
    val operator: Operator?
    val groupId: String

    fun ownedSession(): SessionWitness

    fun requestOwned(
        witness: SessionWitness,
        method: String,
        path: String,
        body: JSONObject? = null,
        recoveryOrigin: String? = null,
    ): String
}
