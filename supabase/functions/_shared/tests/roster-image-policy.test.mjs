import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {deflateSync} from 'node:zlib';
import {classifyRosterImage as classify} from '../roster_image_policy.mjs';

const corpus=new URL('../../../../tools/roster-decoder/native-probe/corpus/',import.meta.url);
const fixture=name=>new Uint8Array(readFileSync(new URL(name,corpus)));
const crcTable=Uint32Array.from({length:256},(_,n)=>{let c=n;for(let i=0;i<8;i++)c=c&1?0xedb88320^(c>>>1):c>>>1;return c>>>0;});
function crc32(bytes){let c=0xffffffff;for(const b of bytes)c=crcTable[(c^b)&255]^(c>>>8);return(c^0xffffffff)>>>0;}
function pngChunk(type,data=Buffer.alloc(0)){const kind=Buffer.from(type),out=Buffer.alloc(12+data.length);out.writeUInt32BE(data.length);kind.copy(out,4);data.copy(out,8);out.writeUInt32BE(crc32(out.subarray(4,8+data.length)),8+data.length);return out;}
const signature=Buffer.from([137,80,78,71,13,10,26,10]);
const ihdr=pngChunk('IHDR',Buffer.from([0,0,0,1,0,0,0,1,8,6,0,0,0]));
const idat=pngChunk('IDAT',deflateSync(Buffer.from([0,1,2,3,255])));
const iend=pngChunk('IEND');
const png=(...chunks)=>new Uint8Array(Buffer.concat([signature,ihdr,...chunks,iend]));
function webpChunk(type,data=Buffer.alloc(0)){const out=Buffer.alloc(8+data.length+(data.length&1));out.write(type,0,'ascii');out.writeUInt32LE(data.length,4);data.copy(out,8);return out;}
function webp(...chunks){const body=Buffer.concat([Buffer.from('WEBP'),...chunks]);const head=Buffer.alloc(8);head.write('RIFF');head.writeUInt32LE(body.length,4);return new Uint8Array(Buffer.concat([head,body]));}

test('real corpus keeps static PNG, JPEG and WebP and rejects multi-frame PNG and WebP',()=>{
 for(const [file,mime] of [['scanned-multilingual.png','image/png'],['scanned-multilingual.jpg','image/jpeg'],['scanned-multilingual.webp','image/webp']])assert.equal(classify(fixture(file),mime),'static',file);
 for(const [file,mime] of [['animation-3.png','image/png'],['animation-21.png','image/png'],['animation-3.webp','image/webp'],['animation-21.webp','image/webp']])assert.equal(classify(fixture(file),mime),'animated',file);
});

test('PNG inspects structured chunks rather than words inside image or metadata',()=>{
 assert.equal(classify(png(pngChunk('tEXt',Buffer.from('acTL fcTL fdAT')),idat),'image/png'),'static');
 const fakePayload=png(pngChunk('IDAT',Buffer.from('acTL fcTL fdAT')));
 assert.equal(classify(fakePayload,'image/png'),'static'); // Pixel validity remains the signed decoder's job.
 const actl=Buffer.alloc(8);actl.writeUInt32BE(2);
 const frame=Buffer.alloc(26);frame.writeUInt32BE(1,4);frame.writeUInt32BE(1,8);
 const second=Buffer.from(frame);second.writeUInt32BE(1);const nextFrame=Buffer.from([0,0,0,2,1]);
 assert.equal(classify(png(pngChunk('acTL',actl),pngChunk('fcTL',frame),idat,pngChunk('fcTL',second),pngChunk('fdAT',nextFrame)),'image/png'),'animated');
 assert.equal(classify(png(pngChunk('acTL',actl),pngChunk('fcTL',frame),idat),'image/png'),'invalid');
 const wrongSequence=Buffer.from(second);wrongSequence.writeUInt32BE(4);
 assert.equal(classify(png(pngChunk('acTL',actl),pngChunk('fcTL',frame),idat,pngChunk('fcTL',wrongSequence),pngChunk('fdAT',nextFrame)),'image/png'),'invalid');
 const wrongDimensions=Buffer.from(frame);wrongDimensions.writeUInt32BE(0,4);
 assert.equal(classify(png(pngChunk('acTL',actl),pngChunk('fcTL',wrongDimensions),idat),'image/png'),'invalid');
 const single=Buffer.alloc(8);single.writeUInt32BE(1);
 assert.equal(classify(png(pngChunk('acTL',single),pngChunk('fcTL',frame),idat),'image/png'),'animated');
 assert.equal(classify(png(idat,pngChunk('acTL',actl),pngChunk('fcTL',frame)),'image/png'),'invalid');
 assert.equal(classify(png(pngChunk('fcTL',frame),idat),'image/png'),'invalid');
});

