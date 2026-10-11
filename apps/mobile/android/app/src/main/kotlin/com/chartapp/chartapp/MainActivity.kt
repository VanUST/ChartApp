// PURPOSE: Write a `.chart` or a `.setlist` container to the destination the reader chooses in the
//          operating system's own save dialog, which is the one file operation the `file_selector`
//          plugin cannot perform on Android. It answers the `saveDocument` method on the channel
//          `chartapp/file_save`, whose Dart end is `native_file_dialog.dart`.
//
// INPUTS: `name` — the file name to propose, with its extension; the reader may change it. `bytes` —
//         the whole encoded container, arriving as a [ByteArray] because Dart's `Uint8List` maps to
//         it in the standard message codec.
//
// OUTPUTS: `true` once the bytes are written, `false` when the reader dismissed the dialog or chose
//          nothing — a dismissal is an outcome and not an error, so it is not reported as one. A
//          `PlatformException` carries what actually went wrong in the cases that are failures: no
//          bytes in the request, a second save while one dialog is already open, an activity that
//          refuses the intent, a destination that opens no stream, and a write that throws. Every
//          one of those reaches the reader as the typed message the file dialog already prints.
//
// KEYWORDS: android, action-create-document, content-resolver, method-channel, file-save,
//           scoped-storage, saf
//
// WHY THIS IS A CHANNEL AND NOT A PLUGIN. `file_selector` documents `getSaveLocation` as unsupported
// on Android, and flutter/flutter#168318 records why: the Android file API answers with a
// `content://` URI that only the platform's own document API can write. That is one intent and one
// output stream, so owning them here costs about forty lines and no dependency; a second plugin for
// the same intent would be a second package to keep current.
//
// WHY `ACTION_CREATE_DOCUMENT` AND NOT A PATH. Android's scoped storage means this application
// cannot write to another application's directory by path without a storage permission, and this
// manifest deliberately declares none. The document API is not a workaround for that restriction;
// it is the supported way to put a file where the musician can find it, and the platform handles
// the permission for the one file the reader picked.
//
// WHY `startActivityForResult` IS USED EVEN THOUGH IT IS DEPRECATED. `FlutterActivity` is the
// activity here and the deprecated pair is the API that works on it without assuming a superclass
// it may not have. The request code is this file's own, and every call that is not ours is handed
// straight to `super`, so a plugin that listens on the legacy path still receives its results.
package com.chartapp.chartapp

import android.app.Activity
import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    /** The bytes of the save that is waiting on the reader, or null when none is. */
    private var pendingBytes: ByteArray? = null

    /** The Dart-side reply for that save, or null when none is waiting. */
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SAVE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveDocument" ->
                        startSaveDocument(
                            name = call.argument<String>("name") ?: DEFAULT_NAME,
                            bytes = call.argument<ByteArray>("bytes"),
                            result = result,
                        )
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Opens the system's create-document dialog, remembering the bytes until the reader answers.
     *
     * The bytes are held rather than written here because the destination does not exist yet; the
     * dialog is what names it, and [onActivityResult] writes once it has.
     */
    private fun startSaveDocument(name: String, bytes: ByteArray?, result: MethodChannel.Result) {
        if (bytes == null) {
            result.error("INVALID_ARGUMENT", "saveDocument needs the bytes to write.", null)
            return
        }
        if (pendingResult != null) {
            result.error("BUSY", "Another save dialog is already open.", null)
            return
        }
        pendingBytes = bytes
        pendingResult = result
        val intent =
            Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                // No MIME type is registered for `.chart` or `.setlist`, so the generic binary type
                // is the honest one; `EXTRA_TITLE` is what preserves the extension the reader sees.
                type = MIME_TYPE
                putExtra(Intent.EXTRA_TITLE, name)
            }
        try {
            startActivityForResult(intent, SAVE_DOCUMENT_REQUEST)
        } catch (error: Exception) {
            pendingBytes = null
            pendingResult = null
            result.error("NO_ACTIVITY", error.message, null)
        }
    }

    /**
     * Writes the remembered bytes to the document the reader chose.
     *
     * A request code that is not this file's is forwarded to `super` untouched, so the plugins that
     * use the legacy result path keep working. A cancelled dialog answers `false` rather than an
     * error, because changing one's mind is not a fault.
     */
    @Suppress("DEPRECATION", "OVERRIDE_DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != SAVE_DOCUMENT_REQUEST) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }
        val bytes = pendingBytes
        val result = pendingResult
        pendingBytes = null
        pendingResult = null
        if (result == null) {
            return
        }
        if (resultCode != Activity.RESULT_OK || bytes == null) {
            result.success(false)
            return
        }
        val uri = data?.data
        if (uri == null) {
            result.success(false)
            return
        }
        val stream =
            try {
                contentResolver.openOutputStream(uri)
            } catch (error: Exception) {
                result.error("OPEN_FAILED", error.message, null)
                return
            }
        if (stream == null) {
            result.error("NO_STREAM", "The chosen destination opened no stream.", null)
            return
        }
        try {
            stream.use { output ->
                output.write(bytes)
                output.flush()
            }
            result.success(true)
        } catch (error: Exception) {
            result.error("WRITE_FAILED", error.message, null)
        }
    }

    private companion object {
        /** The channel `native_file_dialog.dart` invokes. Renaming one end alone breaks saving. */
        const val SAVE_CHANNEL = "chartapp/file_save"

        /** This activity's own request code, kept clear of the plugin's (221/222/223). */
        const val SAVE_DOCUMENT_REQUEST = 4801

        /** The generic binary type: no MIME type is registered for these containers. */
        const val MIME_TYPE = "application/octet-stream"

        /** Used only when the request carries no name at all, which the Dart side never sends. */
        const val DEFAULT_NAME = "document"
    }
}
