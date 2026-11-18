package com.allinone.all_in_one

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.provider.OpenableColumns
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.ExecutorService

/**
 * Receives what other apps share with us ("Share" menu) or ask us to open
 * ("Open with"). Shared content is copied to the app's cache, so Dart gets
 * ordinary file paths, and handed over once the Dart side is ready.
 */
class ShareIntake(
    private val activity: Activity,
    private val executor: ExecutorService,
    private val main: Handler,
) {
    var channel: MethodChannel? = null
    private var dartReady = false
    private var pending: Map<String, Any?>? = null

    /** Reads [intent], once. Safe to call with any intent. */
    fun handle(intent: Intent?) {
        intent ?: return
        val action = intent.action ?: return
        if (action != Intent.ACTION_SEND && action != Intent.ACTION_SEND_MULTIPLE && action != Intent.ACTION_VIEW) return
        // An intent is processed once, even if the activity is recreated.
        if (intent.getBooleanExtra(HANDLED, false)) return
        intent.putExtra(HANDLED, true)

        val uris = ArrayList<Uri>()
        var text: String? = null
        when (action) {
            Intent.ACTION_SEND -> {
                streamUri(intent)?.let { uris.add(it) }
                if (uris.isEmpty()) text = intent.getStringExtra(Intent.EXTRA_TEXT)
            }
            Intent.ACTION_SEND_MULTIPLE -> uris.addAll(streamUris(intent))
            Intent.ACTION_VIEW -> intent.data?.let { uris.add(it) }
        }
        val type = intent.type
        val view = action == Intent.ACTION_VIEW
        executor.execute {
            val files = uris.mapNotNull { copy(it, type) }
            if (files.isNotEmpty() || !text.isNullOrBlank()) {
                val result = mapOf(
                    "action" to if (view) "view" else "send",
                    "text" to text,
                    "files" to files,
                )
                main.post { deliver(result) }
            }
        }
    }

    /** Called by Dart once its handler is set: returns what arrived before. */
    fun take(): Map<String, Any?>? {
        dartReady = true
        val result = pending
        pending = null
        return result
    }

    private fun deliver(result: Map<String, Any?>) {
        if (dartReady && channel != null) channel!!.invokeMethod("sharedArrived", result) else pending = result
    }

    private fun streamUri(intent: Intent): Uri? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(Intent.EXTRA_STREAM)
        }

    private fun streamUris(intent: Intent): List<Uri> =
        (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
        }) ?: emptyList()

    /** Copies one shared item into the cache; null when it cannot be read. */
    private fun copy(uri: Uri, fallbackType: String?): Map<String, Any?>? {
        return try {
            val resolver = activity.contentResolver
            var name: String? = null
            if (uri.scheme == "content") {
                resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
                    if (c.moveToFirst()) name = c.getString(0)
                }
            }
            val clean = (name ?: uri.lastPathSegment ?: "fichier")
                .substringAfterLast('/')
                .replace(Regex("[\\\\/:*?\"<>|\\u0000-\\u001f]"), "_")
                .trimStart('.')
                .ifEmpty { "fichier" }
            val root = File(activity.cacheDir, "share_in")
            sweep(root)
            val dir = File(root, System.nanoTime().toString()).also { it.mkdirs() }
            val target = File(dir, clean)
            resolver.openInputStream(uri)?.use { input ->
                target.outputStream().use { input.copyTo(it) }
            } ?: return null
            mapOf(
                "path" to target.absolutePath,
                "name" to clean,
                "mime" to (resolver.getType(uri) ?: fallbackType),
            )
        } catch (e: Exception) {
            null
        }
    }

    /** Removes copies older than a day. */
    private fun sweep(root: File) {
        val limit = System.currentTimeMillis() - 24L * 3600 * 1000
        root.listFiles()?.forEach { if (it.lastModified() < limit) it.deleteRecursively() }
    }

    private companion object {
        const val HANDLED = "allinone_handled"
    }
}
