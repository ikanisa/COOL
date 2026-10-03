((a,b)=>{a[b]=a[b]||{}})(self,"$__dart_deferred_initializers__")
$__dart_deferred_initializers__.current=function(a,b,c,$){var J,A,D,B={
va(d,e){var x,w,v,u,t,s,r,q=d.i(0,"dart_sdk_version")
A:{if(typeof q=="string"){x=q.length!==0
w=q}else{w=null
x=!1}if(x){x=$.tN().dh(w)
x=x==null?null:x.b[1]
if(x==null)x=J.qt(w)
break A}x="-"
break A}v=A.a1(d.i(0,"archive"))
u=A.a1(d.i(0,"version"))
t=A.a1(d.i(0,"channel"))
s=A.aV(d.i(0,"dart_sdk_arch"))
if(s==null)s="x64"
r=b.G
return new B.ar(e+"/"+v,u,t,x,s,D.a.n(A.a1(d.i(0,"hash")),0,7),new r.Date(r.Date.parse(A.a1(d.i(0,"release_date")))))},
qH(d){var x=$.qG.i(0,d)
if(x==null){x=C.ts(A.cM("https://storage.googleapis.com/flutter_infra_release/releases/releases_"+d+".json")).aV(new B.jY(),y.j)
$.qG.k(0,d,x)}return x},
ar:function ar(d,e,f,g,h,i,j){var _=this
_.a=d
_.b=e
_.c=f
_.d=g
_.e=h
_.f=i
_.r=j},
jY:function jY(){},
jX:function jX(d){this.a=d}},C
J=c[1]
A=c[0]
D=c[2]
B=a.updateHolder(c[24],B)
C=c[35]
B.ar.prototype={}
var z=a.updateTypes(["p<ar>(bN)","ar(h?)"])
B.jY.prototype={
$1(d){var x,w,v
if(d.b===200){x=y.l.a(D.x.cf(C.yJ(C.xv(d.e)).bv(d.w),null))
w=A.a1(x.i(0,"base_url"))
v=J.j4(y.m.a(x.i(0,"releases")),new B.jX(w),y.g)
v=A.av(v,v.$ti.h("N.E"))
return v}else throw A.c(A.qF("Failed to load Flutter releases"))},
$S:z+0}
B.jX.prototype={
$1(d){return B.va(y.l.a(d),this.a)},
$S:z+1};(function inheritance(){var x=a.inherit,w=a.inheritMany
x(B.ar,A.h)
w(A.F,[B.jY,B.jX])})()
var y={g:A.d("ar"),j:A.d("p<ar>"),m:A.d("p<h?>"),l:A.d("m<a,h?>")};(function staticFields(){$.qG=A.z(A.d("a"),A.d("ab<p<ar>>"))})();(function lazyInitializers(){var x=a.lazyFinal
x($,"zN","tN",()=>A.a_("\\(build\\s(.*?)\\)"))})()};
(a=>{a["mmCPmj6JWUi5IKcZa1KgPVzaOzE="]=a.current})($__dart_deferred_initializers__);