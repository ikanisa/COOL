// Admission classifier only. The signed decoder remains responsible for
// decoding pixels and validating the complete image before extraction.
const SIGNATURE=[137,80,78,71,13,10,26,10];
const table=Uint32Array.from({length:256},(_,n)=>{let c=n;for(let i=0;i<8;i++)c=c&1?0xedb88320^(c>>>1):c>>>1;return c>>>0;});
const u32be=(b,p)=>(b[p]*0x1000000+b[p+1]*65536+b[p+2]*256+b[p+3])>>>0;
const u32le=(b,p)=>(b[p]+b[p+1]*256+b[p+2]*65536+b[p+3]*0x1000000)>>>0;
const name=(b,p)=>String.fromCharCode(b[p],b[p+1],b[p+2],b[p+3]);
function crc32(b,start,end){let c=0xffffffff;for(let p=start;p<end;p++)c=table[(c^b[p])&255]^(c>>>8);return(c^0xffffffff)>>>0;}

function png(b){
 if(b.length<8||SIGNATURE.some((n,i)=>b[i]!==n))return 'invalid';
 let p=8,ihdr=false,idat=false,afterIdat=false,actl=false,fdat=false;
 let canvasW=0,canvasH=0,declaredFrames=0,frames=0,sequence=0,frameData=false,frameUsesIdat=false;
 while(p<b.length){
  if(b.length-p<12)return 'invalid';
  const n=u32be(b,p);if(n>b.length-p-12)return 'invalid';
  for(let i=4;i<8;i++)if(!((b[p+i]>=65&&b[p+i]<=90)||(b[p+i]>=97&&b[p+i]<=122)))return 'invalid';
  if(b[p+6]>=97)return 'invalid'; // PNG reserved chunk-name bit.
  const type=name(b,p+4),data=p+8,end=data+n,next=end+4;
  if(crc32(b,p+4,end)!==u32be(b,end))return 'invalid';
  if(!ihdr){if(type!=='IHDR'||n!==13)return 'invalid';ihdr=true;canvasW=u32be(b,data);canvasH=u32be(b,data+4);if(!canvasW||!canvasH)return 'invalid';}
  else if(type==='IHDR')return 'invalid';
  if(type==='acTL'){
   if(actl||idat||n!==8||u32be(b,data)===0)return 'invalid';actl=true;declaredFrames=u32be(b,data);
  }else if(type==='fcTL'){
   if(!actl||n!==26||u32be(b,data)!==sequence++||(frames&&!frameData))return 'invalid';
   const w=u32be(b,data+4),h=u32be(b,data+8),x=u32be(b,data+12),y=u32be(b,data+16);
   if(!w||!h||w>canvasW||h>canvasH||x>canvasW-w||y>canvasH-h||b[data+24]>2||b[data+25]>1)return 'invalid';
   if(!idat&&(w!==canvasW||h!==canvasH||x||y))return 'invalid';
   frames++;if(frames>declaredFrames)return 'invalid';frameData=false;frameUsesIdat=!idat;
  }else if(type==='fdAT'){
   if(!actl||!idat||!frames||frameUsesIdat||n<4||u32be(b,data)!==sequence++)return 'invalid';fdat=true;if(n>4)frameData=true;
  }else if(type==='IDAT'){
   if(afterIdat||fdat)return 'invalid';idat=true;if(actl&&frames&&frameUsesIdat&&n)frameData=true;
  }else if(type==='IEND'){
   if(n!==0||!idat||next!==b.length||(actl&&(frames!==declaredFrames||!frameData)))return 'invalid';
   return actl?'animated':'static';
  }
  if(idat&&type!=='IDAT')afterIdat=true;
  p=next;
 }
 return 'invalid';
}

