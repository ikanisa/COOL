package rw.ikanisa.burimunsi.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.ui.semantics.Role as SemanticRole
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.*
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.cool.mobile.R
import rw.ikanisa.burimunsi.core.*

@Composable private fun PaymentRow(p:Payment,first:Boolean=true,last:Boolean=true,click:()->Unit){
    val t=LocalUiText.current
    val action=focusAction("payment:${p.id}",click)
    val status=PaymentPresentation.payment(p)
    val fontScale=LocalDensity.current.fontScale
    BoxWithConstraints(action.modifier.fillMaxWidth().heightIn(min=84.dp).background(BuriTheme.Group,rowShape(first,last)).clickable(role=SemanticRole.Button,onClick=action.click)
        .semantics(mergeDescendants=true){}.padding(horizontal=16.dp,vertical=16.dp)){
        val stacked=maxWidth<280.dp||fontScale>=1.5f
        Column(Modifier.fillMaxWidth()){
            Row(verticalAlignment=Alignment.CenterVertically){
                Avatar(p.payerNameRaw,unallocated=p.state=="unallocated");Spacer(Modifier.width(12.dp))
                Column(Modifier.weight(1f)){
                    SingleLineName(p.payerNameRaw.ifBlank{t("Unavailable")})
                    Spacer(Modifier.height(4.dp));Text(p.atRaw,fontSize=14.sp,color=BuriTheme.Muted,lineHeight=22.sp)
                    Spacer(Modifier.height(4.dp));Text(t("FT Id: %1\$s",p.ftId?:t("Unavailable")),fontSize=14.sp,color=BuriTheme.Muted,lineHeight=22.sp)
                    if(p.sourceKind=="observation"){Spacer(Modifier.height(4.dp));Text(t(PaymentPresentation.directionLabel(p.direction)),fontSize=14.sp,color=BuriTheme.Muted,lineHeight=22.sp)}
                }
                if(!stacked){
                    Spacer(Modifier.width(8.dp))
                    Column(Modifier.widthIn(max=140.dp),horizontalAlignment=Alignment.End){
                        MoneyText(p.amountRwf,size=22);Spacer(Modifier.height(6.dp))
                        Glyph(stateIcon(status.icon),status.label,stateTone(status.tone),20)
                    }
                }
            }
            if(stacked){
                Spacer(Modifier.height(10.dp))
                Row(Modifier.fillMaxWidth(),verticalAlignment=Alignment.CenterVertically){
                    MoneyText(p.amountRwf,Modifier.weight(1f),22,showHint=true)
                    Spacer(Modifier.width(12.dp));Glyph(stateIcon(status.icon),status.label,stateTone(status.tone),20)
                }
            }
        }
        if(!last)HorizontalDivider(Modifier.align(Alignment.BottomCenter),color=Color.White.copy(alpha=.08f))
    }
}
@Composable private fun MemberRow(member:Member,first:Boolean=true,last:Boolean=true,click:()->Unit){
    val t=LocalUiText.current
    val action=focusAction("member:${member.id}",click)
    val fontScale=LocalDensity.current.fontScale
    BoxWithConstraints(action.modifier.fillMaxWidth().heightIn(min=84.dp).background(BuriTheme.Group,rowShape(first,last)).clickable(role=SemanticRole.Button,onClick=action.click)
        .semantics(mergeDescendants=true){}.padding(horizontal=16.dp,vertical=16.dp)){
        val stacked=maxWidth<280.dp||fontScale>=1.5f
        Column(Modifier.fillMaxWidth()){
            Row(verticalAlignment=Alignment.CenterVertically){
                Avatar(member.name);Spacer(Modifier.width(12.dp))
                Column(Modifier.weight(1f)){
                    SingleLineName(member.name);Spacer(Modifier.height(5.dp))
                    Text(if(member.active)member.phone else t("%1\$s · %2\$s",member.phone,t("Inactive")),fontSize=14.sp,color=BuriTheme.Muted,lineHeight=22.sp)
                }
                if(!stacked){Spacer(Modifier.width(8.dp));MoneyText(member.balanceRwf,Modifier.widthIn(max=140.dp),22)}
            }
            if(stacked){Spacer(Modifier.height(10.dp));MoneyText(member.balanceRwf,Modifier.fillMaxWidth(),22,showHint=true)}
        }
        if(!last)HorizontalDivider(Modifier.align(Alignment.BottomCenter),color=Color.White.copy(alpha=.08f))
    }
}
@Composable private fun LedgerRowView(row:LedgerRow,first:Boolean=true,last:Boolean=true,click:()->Unit){
    val t=LocalUiText.current;val action=focusAction("ledger:${row.id}",click)
    BoxWithConstraints(action.modifier.fillMaxWidth().heightIn(min=84.dp).background(BuriTheme.Group,rowShape(first,last))
        .then(if(row.transactionId!=null)Modifier.clickable(role=SemanticRole.Button,onClick=action.click)else Modifier).padding(horizontal=16.dp,vertical=16.dp)){
        val stacked=maxWidth<280.dp||LocalDensity.current.fontScale>=1.5f
        Column(Modifier.fillMaxWidth()){
            Row(verticalAlignment=Alignment.CenterVertically){
                Avatar(row.payerNameRaw);Spacer(Modifier.width(12.dp));Column(Modifier.weight(1f)){
                    SingleLineName(row.payerNameRaw);Spacer(Modifier.height(5.dp));Text(row.atRaw,fontSize=13.sp,color=BuriTheme.Muted,lineHeight=19.sp)
                    Spacer(Modifier.height(5.dp));Text(t("FT Id: %1\$s",row.ftId),fontSize=13.sp,color=BuriTheme.Muted,lineHeight=19.sp)
                }
                if(!stacked){Spacer(Modifier.width(8.dp));Column(Modifier.widthIn(max=140.dp),horizontalAlignment=Alignment.End){MoneyText(row.amountRwf,size=22);Spacer(Modifier.height(5.dp));val status=PaymentPresentation.payment(row.state?:"unknown");Glyph(stateIcon(status.icon),status.label,stateTone(status.tone),16)}}
            }
            if(stacked){Spacer(Modifier.height(10.dp));Row(Modifier.fillMaxWidth(),verticalAlignment=Alignment.CenterVertically){MoneyText(row.amountRwf,Modifier.weight(1f),22,showHint=true);val status=PaymentPresentation.payment(row.state?:"unknown");Glyph(stateIcon(status.icon),status.label,stateTone(status.tone),16)}}
        }
        if(!last)HorizontalDivider(Modifier.align(Alignment.BottomCenter),color=Color.White.copy(alpha=.08f))
    }
}

