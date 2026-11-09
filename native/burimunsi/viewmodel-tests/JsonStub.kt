package org.json
class JSONObject{val fields=mutableMapOf<String,Any?>();fun put(k:String,v:Any?):JSONObject{fields[k]=v;return this};fun optString(k:String,fallback:String=""):String=runCatching{getString(k)}.getOrDefault(fallback);fun getString(k:String):String=fields[k] as String}
class JSONArray{fun put(v:Any?):JSONArray=this}
