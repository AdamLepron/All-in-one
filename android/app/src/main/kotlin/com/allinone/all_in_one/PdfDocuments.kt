package com.allinone.all_in_one

import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicInteger

/** Open PDF files, rendered page by page with the system renderer. */
class PdfDocuments {
    private class Doc(val descriptor: ParcelFileDescriptor, val renderer: PdfRenderer)

    private val docs = ConcurrentHashMap<Int, Doc>()
    private val nextId = AtomicInteger(1)

    /** Returns the handle, page count and each page's size in points. */
    fun open(path: String): Map<String, Any> {
        val descriptor = ParcelFileDescriptor.open(File(path), ParcelFileDescriptor.MODE_READ_ONLY)
        val renderer = try {
            PdfRenderer(descriptor)
        } catch (e: Exception) {
            descriptor.close()
            throw e
        }
        val sizes = ArrayList<Double>(renderer.pageCount * 2)
        for (i in 0 until renderer.pageCount) {
            renderer.openPage(i).use { page ->
                sizes.add(page.width.toDouble())
                sizes.add(page.height.toDouble())
            }
        }
        val id = nextId.getAndIncrement()
        docs[id] = Doc(descriptor, renderer)
        return mapOf("id" to id, "count" to renderer.pageCount, "sizes" to sizes)
    }

    /** One page as JPEG bytes, [width] pixels wide. */
    fun render(id: Int, index: Int, width: Int): ByteArray? {
        val doc = docs[id] ?: return null
        // PdfRenderer allows a single open page at a time.
        synchronized(doc) {
            if (docs[id] == null) return null
            doc.renderer.openPage(index).use { page ->
                val w = width.coerceIn(64, 4096)
                val h = (w.toLong() * page.height / page.width).toInt().coerceIn(1, 8192)
                val bitmap = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
                bitmap.eraseColor(Color.WHITE)
                page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                return ByteArrayOutputStream().use { out ->
                    bitmap.compress(Bitmap.CompressFormat.JPEG, 92, out)
                    bitmap.recycle()
                    out.toByteArray()
                }
            }
        }
    }

    fun close(id: Int) {
        val doc = docs.remove(id) ?: return
        synchronized(doc) {
            doc.renderer.close()
            doc.descriptor.close()
        }
    }

    fun closeAll() = docs.keys.toList().forEach(::close)
}
