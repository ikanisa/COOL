package rw.ikanisa.burimunsi

import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import android.net.Uri
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.FileProvider
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File

/** The system camera owns capture; no camera or shared-media permission is needed. */
internal class MemberPhotoCaptureContract:ActivityResultContracts.TakePicture(){
    override fun createIntent(context:Context,input:Uri):Intent=super.createIntent(context,input).apply{
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
        clipData=ClipData.newRawUri("Member list photo",input)
    }
}

internal fun memberPhotoUri(context:Context,file:File):Uri=
    FileProvider.getUriForFile(context,context.packageName+".member-photo",file)

/** Bounded, orientation-corrected JPEG input for the existing OCR preview. */
internal fun prepareMemberPhoto(source:ByteArray):ByteArray{
    var decoded:Bitmap?=null;var oriented:Bitmap?=null
    try{
        val bounds=BitmapFactory.Options().apply{inJustDecodeBounds=true}
        BitmapFactory.decodeByteArray(source,0,source.size,bounds)
        require(bounds.outWidth>0&&bounds.outHeight>0)
        if(bounds.outWidth.toLong()*bounds.outHeight>100_000_000L)throw MemberDocumentTooLarge()
        var sample=1
        while(maxOf(bounds.outWidth,bounds.outHeight)/sample>2560)sample*=2
        decoded=BitmapFactory.decodeByteArray(source,0,source.size,BitmapFactory.Options().apply{
            inSampleSize=sample;inPreferredConfig=Bitmap.Config.ARGB_8888
        })?:error("member_photo_unreadable")
        val orientation=runCatching{ByteArrayInputStream(source).use{ExifInterface(it).getAttributeInt(ExifInterface.TAG_ORIENTATION,ExifInterface.ORIENTATION_NORMAL)}}.getOrDefault(ExifInterface.ORIENTATION_NORMAL)
        val matrix=Matrix().apply{when(orientation){
            ExifInterface.ORIENTATION_FLIP_HORIZONTAL->setScale(-1f,1f)
            ExifInterface.ORIENTATION_ROTATE_180->setRotate(180f)
            ExifInterface.ORIENTATION_FLIP_VERTICAL->setScale(1f,-1f)
            ExifInterface.ORIENTATION_TRANSPOSE->{setRotate(90f);postScale(-1f,1f)}
            ExifInterface.ORIENTATION_ROTATE_90->setRotate(90f)
            ExifInterface.ORIENTATION_TRANSVERSE->{setRotate(270f);postScale(-1f,1f)}
            ExifInterface.ORIENTATION_ROTATE_270->setRotate(270f)
        }}
        oriented=Bitmap.createBitmap(decoded,0,0,decoded.width,decoded.height,matrix,true)
        val output=object:ByteArrayOutputStream(){fun wipe(){buf.fill(0)}}
        try{
            for(quality in listOf(90,80,70)){
                output.wipe();output.reset()
                check(oriented.compress(Bitmap.CompressFormat.JPEG,quality,output))
                if(output.size() in 1..5*1024*1024)return output.toByteArray()
            }
            throw MemberDocumentTooLarge()
        }finally{output.wipe();output.close()}
    }finally{if(oriented!==decoded)oriented?.recycle();decoded?.recycle();source.fill(0)}
}
