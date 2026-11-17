package org.json
class JSONObject{
 val fields=mutableMapOf<String,Any?>()
 fun put(k:String,v:Any?):JSONObject{fields[k]=v;return this}
 fun has(k:String)=fields.containsKey(k)
 fun isNull(k:String)=fields[k]==null
 fun optString(k:String,fallback:String=""):String=runCatching{getString(k)}.getOrDefault(fallback)
 fun getString(k:String):String=fields[k] as String
 fun getInt(k:String):Int=(fields[k] as Number).toInt()
 fun getBoolean(k:String):Boolean=fields[k] as Boolean
 fun getJSONObject(k:String)=fields[k] as JSONObject
 fun getJSONArray(k:String)=fields[k] as JSONArray
}
class JSONArray{
 private val values=mutableListOf<Any?>()
 fun put(v:Any?):JSONArray{values.add(v);return this}
 fun length()=values.size
 fun getJSONObject(i:Int)=values[i] as JSONObject
}
