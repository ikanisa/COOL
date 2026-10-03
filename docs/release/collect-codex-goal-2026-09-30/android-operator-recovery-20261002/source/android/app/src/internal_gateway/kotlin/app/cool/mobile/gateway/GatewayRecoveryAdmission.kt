package app.cool.mobile.gateway

import java.util.concurrent.atomic.AtomicBoolean

/** Each queued task carries this immutable identity and its own cancellation.
 * Picker delivery reserves the operation synchronously through terminal. */
internal class GatewayRecoveryAdmission {
    internal class Ticket(val operation:String,val trustedManifest:String?) {
        val cancelled=AtomicBoolean(false)
        internal var phase="preparing"
    }
    private var current:Ticket?=null
    @Synchronized fun admit(operation:String,trustedManifest:String?):Ticket {
        if(current!=null)throw GatewayStateException("gateway_recovery_busy")
        return Ticket(operation,trustedManifest).also { current=it }
    }
    @Synchronized fun owns(ticket:Ticket):Boolean=current===ticket
    @Synchronized fun picker(ticket:Ticket):Boolean {
        if(current!==ticket || ticket.cancelled.get())return false
        ticket.phase="picker";return true
    }
    @Synchronized fun picked(ticket:Ticket):Boolean {
        if(current!==ticket || ticket.phase!="picker" || ticket.cancelled.get())return false
        ticket.phase="transfer";return true
    }
    @Synchronized fun cancel(ticket:Ticket):Boolean {
        if(current!==ticket)return false
        ticket.cancelled.set(true);return ticket.phase=="picker"
    }
    @Synchronized fun requireWork(ticket:Ticket) {
        if(current!==ticket || ticket.cancelled.get())throw GatewayStateException("gateway_recovery_cancelled")
    }
    @Synchronized fun complete(ticket:Ticket):Boolean {
        if(current!==ticket)return false
        ticket.phase="terminal";current=null;return true
    }
}
