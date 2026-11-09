package org.json

// TEST ONLY JSON fixture adapter. Not Android org.json qualification; never packaged in app.
private fun encode(v:Any?):String=when(v){
 null,JSONObject.NULL->"null";is JSONObject->v.fields.entries.joinToString(",","{","}"){encode(it.key)+":"+encode(it.value)}
 is JSONArray->v.items.joinToString(",","[","]"){encode(it)}
 is Boolean,is Number->v.toString()
 else->"\""+v.toString().map{c->when(c){'"'->"\\\"";'\\'->"\\\\";'\n'->"\\n";'\r'->"\\r";'\t'->"\\t";else->if(c.code<32)"\\u%04x".format(c.code) else c.toString()}}.joinToString("")+"\""
}
private class Parser(private val text:String){
 private var p=0
 private fun ws(){while(p<text.length&&text[p].isWhitespace())p++}
 private fun take(c:Char){ws();check(p<text.length&&text[p++]==c)}
 private fun string():String{take('"');val out=StringBuilder();while(p<text.length){val c=text[p++];if(c=='"')return out.toString();if(c=='\\'){check(p<text.length);when(val e=text[p++]){'u'->{check(p+4<=text.length);out.append(text.substring(p,p+4).toInt(16).toChar());p+=4};'n'->out.append('\n');'r'->out.append('\r');'t'->out.append('\t');'b'->out.append('\b');'f'->out.append('\u000c');'"','\\','/'->out.append(e);else->error("escape")}}else{check(c.code>=32);out.append(c)}};error("unclosed string")}
 private fun value():Any{ws();check(p<text.length);return when(text[p]){
 '"'->string()
 '{'->{take('{');val obj=JSONObject();ws();if(p<text.length&&text[p]=='}'){p++;obj}else{while(true){val k=string();take(':');obj.put(k,value());ws();if(text[p]=='}'){p++;break};take(',')};obj}}
 '['->{take('[');val a=JSONArray();ws();if(p<text.length&&text[p]==']'){p++;a}else{while(true){a.put(value());ws();if(text[p]==']'){p++;break};take(',')};a}}
 't'->{check(text.startsWith("true",p));p+=4;true};'f'->{check(text.startsWith("false",p));p+=5;false};'n'->{check(text.startsWith("null",p));p+=4;JSONObject.NULL}
 else->{val start=p;while(p<text.length&&text[p] in "-+0123456789.eE")p++;val raw=text.substring(start,p);check(raw.isNotEmpty());raw.toLongOrNull()?:java.math.BigDecimal(raw)}
 }}
 fun parse():Any{val v=value();ws();check(p==text.length);return v}
}
class JSONObject{
 internal val fields=linkedMapOf<String,Any?>()
 constructor()
 constructor(text:String){fields.putAll((Parser(text).parse() as JSONObject).fields)}
 companion object {val NULL=Any()}
 fun put(k:String,v:Any?):JSONObject{fields[k]=v?:NULL;return this}
 fun get(k:String):Any=fields[k]?:error("Missing $k")
 fun has(k:String)=fields.containsKey(k)
 fun isNull(k:String)=!has(k)||fields[k]===NULL
 fun getString(k:String)=get(k) as String
 fun getLong(k:String)=(get(k) as Number).toLong()
 fun getInt(k:String)=(get(k) as Number).toInt()
 fun getBoolean(k:String)=get(k) as Boolean
 fun getJSONObject(k:String)=get(k) as JSONObject
 fun getJSONArray(k:String)=get(k) as JSONArray
 fun optJSONObject(k:String):JSONObject?=fields[k] as? JSONObject
 fun optJSONArray(k:String):JSONArray?=fields[k] as? JSONArray
 fun optString(k:String,fallback:String="")=(fields[k] as? String)?:fallback
 fun optInt(k:String,fallback:Int=0)=(fields[k] as? Number)?.toInt()?:fallback
 fun optBoolean(k:String,fallback:Boolean=false)=(fields[k] as? Boolean)?:fallback
 fun keys():MutableIterator<String> =fields.keys.toMutableSet().iterator()
 fun remove(k:String){fields.remove(k)}
 fun length()=fields.size
 override fun toString()=encode(this)
}
class JSONArray{
 internal val items=mutableListOf<Any?>()
 fun put(v:Any?):JSONArray{items.add(v?:JSONObject.NULL);return this}
 fun length()=items.size
 fun get(i:Int):Any=items[i]?:JSONObject.NULL
 fun getJSONObject(i:Int)=items[i] as JSONObject
 fun getString(i:Int)=items[i] as String
 override fun toString()=encode(this)
}