function webp(b){
 if(b.length<20||name(b,0)!=='RIFF'||name(b,8)!=='WEBP'||u32le(b,4)!==b.length-8)return 'invalid';
 let p=12,extended=false,flag=false,animation=false,frame=false,still=false;
 while(p<b.length){
  if(b.length-p<8)return 'invalid';
  const type=name(b,p),n=u32le(b,p+4),data=p+8;
  if(n>b.length-data)return 'invalid';
  const end=data+n,next=end+(n&1);if(next>b.length)return 'invalid';
  if(type==='VP8X'){
   if(extended||p!==12||n!==10||(b[data]&0xc1)!==0||b[data+1]||b[data+2]||b[data+3])return 'invalid';
   extended=true;flag=Boolean(b[data]&2);
  }else if(type==='ANIM'){
   if(!extended||!flag||animation||frame||n!==6||still)return 'invalid';animation=true;
  }else if(type==='ANMF'){
   if(!extended||!flag||!animation||n<16||still)return 'invalid';frame=true;
  }else if(type==='VP8 '||type==='VP8L'){
   if(flag||animation||still)return 'invalid';still=true;
  }
  p=next;
 }
 if(p!==b.length)return 'invalid';
 if(flag)return animation&&frame?'animated':'invalid';
 return animation||frame||!still?'invalid':'static';
}

// MPF lives in a JPEG APP2 segment and uses a TIFF IFD. Inspect the
// NumberOfImages tag rather than searching arbitrary metadata or entropy.
function mpf(b,start,end){
 const t=start+4;if(end-t<8)return 'invalid';
 const little=b[t]===73&&b[t+1]===73,big=b[t]===77&&b[t+1]===77;
 if(!little&&!big)return 'invalid';
 const u16=p=>little?b[p]+b[p+1]*256:b[p]*256+b[p+1];
 const u32=p=>little?u32le(b,p):u32be(b,p);
 if(u16(t+2)!==42)return 'invalid';
 const offset=u32(t+4);if(offset<8||offset>end-t-2)return 'invalid';
 const ifd=t+offset,count=u16(ifd),entries=ifd+2;
 if(count>Math.floor((end-entries-4)/12))return 'invalid';
 let images=null;
 for(let i=0;i<count;i++){
  const entry=entries+i*12;
  if(u16(entry)===0xb001){
   if(images!==null||u16(entry+2)!==4||u32(entry+4)!==1)return 'invalid';
   images=u32(entry+8);
  }
 }
 return images===null||images===0?'invalid':images>1?'animated':'static';
}

