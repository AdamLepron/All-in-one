package com.allinone.all_in_one

import android.content.Context
import java.io.File
import java.io.PrintWriter
import java.io.StringWriter
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Keeps the stack trace of a crash that happens before (or outside of) the
 * Dart side, so the next launch can show it in the incident journal.
 */
object NativeCrash {
    const val FILE = "native_crash.txt"
    private const val MAX_BYTES = 64 * 1024

    fun install(context: Context) {
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, error ->
            record(context, "uncaught (${thread.name})", error)
            previous?.uncaughtException(thread, error)
        }
    }

    fun record(context: Context, where: String, error: Throwable) {
        try {
            val trace = StringWriter().also { error.printStackTrace(PrintWriter(it)) }.toString()
            val stamp = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US).format(Date())
            val entry = "[$stamp] $where\n$trace\n"
            // The app's own files folder (read by Dart at the next launch)…
            append(File(context.filesDir, FILE), entry)
            // …and a copy a file manager can reach, for when the app cannot start.
            context.getExternalFilesDir(null)?.let { append(File(it, FILE), entry) }
        } catch (_: Throwable) {
            // Writing the report must never make things worse.
        }
    }

    private fun append(file: File, text: String) {
        val old = if (file.exists() && file.length() < MAX_BYTES) file.readText() else ""
        file.writeText(old + text)
    }
}