test('PNG malformed CRC, lengths, order, missing end and trailing bytes fail closed',()=>{
 const good=png(idat),badCRC=good.slice();badCRC[badCRC.length-1]^=1;
 const huge=good.slice();huge.set([255,255,255,255],33);
 for(const b of [fixture('bad-crc.png'),fixture('truncated.png'),badCRC,huge,good.slice(0,-12),new Uint8Array([...good,0]),png(idat,pngChunk('tEXt'),idat)])assert.equal(classify(b,'image/png'),'invalid');
});

test('WebP permits ordinary static extended metadata and odd-sized padded chunks',()=>{
 const vp8x=Buffer.alloc(10);vp8x[0]=0x3c; // ICCP, alpha, EXIF and XMP, no animation.
 const input=webp(webpChunk('VP8X',vp8x),webpChunk('ICCP',Buffer.from('a')),webpChunk('ALPH',Buffer.from('abc')),webpChunk('VP8 ',Buffer.from('image')),webpChunk('EXIF',Buffer.from('ANIM')),webpChunk('XMP ',Buffer.from('ANMF')));
 assert.equal(classify(input,'image/webp'),'static');
 assert.equal(classify(webp(webpChunk('VP8L',Buffer.from('image'))),'image/webp'),'static');
});

test('WebP animation flags/chunks are structural, and malformed containers fail closed',()=>{
 const vp8x=Buffer.alloc(10);vp8x[0]=2;
 const anim=webpChunk('ANIM',Buffer.alloc(6)),frame=webpChunk('ANMF',Buffer.alloc(16));
 assert.equal(classify(webp(webpChunk('VP8X',vp8x),anim,frame),'image/webp'),'animated');
 const truncated=fixture('truncated.webp');
 const short=webp(webpChunk('VP8 ',Buffer.from('a'))).slice(0,-1);
 const wrongSize=webp(webpChunk('VP8 ',Buffer.from('image')));wrongSize[4]^=1;
 const noFlag=Buffer.alloc(10);
 for(const input of [truncated,short,wrongSize,webp(webpChunk('VP8X',vp8x),frame),webp(webpChunk('VP8X',noFlag),anim,frame),webp(webpChunk('VP8X',vp8x),anim)])assert.equal(classify(input,'image/webp'),'invalid');
});

function jpegSegment(marker,data){const out=Buffer.alloc(data.length+4);out[0]=255;out[1]=marker;out.writeUInt16BE(data.length+2,2);data.copy(out,4);return out;}
function jpegWithSegment(jpeg,segment){return new Uint8Array(Buffer.concat([jpeg.subarray(0,2),segment,jpeg.subarray(2)]));}
function mpfIndex(count,order='LE'){
 const t=Buffer.alloc(26);t.write(order==='LE'?'II':'MM');
 const w16=(n,p)=>order==='LE'?t.writeUInt16LE(n,p):t.writeUInt16BE(n,p);
 const w32=(n,p)=>order==='LE'?t.writeUInt32LE(n,p):t.writeUInt32BE(n,p);
 w16(42,2);w32(8,4);w16(1,8);w16(0xb001,10);w16(4,12);w32(1,14);w32(count,18);w32(0,22);
 return jpegSegment(0xe2,Buffer.concat([Buffer.from('MPF\0'),t]));
}

test('JPEG detects a real multi-picture MPO while retaining ordinary and progressive static images',()=>{
 const local=new URL('./fixtures/',import.meta.url);
 const mpo=new Uint8Array(readFileSync(new URL('roster-image-multiframe.mpo',local)));
 const progressive=new Uint8Array(readFileSync(new URL('roster-image-progressive.jpg',local)));
 assert.equal(classify(mpo,'image/jpeg'),'animated');
 assert.equal(classify(progressive,'image/jpeg'),'static');
 const ordinary=fixture('scanned-multilingual.jpg');
 assert.equal(classify(new Uint8Array([...ordinary,0,0,1,2]),'image/jpeg'),'static');
 for(const order of ['LE','BE']){
  assert.equal(classify(jpegWithSegment(ordinary,mpfIndex(1,order)),'image/jpeg'),'static');
  assert.equal(classify(jpegWithSegment(ordinary,mpfIndex(2,order)),'image/jpeg'),'animated');
 }
});

test('JPEG respects marker framing and rejects malformed MPF without matching metadata text',()=>{
 const ordinary=fixture('scanned-multilingual.jpg');
 assert.equal(classify(jpegWithSegment(ordinary,jpegSegment(0xe1,Buffer.from('MPF\0 content'))),'image/jpeg'),'static');
 assert.equal(classify(jpegWithSegment(ordinary,jpegSegment(0xe2,Buffer.from('ICC_PROFILE\0 MPF\0'))),'image/jpeg'),'static');
 const badMPF=jpegSegment(0xe2,Buffer.from('MPF\0II\x2a\0\xff\xff\xff\xff','binary'));
 assert.equal(classify(jpegWithSegment(ordinary,badMPF),'image/jpeg'),'invalid');
 assert.equal(classify(fixture('truncated.jpg'),'image/jpeg'),'invalid');
 assert.equal(classify(new Uint8Array([255,216,255,226,255,255]),'image/jpeg'),'invalid');
});