// Motion Photo JPEGs may append MP4 or QuickTime after the still. Metadata
// alone is not proof: it can remain after a video was stripped. Look only for
// structurally framed media boxes and a declared video track, never for words
// inside media payloads. This is a conservative admission check, not a media
// decoder or a claim to recognize every possible motion-photo layout.
function motionTail(b,start){
 const budget={left:8192};let candidates=0,suspicious=false;
 function box(p,end){
  if(--budget.left<0)return {limit:true};
  if(end-p<8)return null;
  let size=u32be(b,p),header=8;
  if(size===1){if(end-p<16||u32be(b,p+8)!==0)return null;size=u32be(b,p+12);header=16;}
  else if(size===0)size=end-p;
  if(size<header||size>end-p)return null;
  return {type:name(b,p+4),data:p+header,end:p+size,header};
 }
 function children(start,end,visit){
  let p=start;
  while(p<end){const current=box(p,end);if(!current)return 'bad';if(current.limit)return 'limit';
   const result=visit(current);if(result)return result;p=current.end;
  }
  return p===end?null:'bad';
 }
 function inspect(start){
  let ftyp=false,movie=false,media=false,track=false,video=false,fragment=false,broken=false;
  const result=children(start,b.length,top=>{
   if(top.type==='ftyp'){
    if(ftyp||top.end-top.data<8||(top.end-top.data)%4)return 'bad';ftyp=true;
   }else if(top.type==='mdat'){
    if(top.end>top.data)media=true;
   }else if(top.type==='moof')fragment=true;
   else if(top.type==='moov'){
    if(movie)return 'bad';movie=true;
    return children(top.data,top.end,movieBox=>{
     if(movieBox.type==='cmov')return 'bad'; // Unsupported compressed QuickTime metadata.
     if(movieBox.type!=='trak')return null;
     track=true;let handler=false;
     const outcome=children(movieBox.data,movieBox.end,trackBox=>{
      if(trackBox.type!=='mdia')return null;
      return children(trackBox.data,trackBox.end,mediaBox=>{
       if(mediaBox.type!=='hdlr')return null;
       if(handler||mediaBox.end-mediaBox.data<24)return 'bad';handler=true;
       if(name(b,mediaBox.data+8)==='vide')video=true;
       return null;
      });
     });
     return outcome||(!handler?'bad':null);
    });
   }
   return null;
  });
  if(result==='limit')return 'invalid';
  if(result==='bad')broken=true;
  if(broken)return ftyp||movie?'invalid':'none';
  if(video&&media)return 'animated';
  if((ftyp||movie||fragment)&&(!movie||!track||!media))return 'invalid';
  return movie&&track&&media?'static':'none';
 }
 for(let p=start;p+8<=b.length;p++){
  // Avoid allocating a string for every byte of a large benign trailer.
  const a=b[p+4],c=b[p+5],d=b[p+6],e=b[p+7];
  if(!((a===102&&c===116&&d===121&&e===112)||(a===109&&c===111&&d===111&&e===118)
    ||(a===109&&c===100&&d===97&&e===116)||(a===119&&c===105&&d===100&&e===101)))continue;
  if(++candidates>128)return 'invalid';
  const first=box(p,b.length);if(first?.limit)return 'invalid';
  if(!first){
   // A recognizable MP4/QuickTime brand with a broken ftyp is not a still.
   if(a===102&&p+12<=b.length&&['isom','iso2','mp41','mp42','avc1','qt  '].includes(name(b,p+8)))suspicious=true;
   continue;
  }
  const result=inspect(p);
  if(result==='animated')return result;
  if(result==='invalid')suspicious=true;
  // A merely plausible mdat can itself be padding before a real video. Only
  // an independently confirmed container may stop the byte-wise tail scan.
 }
 return suspicious?'invalid':'static';
}

function jpeg(b){
 if(b.length<4||b[0]!==255||b[1]!==216)return 'invalid';
 let p=2,sawScan=false,sawMpf=false;
 while(p<b.length){
  if(b[p++]!==255)return 'invalid';
  while(p<b.length&&b[p]===255)p++;
  if(p>=b.length)return 'invalid';
  const marker=b[p++];
  // JPEG decoders commonly accept trailing padding or metadata after EOI.
  // A valid MPO's MPF index is inside its first image and is handled above;
  // trailing bytes alone are not interpreted as an extra frame here.
  if(marker===0xd9)return sawScan?motionTail(b,p):'invalid';
  if(marker===0xd8||marker===0||marker>=0xd0&&marker<=0xd7)return 'invalid';
  if(marker===1)continue;
  if(p+2>b.length)return 'invalid';
  const size=b[p]*256+b[p+1];if(size<2||size>b.length-p)return 'invalid';
  const data=p+2,end=p+size;
  if(marker===0xe2&&end-data>=4&&name(b,data)==='MPF\0'){
   if(sawMpf)return 'invalid';sawMpf=true;
   const classification=mpf(b,data,end);if(classification!=='static')return classification;
  }
  p=end;
  if(marker===0xda){
   sawScan=true;let next=false;
   while(p<b.length){
    if(b[p++]!==255)continue;
    while(p<b.length&&b[p]===255)p++;
    if(p>=b.length)return 'invalid';
    const code=b[p++];
    if(code===0||code===1||(code>=0xd0&&code<=0xd7))continue;
    p-=2;next=true;break;
   }
   if(!next)return 'invalid';
  }
 }
 return 'invalid';
}

/** Returns only a classification; it never turns invalid data into approval. */
export function classifyRosterImage(bytes,mime){
 if(!(bytes instanceof Uint8Array))return 'invalid';
 if(mime==='image/png')return png(bytes);
 if(mime==='image/webp')return webp(bytes);
 if(mime==='image/jpeg')return jpeg(bytes);
 return 'invalid';
}