@Composable internal fun HomeScreen(s:UiState,m:BuriController){
    val t=LocalUiText.current;val home=s.home
    LazyColumn(Modifier.fillMaxSize(),state=routeList(s,m),contentPadding=PaddingValues(20.dp,21.dp,20.dp,26.dp),verticalArrangement=Arrangement.spacedBy(14.dp)){
        if(home==null){item{if(s.busy){BuriInlineLoading("Loading records");BuriSkeletonRows()}else Empty(t("No records available"))};return@LazyColumn}
        item{BigValue(home.balanceRwf)}
        item{Row(Modifier.fillMaxWidth().padding(top=6.dp,bottom=11.dp),horizontalArrangement=Arrangement.SpaceEvenly){
            RoundAction(R.drawable.ic_activity,t("Open payments"),{m.navigate(Route.PAYMENTS)},!s.busy,58)
            RoundAction(R.drawable.ic_members,t("Open members"),{m.navigate(Route.MEMBERS)},!s.busy,58)
            if(m.allows(Capability.ENROLL))RoundAction(R.drawable.ic_plus,t("Add member"),{m.openSheet(Sheet.ENROLL)},!s.busy&&!s.offline,58)
            if(m.allows(Capability.SMS))RoundAction(R.drawable.ic_sms,t("Messages"),{m.navigate(Route.SMS)},!s.busy,58)
            else RoundAction(R.drawable.ic_history,t("Recent payments"),{m.navigate(Route.PAYMENTS)},!s.busy,58)
        }}
        item{Row(Modifier.fillMaxWidth().padding(horizontal=8.dp),horizontalArrangement=Arrangement.spacedBy(20.dp)){
            Column(Modifier.weight(1f)){MoneyText(home.todayRwf,size=32,showHint=true);Spacer(Modifier.height(4.dp));Text(t("Today · RWF"),color=BuriTheme.Muted,fontSize=13.sp)}
            Column(Modifier.weight(1f),horizontalAlignment=Alignment.End){Text(home.memberCount.toString(),fontSize=32.sp,lineHeight=38.sp);Spacer(Modifier.height(4.dp));Text(t("Members"),color=BuriTheme.Muted,fontSize=13.sp)}
        }}
        if(home.unallocatedCount>0)item{Row(Modifier.fillMaxWidth().background(BuriTheme.Warn.copy(alpha=.075f),RoundedCornerShape(22.dp)).clickable(enabled=!s.busy){m.openUnallocated()}.padding(horizontal=16.dp,vertical=13.dp),verticalAlignment=Alignment.CenterVertically){
            Glyph(R.drawable.ic_link,null,BuriTheme.Warn,24);Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)){Text(t("%1\$d unallocated",home.unallocatedCount),fontSize=18.sp,color=BuriTheme.Warn);Spacer(Modifier.height(2.dp));Text(home.unallocatedAmountRwf?.let{t("RWF %1\$s",money(it,t.locale))}?:t("Unavailable"),fontSize=13.sp,color=BuriTheme.Warn)}
            Glyph(R.drawable.ic_arrow,t("Open unallocated"),BuriTheme.Warn,18)
        }}
        item{Row(Modifier.fillMaxWidth().heightIn(min=48.dp),verticalAlignment=Alignment.CenterVertically){Text(t("Recent"),Modifier.weight(1f),fontSize=24.sp,fontWeight=FontWeight.SemiBold);RoundAction(R.drawable.ic_arrow,t("All payments"),{m.navigate(Route.PAYMENTS)},!s.busy,48)}}
        val recent=home.recent.take(3)
        itemsIndexed(recent,key={_,p->p.id}){index,p->PaymentRow(p,index==0,index==recent.lastIndex){m.navigate(Route.PAYMENT,p.id)}}
        if(home.recent.isEmpty())item{Empty()}
    }
}
@Composable internal fun PaymentsScreen(s:UiState,m:BuriController,onExport:()->Unit){
    val t=LocalUiText.current
    LazyColumn(Modifier.fillMaxSize(),state=routeList(s,m),contentPadding=PaddingValues(20.dp,4.dp,20.dp,26.dp)){
        item{OverviewTitle(t("Payments"));Search(s.search,m::search,m::searchSubmit,t("Search"),s.busy)}
        item{ListingToolbar(m,onExport,showFilter=false)}
        item{Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(vertical=12.dp),horizontalArrangement=Arrangement.spacedBy(10.dp)){
            FilterChipIcon(t("All"),R.drawable.ic_activity,s.filter=="all"){m.setFilter("all")}
            FilterChipIcon(t("Allocated"),R.drawable.ic_check,s.filter=="allocated"){m.setFilter("allocated")}
            val count=s.home?.unallocatedCount?:if(s.filter=="unallocated"&&s.search.isBlank())s.payments?.totalCount else null
            FilterChipIcon(t("Unallocated"),R.drawable.ic_link,s.filter=="unallocated",count){m.setFilter("unallocated")}
        }}
        item{CountLine(s.payments?.totalCount?.toString().orEmpty(),"RWF")}
        val payments=s.payments?.items.orEmpty()
        itemsIndexed(payments,key={_,p->p.id}){index,p->PaymentRow(p,index==0,index==payments.lastIndex){m.navigate(Route.PAYMENT,p.id)}}
        if(s.payments?.items?.isEmpty()==true)item{Empty(t("No payments"));Text(t("Try another search."),color=BuriTheme.Muted)}
        moreButton(s.payments?.nextCursor,s.busy,m::more,autoEnabled=!s.offline&&s.error==null)
    }
}
@Composable internal fun PaymentScreen(s:UiState,m:BuriController){
    val t=LocalUiText.current
    val p=s.payment
    if(p==null){if(s.busy)BuriLoadingPanel("Loading payment")else Empty(t("Payment unavailable. Go back or refresh."));return}
    val status=PaymentPresentation.payment(p)
    val canAllocate=PaymentPresentation.canAllocate(p)&&m.allows(Capability.ALLOCATE)
    Box(Modifier.fillMaxSize()){
        LazyColumn(Modifier.fillMaxSize().testTag("payment-details-scroll"),state=routeList(s,m),contentPadding=PaddingValues(20.dp,20.dp,20.dp,if(canAllocate)104.dp else 26.dp),verticalArrangement=Arrangement.spacedBy(12.dp)){
            item{Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.Center){
                Box(Modifier.size(78.dp).background(stateTone(status.tone).copy(alpha=if(status.tone=="good") .07f else if(status.tone=="warn") .08f else .12f),CircleShape),contentAlignment=Alignment.Center){Glyph(stateIcon(status.icon),status.label,stateTone(status.tone),36)}
            }}
            item{SingleLineName(p.payerNameRaw.ifBlank{t("Unavailable")},Modifier.fillMaxWidth(),26,TextAlign.Center)}
            item{BigValue(p.amountRwf)}
            if(!status.confirmedCredit)item{Text(t(status.label),Modifier.fillMaxWidth(),color=stateTone(status.tone),fontSize=14.sp,lineHeight=21.sp,textAlign=TextAlign.Center)}
            if(p.state=="corrected")item{Text(t("Amount on original receipt · member credit not confirmed."),Modifier.fillMaxWidth(),color=BuriTheme.Muted,fontSize=14.sp,lineHeight=21.sp,textAlign=TextAlign.Center)}
            item{FactGroup(buildList{
                if(p.sourceKind=="observation"){
                    add(t("Direction") to t(PaymentPresentation.directionLabel(p.direction)))
                    add(t("Outcome") to t(PaymentPresentation.outcomeLabel(p.outcome)))
                }
                p.paymentReference?.let{add(t("Payment reference") to it)}
                add(t("FT Id") to (p.ftId?:t("Unavailable")));add(t("at") to p.atRaw.ifBlank{t("Unavailable")})
                add((if(p.memberPhone!=null&&p.memberPhone!=p.payerPhoneRaw)t("Member MoMo")else t("MoMo")) to (p.memberPhone?:p.payerPhoneRaw.ifBlank{t("Unavailable")}))
                if(p.memberPhone!=null&&p.memberPhone!=p.payerPhoneRaw)add(t("from") to "${p.payerNameRaw} (${p.payerPhoneRaw})")
                p.feeRwf?.let{add(t("Fee") to t("RWF %1\$s",money(it,t.locale)))}
                p.walletBalanceAfterRwf?.let{add(t("Balance after") to t("RWF %1\$s",money(it,t.locale)))}
            })}
            item{Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.spacedBy(22.dp,Alignment.CenterHorizontally)){
                if(p.memberId!=null)RoundAction(R.drawable.ic_members,t("Member ledger"),{m.navigate(Route.MEMBER,p.memberId)},!s.busy,58)
                p.sourceId?.let{sourceId->if(m.allows(Capability.SMS))RoundAction(R.drawable.ic_sms,t("Original SMS"),{
                    m.openSms(if(p.sourceKind=="observation")SmsSourceRef.Observation(sourceId) else SmsSourceRef.Canonical(sourceId))
                },!s.busy,58)}
                RoundAction(R.drawable.ic_history,t("Contribution history"),{m.openSheet(Sheet.HISTORY,p.id)},!s.busy,58)
            }}
        }
        if(canAllocate)Box(Modifier.align(Alignment.BottomCenter).fillMaxWidth().padding(horizontal=20.dp).padding(bottom=13.dp)){
            Primary(t("Allocate"),{m.openSheet(Sheet.ALLOCATE)},!s.busy&&!s.offline&&!s.pending,icon=R.drawable.ic_link,modifier=Modifier.testTag("payment-allocation-fixed"))
        }
    }
}
@Composable internal fun MembersScreen(s:UiState,m:BuriController,onExport:()->Unit){
    val t=LocalUiText.current
    LazyColumn(Modifier.fillMaxSize(),state=routeList(s,m),contentPadding=PaddingValues(20.dp,4.dp,20.dp,26.dp)){
        item{OverviewTitle(t("Members"));Search(s.search,m::search,m::searchSubmit,t("Search"),s.busy)}
        item{ListingToolbar(m,onExport)}
        item{CountLine(s.members?.totalCount?.let{t("%1\$d members",it)}?:t("Unavailable"),"RWF")}
        val members=s.members?.items.orEmpty()
        itemsIndexed(members,key={_,member->member.id}){index,member->MemberRow(member,index==0,index==members.lastIndex){m.navigate(Route.MEMBER,member.id)}}
        if(s.members?.items?.isEmpty()==true)item{Empty(t("No members"));Text(t("Try a name or MoMo number."),color=BuriTheme.Muted)}
        moreButton(s.members?.nextCursor,s.busy,m::more,autoEnabled=!s.offline&&s.error==null)
    }
}
@Composable internal fun MemberScreen(s:UiState,m:BuriController,onExport:()->Unit){
    val t=LocalUiText.current
    val member=s.member
    if(member==null){if(s.busy)BuriLoadingPanel("Loading member")else Empty(t("Member unavailable. Go back or refresh."));return}
    LazyColumn(Modifier.fillMaxSize(),state=routeList(s,m),contentPadding=PaddingValues(20.dp,20.dp,20.dp,26.dp),verticalArrangement=Arrangement.spacedBy(14.dp)){
        item{Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.Center){Avatar(member.name,66,initialsSize=24)}}
        item{SingleLineName(member.name,Modifier.fillMaxWidth(),32,TextAlign.Center);Spacer(Modifier.height(8.dp));Text(if(member.active)member.phone else t("%1\$s · %2\$s",member.phone,t("Inactive")),Modifier.fillMaxWidth(),fontSize=14.sp,color=BuriTheme.Muted,lineHeight=21.sp,textAlign=TextAlign.Center)}
        item{BigValue(member.balanceRwf,60)}
        item{Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.Center){
            RoundAction(R.drawable.ic_info,t("Member details"),{m.openSheet(Sheet.MEMBER_DETAILS)},!s.busy,58)
            Spacer(Modifier.width(22.dp));RoundAction(R.drawable.ic_export,t("Download transactions"),onExport,!s.busy&&!s.offline&&m.canExportListing,58)
        }}
        item{ListingToolbar(m,onExport,showExport=false)}
        item{Row(Modifier.fillMaxWidth().heightIn(min=48.dp),verticalAlignment=Alignment.CenterVertically){Text(t("Transactions"),Modifier.weight(1f).semantics{heading()},fontSize=24.sp,fontWeight=FontWeight.SemiBold);Text(t("RWF"),fontSize=12.sp,color=BuriTheme.Muted)}}
        val transactions=s.memberTransactions?.items.orEmpty()
        itemsIndexed(transactions,key={_,payment->payment.id}){index,payment->PaymentRow(payment,index==0,index==transactions.lastIndex){m.navigate(Route.PAYMENT,payment.id)}}
        if(s.memberTransactions?.items?.isEmpty()==true)item{Empty(t("No transactions"))}
        moreButton(s.memberTransactions?.nextCursor,s.busy,m::more,autoEnabled=!s.offline&&s.error==null)
    }
}
