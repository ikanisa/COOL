package app.cool.mobile

import android.content.Context
import android.nfc.NdefMessage
import android.nfc.NdefRecord
import android.nfc.cardemulation.HostApduService
import android.os.Bundle

class CoolNfcHostApduService : HostApduService() {
    private var selectedFile: SelectedFile = SelectedFile.NONE

    override fun processCommandApdu(commandApdu: ByteArray?, extras: Bundle?): ByteArray {
        val apdu = commandApdu ?: return STATUS_FAILED
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val enabled = prefs.getBoolean(KEY_ENABLED, false)
        if (!enabled) {
            return STATUS_FILE_NOT_FOUND
        }

        val uri = prefs.getString(KEY_URI, null) ?: return STATUS_FILE_NOT_FOUND
        val ndefPayload = buildNdefPayload(uri)

        return when {
            isSelectNdefApp(apdu) -> {
                selectedFile = SelectedFile.NONE
                STATUS_SUCCESS
            }
            isSelectCcFile(apdu) -> {
                selectedFile = SelectedFile.CAPABILITY_CONTAINER
                STATUS_SUCCESS
            }
            isSelectNdefFile(apdu) -> {
                selectedFile = SelectedFile.NDEF
                STATUS_SUCCESS
            }
            isReadBinary(apdu) -> {
                val offset = ((apdu[2].toInt() and 0xFF) shl 8) or (apdu[3].toInt() and 0xFF)
                val length = apdu[4].toInt() and 0xFF
                val fileBytes = when (selectedFile) {
                    SelectedFile.CAPABILITY_CONTAINER -> CAPABILITY_CONTAINER_FILE
                    SelectedFile.NDEF -> ndefPayload
                    SelectedFile.NONE -> return STATUS_FILE_NOT_FOUND
                }
                val slice = readBinary(fileBytes, offset, length) ?: return STATUS_FAILED
                slice + STATUS_SUCCESS
            }
            else -> STATUS_FAILED
        }
    }

    override fun onDeactivated(reason: Int) {
        selectedFile = SelectedFile.NONE
    }

    private fun buildNdefPayload(uri: String): ByteArray {
        val message = NdefMessage(arrayOf(NdefRecord.createUri(uri)))
        val ndefMessageBytes = message.toByteArray()
        val nlen = byteArrayOf(
            ((ndefMessageBytes.size shr 8) and 0xFF).toByte(),
            (ndefMessageBytes.size and 0xFF).toByte()
        )
        return nlen + ndefMessageBytes
    }

    private fun isReadBinary(apdu: ByteArray): Boolean {
        return apdu.size >= 5 && apdu[0] == 0x00.toByte() && apdu[1] == 0xB0.toByte()
    }

    private fun isSelectNdefApp(apdu: ByteArray): Boolean {
        return apdu.size >= SELECT_NDEF_APP_HEADER.size + NDEF_AID.size &&
            apdu.copyOfRange(0, SELECT_NDEF_APP_HEADER.size).contentEquals(SELECT_NDEF_APP_HEADER) &&
            apdu.copyOfRange(5, 5 + NDEF_AID.size).contentEquals(NDEF_AID)
    }

    private fun isSelectCcFile(apdu: ByteArray): Boolean {
        return apdu.contentEquals(SELECT_CC_FILE)
    }

    private fun isSelectNdefFile(apdu: ByteArray): Boolean {
        return apdu.contentEquals(SELECT_NDEF_FILE)
    }

    private fun readBinary(payload: ByteArray, offset: Int, length: Int): ByteArray? {
        if (offset < 0 || offset > payload.size) {
            return null
        }
        val end = minOf(offset + length, payload.size)
        return payload.copyOfRange(offset, end)
    }

    companion object {
        const val PREFS_NAME = "cool_nfc_hce"
        const val KEY_ENABLED = "enabled"
        const val KEY_URI = "uri"

        private val STATUS_SUCCESS = byteArrayOf(0x90.toByte(), 0x00.toByte())
        private val STATUS_FAILED = byteArrayOf(0x6F.toByte(), 0x00.toByte())
        private val STATUS_FILE_NOT_FOUND = byteArrayOf(0x6A.toByte(), 0x82.toByte())

        private val CAPABILITY_CONTAINER_FILE = byteArrayOf(
            0x00.toByte(), 0x0F.toByte(),
            0x20.toByte(),
            0x00.toByte(), 0x3B.toByte(),
            0x00.toByte(), 0x34.toByte(),
            0x04.toByte(), 0x06.toByte(),
            0xE1.toByte(), 0x04.toByte(),
            0xFF.toByte(), 0xFE.toByte(),
            0x00.toByte(),
            0x00.toByte()
        )

        private val SELECT_NDEF_APP_HEADER = byteArrayOf(
            0x00.toByte(), 0xA4.toByte(), 0x04.toByte(), 0x00.toByte(), 0x07.toByte()
        )
        private val NDEF_AID = byteArrayOf(
            0xD2.toByte(), 0x76.toByte(), 0x00.toByte(), 0x00.toByte(), 0x85.toByte(), 0x01.toByte(), 0x01.toByte()
        )

        private val SELECT_CC_FILE = byteArrayOf(
            0x00.toByte(), 0xA4.toByte(), 0x00.toByte(), 0x0C.toByte(), 0x02.toByte(),
            0xE1.toByte(), 0x03.toByte()
        )

        private val SELECT_NDEF_FILE = byteArrayOf(
            0x00.toByte(), 0xA4.toByte(), 0x00.toByte(), 0x0C.toByte(), 0x02.toByte(),
            0xE1.toByte(), 0x04.toByte()
        )
    }

    private enum class SelectedFile {
        NONE,
        CAPABILITY_CONTAINER,
        NDEF
    }
}
