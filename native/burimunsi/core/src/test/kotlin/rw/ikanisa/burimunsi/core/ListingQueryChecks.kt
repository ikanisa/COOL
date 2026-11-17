package rw.ikanisa.burimunsi.core

object ListingQueryChecks {
    fun run(){
        var checks=0
        fun ok(value:Boolean){check(value);checks++}
        fun rejects(action:()->Unit){ok(runCatching(action).exceptionOrNull() is ContractFailure)}
        ok(ListingQuery.defaultsFor(ListingTarget.STAFF).sort==ListingSort.NAME_ASC)
        ok(ListingQuery.defaultsFor(ListingTarget.HISTORY).sort==ListingSort.OLDEST)
        ok(ListingQuery.defaultsFor(ListingTarget.MEMBERS).sort==ListingSort.NEWEST)
        val query=ListingQuery(q="Example",sort=ListingSort.AMOUNT_DESC,fromAt="2026-11-14T00:00:00Z",untilAt="2026-11-15T00:00:00Z",minRwf=100,maxRwf=500,direction="incoming",outcome="successful",credit="uncredited")
        val values=query.queryValues(ListingTarget.PAYMENTS)
        ok(values["sort"]=="amount_desc"&&values["minRwf"]=="100"&&values["untilAt"]=="2026-11-15T00:00:00Z")
        ok(values["direction"]=="incoming"&&values["outcome"]=="successful"&&values["credit"]=="uncredited")
        ok(ListingQuery(active="inactive",minRwf=0,sort=ListingSort.BALANCE_DESC).queryValues(ListingTarget.MEMBERS)["active"]=="inactive")
        ok(ListingQuery(minRwf=-500,maxRwf=0,sort=ListingSort.AMOUNT_ASC).validated(ListingTarget.LEDGER).minRwf==-500L)
        ok(ListingQuery(filter="ledger_entry").validated(ListingTarget.HISTORY).filter=="ledger_entry")
        rejects{ListingQuery(minRwf=-1).validated(ListingTarget.PAYMENTS)}
        rejects{ListingQuery(minRwf=500,maxRwf=100).validated(ListingTarget.PAYMENTS)}
        rejects{ListingQuery(maxRwf=Values.MAX_RWF+1).validated(ListingTarget.PAYMENTS)}
        rejects{ListingQuery(credit="verified").validated(ListingTarget.PAYMENTS)}
        rejects{ListingQuery(direction="incoming").validated(ListingTarget.MEMBERS)}
        rejects{ListingQuery(active="active").validated(ListingTarget.PAYMENTS)}
        rejects{ListingQuery(minRwf=1).validated(ListingTarget.SMS)}
        rejects{ListingQuery(sort=ListingSort.NAME_ASC).validated(ListingTarget.SMS)}
        rejects{ListingQuery(fromAt="2026-02-30T00:00:00Z").validated(ListingTarget.PAYMENTS)}
        rejects{ListingQuery(fromAt="2026-11-14T00:00:00").validated(ListingTarget.PAYMENTS)}
        rejects{ListingQuery(fromAt="2026-11-15T00:00:00Z",untilAt="2026-11-14T00:00:00Z").validated(ListingTarget.PAYMENTS)}
        rejects{ListingQuery(fromAt="2026-11-14T00:00:00Z").validated(ListingTarget.STAFF)}
        rejects{ListingQuery(q="bad\nvalue").validated(ListingTarget.PAYMENTS)}
        rejects{ListingQuery(q="x".repeat(81)).validated(ListingTarget.MEMBERS)}
        for(target in ListingTarget.entries){
            ok(ListingQuery.defaultsFor(target).validated(target).sort in ListingQuery.allowedSorts(target))
            ok(ListingQuery.filters(target).first()=="all")
        }
        println("PASS listing query checks $checks")
    }
}
