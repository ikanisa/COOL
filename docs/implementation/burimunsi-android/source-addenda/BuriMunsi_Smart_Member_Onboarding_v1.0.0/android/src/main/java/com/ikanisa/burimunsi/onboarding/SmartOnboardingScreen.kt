package com.ikanisa.burimunsi.onboarding

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.UploadFile
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch

/** Integration UI: mount from the existing Add Member '+' entry point; reuse host navigation and existing theme. */
data class MemberSuggestion(val candidateId:String,val momoName:String,val last3:String,val evidenceCount:Int)
data class ImportMemberRow(val row:Int,val momoName:String,val momoNumber:String?,val status:String,val selected:Boolean=true)
interface OnboardingGateway {
 suspend fun suggestions(search:String):List<MemberSuggestion>
 suspend fun createMember(name:String,phone:String,candidateId:String?,ownershipVerified:Boolean,termsAccepted:Boolean,consentRecorded:Boolean):String
 suspend fun extractDocument(mimeType:String,content:ByteArray):List<ImportMemberRow>
 suspend fun importReviewed(rows:List<ReviewedMember>):ImportSummary
}
data class ReviewedMember(val row:Int,val momoName:String,val momoNumber:String,val selected:Boolean,val ownershipVerified:Boolean,val termsAccepted:Boolean,val consentRecorded:Boolean)
data class ImportSummary(val created:Int,val rejected:Int)
private val orange=Color(0xFFFF733E)
private val violet=Color(0xFF5144C9)
private enum class Step { OPTIONS, SUGGESTIONS, FORM, IMPORT }

