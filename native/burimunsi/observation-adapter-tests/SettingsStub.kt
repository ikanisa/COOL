package android.provider

import android.content.ContentResolver

object Settings {
    object Secure {
        const val ANDROID_ID="android_id"
        var testId:String?="1234567890abcdef"
        fun getString(resolver:ContentResolver,name:String):String? = testId
    }
}
