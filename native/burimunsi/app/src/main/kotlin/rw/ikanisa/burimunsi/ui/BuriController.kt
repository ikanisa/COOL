package rw.ikanisa.burimunsi.ui

import rw.ikanisa.burimunsi.core.*

/** UI contract; device, network and financial authority remain outside composables. */
interface BuriController {
    val state:UiState
    val presentation:ScreenPresentation get()=state.presentation(screenGate,System.currentTimeMillis())
    val screenGate:ScreenGate get()=ScreenGate.OPEN
    fun allows(capability:Capability):Boolean
    fun login(phone:String,pin:String)
    fun logout()
    fun navigate(route:Route,id:String?=null)
    fun listPosition(route:Route,id:String?,index:Int,offset:Int) {}
    fun editDraft(key:String,value:String) {}
    fun discardDraft() {}
    fun keepDraft() {}
    fun back()
    fun openUnallocated()
    fun search(value:String)
    fun searchSubmit()
    fun setFilter(value:String)
    fun refresh()
    fun more()
    fun openSheet(sheet:Sheet,id:String?=null)
    fun closeSheet()
    fun selectMember(member:Member)
    fun allocationSearch(q:String)
    fun allocate(note:String)
    fun enroll(name:String,phone:String)
    fun changePin(current:String,next:String,confirm:String)
    fun saveStaff(name:String,phone:String,pin:String,enroll:Boolean,allocate:Boolean)
    fun staffAction(action:String,pin:String?=null)
    fun requestRemoveStaff()
    fun setMemberActive(active:Boolean)
    fun pair(code:String)
    fun setPaused(value:Boolean)
    fun retry()
}