test('JPEG motion-photo admission detects a real appended H.264 MP4 or QuickTime video',()=>{
 const local=new URL('./fixtures/',import.meta.url),ordinary=fixture('scanned-multilingual.jpg');
 const mp4=readFileSync(new URL('roster-motion-h264.mp4',local)),mov=readFileSync(new URL('roster-motion-quicktime.mov',local));
 const xmp=Buffer.from('http://ns.adobe.com/xap/1.0/\0<x:xmpmeta><rdf:Description Camera:MotionPhoto="1" Item:Mime="video/mp4"/></x:xmpmeta>');
 const photo=jpegWithSegment(ordinary,jpegSegment(0xe1,xmp));
 assert.equal(classify(photo,'image/jpeg'),'static'); // MotionPhoto metadata may outlive a stripped video.
 for(const video of [mp4,mov]){
  assert.equal(classify(Buffer.concat([photo,video]),'image/jpeg'),'animated');
  assert.equal(classify(Buffer.concat([photo,Buffer.alloc(19),video]),'image/jpeg'),'animated');
  const apparentMdat=Buffer.alloc(8);apparentMdat.writeUInt32BE(video.length+8);apparentMdat.write('mdat',4);
  assert.equal(classify(Buffer.concat([photo,apparentMdat,video]),'image/jpeg'),'animated');
 }
 // A non-video-looking first container must not hide a later video item.
 const audioDecoy=Buffer.from(mp4),videoHandler=audioDecoy.indexOf(Buffer.from('vide'));
 assert.ok(videoHandler>0);audioDecoy.write('soun',videoHandler);
 assert.equal(classify(Buffer.concat([photo,audioDecoy,mp4]),'image/jpeg'),'animated');
 let audioMdat=0;while(audioMdat<audioDecoy.length&&audioDecoy.toString('ascii',audioMdat+4,audioMdat+8)!=='mdat')audioMdat+=audioDecoy.readUInt32BE(audioMdat);
 assert.ok(audioMdat<audioDecoy.length);audioDecoy.writeUInt32BE(audioDecoy.readUInt32BE(audioMdat)+mp4.length,audioMdat);
 assert.equal(classify(Buffer.concat([photo,audioDecoy,mp4]),'image/jpeg'),'animated');
 // QuickTime files may begin with `wide`/`mdat` and omit ftyp.
 const ftypSize=mov.readUInt32BE(0);
 assert.equal(classify(Buffer.concat([photo,mov.subarray(ftypSize)]),'image/jpeg'),'animated');
});

test('JPEG appended box detection handles extended/zero sizes and keeps harmless text',()=>{
 const local=new URL('./fixtures/',import.meta.url),ordinary=fixture('scanned-multilingual.jpg');
 const mp4=readFileSync(new URL('roster-motion-h264.mp4',local));
 const originalSize=mp4.readUInt32BE(0),extended=Buffer.alloc(16);
 extended.writeUInt32BE(1);extended.write('ftyp',4);extended.writeBigUInt64BE(BigInt(originalSize+8),8);
 const extendedVideo=Buffer.concat([extended,mp4.subarray(8)]);
 assert.equal(classify(Buffer.concat([ordinary,extendedVideo]),'image/jpeg'),'animated');
 const zeroMdat=Buffer.from(mp4);let p=0;
 while(p<zeroMdat.length&&zeroMdat.toString('ascii',p+4,p+8)!=='mdat')p+=zeroMdat.readUInt32BE(p);
 assert.ok(p<zeroMdat.length);zeroMdat.writeUInt32BE(0,p);
 assert.equal(classify(Buffer.concat([ordinary,zeroMdat]),'image/jpeg'),'animated');
 assert.equal(classify(Buffer.concat([ordinary,Buffer.from('leftover XMP MotionPhoto=1 and ftyp text')]),'image/jpeg'),'static');
 const truncated=mp4.subarray(0,mp4.length-1);
 assert.equal(classify(Buffer.concat([ordinary,truncated]),'image/jpeg'),'invalid');
 const suspicious=Buffer.concat(Array.from({length:129},()=>Buffer.from([0,0,0,4,102,116,121,112])));
 assert.equal(classify(Buffer.concat([ordinary,suspicious]),'image/jpeg'),'invalid');
});

test('unsupported types and unstructured inputs are refused',()=>{
 assert.equal(classify(new Uint8Array([71,73,70,56]),'image/gif'),'invalid');
 assert.equal(classify('not bytes','image/png'),'invalid');
 assert.equal(classify(new Uint8Array([137,80,78,71]),'image/png'),'invalid');
});