@Composable
fun SmartOnboardingScreen(
 gateway:OnboardingGateway,
 onBack:()->Unit,
 onMemberCreated:(String)->Unit,
 onPickImportFile:()->Unit,
 selectedFile:Pair<String,ByteArray>?=null
) {
 var step by remember { mutableStateOf(Step.OPTIONS) }
 var search by remember { mutableStateOf("") }
 var suggestions by remember { mutableStateOf<List<MemberSuggestion>>(emptyList()) }
 var selected by remember { mutableStateOf<MemberSuggestion?>(null) }
 var name by remember { mutableStateOf("") }
 var phone by remember { mutableStateOf("") }
 var ownership by remember { mutableStateOf(false) }
 var terms by remember { mutableStateOf(false) }
 var consent by remember { mutableStateOf(false) }
 var loading by remember { mutableStateOf(false) }
 var error by remember { mutableStateOf<String?>(null) }
 var imported by remember { mutableStateOf<List<ImportMemberRow>>(emptyList()) }
 var completed by remember { mutableStateOf<String?>(null) }
 var editingImportRow by remember { mutableStateOf<Int?>(null) }
 val verifiedRows = remember { mutableStateMapOf<Int,ReviewedMember>() }
 val scope= rememberCoroutineScope()
 // Debounced search should be provided by the host ViewModel/Flow; this module fetches on explicit search.
 LaunchedEffect(step,selectedFile) {
  if(step==Step.IMPORT && selectedFile!=null) {
   loading=true; error=null
   try { imported=gateway.extractDocument(selectedFile.first,selectedFile.second);verifiedRows.clear() }
   catch(e:Exception){error=e.message?:"Import failed"}
   finally{loading=false}
  }
 }
 Column(Modifier.fillMaxSize()) {
  Row(Modifier.fillMaxWidth().padding(16.dp),verticalAlignment=Alignment.CenterVertically) {
   IconButton(onClick={if(step==Step.OPTIONS) onBack() else {step=Step.OPTIONS;error=null}}){Icon(Icons.Default.ArrowBack,"Back")}
   Column { Text("BuriMunsi",color=violet,style=MaterialTheme.typography.titleLarge,fontWeight=FontWeight.Bold)
    Text("Add members",style=MaterialTheme.typography.titleMedium) }
  }
  HorizontalDivider()
  Column(Modifier.fillMaxWidth().padding(horizontal=18.dp, vertical=14.dp)) {
   error?.let { Text(it,color=MaterialTheme.colorScheme.error);Spacer(Modifier.height(10.dp)) }
   completed?.let {Text(it,color=violet);Spacer(Modifier.height(10.dp))}
   if(loading) LinearProgressIndicator(Modifier.fillMaxWidth())
   when(step) {
    Step.OPTIONS -> {
     Text("How would you like to add members?",style=MaterialTheme.typography.titleMedium,fontWeight=FontWeight.SemiBold)
     Spacer(Modifier.height(18.dp))
     OptionTile("Suggested from MoMo", "Search unmatched payer names and last 3 digits") {step=Step.SUGGESTIONS;scope.launch {loading=true;try{suggestions=gateway.suggestions("")}catch(e:Exception){error=e.message}finally{loading=false}}}
     OptionTile("Add manually", "Enter a verified MoMo name and number") {selected=null;editingImportRow=null;name="";phone="";ownership=false;terms=false;consent=false;step=Step.FORM}
     OptionTile("Import member list", "Upload or scan, review, then register") {step=Step.IMPORT;onPickImportFile()}
    }
    Step.SUGGESTIONS -> {
     Text("Suggested members",style=MaterialTheme.typography.titleLarge,fontWeight=FontWeight.Bold)
     Text("From received MoMo messages · Not yet registered",style=MaterialTheme.typography.bodySmall)
     Spacer(Modifier.height(12.dp))
     OutlinedTextField(search,{search=it},Modifier.fillMaxWidth(),label={Text("Search by name or last 3 digits")},leadingIcon={Icon(Icons.Default.Search,null)},singleLine=true)
     Spacer(Modifier.height(8.dp))
     Button(onClick={scope.launch{loading=true;error=null;try{suggestions=gateway.suggestions(search)}catch(e:Exception){error=e.message}finally{loading=false}}},enabled=!loading) {Text("Search")}
     Spacer(Modifier.height(8.dp))
     if(suggestions.isEmpty()&&!loading) Text("No eligible suggestions found. You can add a member manually.")
     LazyColumn(contentPadding=PaddingValues(bottom=28.dp)) {
      items(suggestions,key={it.candidateId}) {s->
       ListItem(headlineContent={Text(s.momoName,fontWeight=FontWeight.SemiBold)},supportingContent={Text("MoMo number ···${s.last3}  ·  ${s.evidenceCount} message(s)")},trailingContent={Text("Select",color=violet)},modifier=Modifier.clickable {
        selected=s;name=s.momoName;phone="";ownership=false;terms=false;consent=false;step=Step.FORM
       })
       HorizontalDivider()
      }
     }
    }
    Step.FORM -> {
     Text("Complete member details",style=MaterialTheme.typography.titleLarge,fontWeight=FontWeight.Bold)
     if(selected!=null) Text("Suggested from MoMo ···${selected!!.last3} — verify the full number",style=MaterialTheme.typography.bodySmall)
     Spacer(Modifier.height(12.dp))
     OutlinedTextField(name,{name=it},Modifier.fillMaxWidth(),label={Text("MoMo registered name")},singleLine=true)
     Spacer(Modifier.height(10.dp))
     OutlinedTextField(phone,{phone=it},Modifier.fillMaxWidth(),label={Text("Full MoMo number")},keyboardOptions=KeyboardOptions(keyboardType=KeyboardType.Phone),singleLine=true)
     Spacer(Modifier.height(12.dp))
     Row(verticalAlignment=Alignment.CenterVertically){Checkbox(ownership,{ownership=it});Text("Full number and phone ownership verified")}
     Row(verticalAlignment=Alignment.CenterVertically){Checkbox(terms,{terms=it});Text("Member accepted BSM savings terms")}
     Row(verticalAlignment=Alignment.CenterVertically){Checkbox(consent,{consent=it});Text("Privacy notice and consent recorded")}
     Spacer(Modifier.height(14.dp))
     Button(onClick={scope.launch {loading=true;error=null;try {
       val row=editingImportRow
       if(row!=null) {
        verifiedRows[row]=ReviewedMember(row,name,phone,true,ownership,terms,consent)
        completed="Row $row verified and ready for bulk registration"
        editingImportRow=null;step=Step.IMPORT
       }else {val id=gateway.createMember(name,phone,selected?.candidateId,ownership,terms,consent);onMemberCreated(id)}
      } catch(e:Exception){error=e.message}finally{loading=false}}},enabled=!loading&&ownership&&terms&&consent&&phone.isNotBlank()&&name.isNotBlank(),colors=ButtonDefaults.buttonColors(containerColor=violet),modifier=Modifier.fillMaxWidth()) {Icon(Icons.Default.Check,null);Spacer(Modifier.width(8.dp));Text(if(editingImportRow==null) "Save member" else "Add verified row to batch")}
     Text("This does not allocate or confirm previous payments.",style=MaterialTheme.typography.bodySmall)
    }
    Step.IMPORT -> {
     Text("Import member list",style=MaterialTheme.typography.titleLarge,fontWeight=FontWeight.Bold)
     Text("Upload a clear photo; extracted entries must be verified before registration.",style=MaterialTheme.typography.bodyMedium)
     Spacer(Modifier.height(12.dp))
     OutlinedButton(onClick=onPickImportFile) {Icon(Icons.Default.UploadFile,null);Spacer(Modifier.width(8.dp));Text("Choose another file")}
     Spacer(Modifier.height(8.dp))
     if(imported.isNotEmpty()) {
      val ready=imported.count{it.status=="ready"}
      Text("${imported.size} extracted · $ready need staff review",fontWeight=FontWeight.Bold)
      Text("Open each row, correct OCR mistakes and record ownership and consent checks.",style=MaterialTheme.typography.bodySmall)
      Text("${verifiedRows.size} verified for import",color=violet,fontWeight=FontWeight.SemiBold)
      Button(onClick={scope.launch {
       loading=true;error=null
       try {
        val result=gateway.importReviewed(verifiedRows.values.sortedBy { it.row })
        completed="${result.created} members registered; ${result.rejected} not registered"
        verifiedRows.clear();imported=emptyList()
       } catch(e:Exception){error=e.message} finally{loading=false}
      }},enabled=!loading&&verifiedRows.isNotEmpty(),colors=ButtonDefaults.buttonColors(containerColor=violet)) {Text("Register verified members (${verifiedRows.size})")}
     }
     LazyColumn { items(imported,key={it.row}) { r ->
      ListItem(headlineContent={Text(r.momoName.ifBlank { "Unreadable name" })},supportingContent={Text("${r.momoNumber?:"Number missing"} · ${r.status}")},trailingContent={Text("Review",color=violet)},modifier=Modifier.clickable {
        name=r.momoName;phone=r.momoNumber?:"";selected=null;editingImportRow=r.row;ownership=false;terms=false;consent=false;step=Step.FORM
      })
      HorizontalDivider()
     }}
    }
   }
  }
 }
}
@Composable private fun OptionTile(title:String,detail:String,onClick:()->Unit) {
 ElevatedCard(onClick=onClick,shape=RoundedCornerShape(16.dp),modifier=Modifier.fillMaxWidth().padding(bottom=12.dp)) {
  Row(Modifier.padding(18.dp),verticalAlignment=Alignment.CenterVertically) {
   Icon(Icons.Default.Add,null,tint=orange);Spacer(Modifier.width(14.dp))
   Column {Text(title,fontWeight=FontWeight.Bold);Text(detail,style=MaterialTheme.typography.bodySmall)}
  }
 }
}
