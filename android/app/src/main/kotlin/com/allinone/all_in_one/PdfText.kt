package com.allinone.all_in_one

import android.content.Context
import com.tom_roush.pdfbox.android.PDFBoxResourceLoader
import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.pdmodel.interactive.documentnavigation.outline.PDOutlineItem
import com.tom_roush.pdfbox.text.PDFTextStripper
import com.tom_roush.pdfbox.text.TextPosition
import java.io.File

/**
 * Reads what the system renderer cannot give: the table of contents of a PDF
 * and where a word appears on its pages.
 */
class PdfText(context: Context) {
    init {
        PDFBoxResourceLoader.init(context.applicationContext)
    }

    /** Table of contents as a flat list: title, 0-based page, nesting level. */
    fun outline(path: String): List<Map<String, Any>> {
        PDDocument.load(File(path)).use { doc ->
            val root = doc.documentCatalog.documentOutline ?: return emptyList()
            val out = ArrayList<Map<String, Any>>()
            fun walk(first: PDOutlineItem?, level: Int) {
                var item = first
                while (item != null && out.size < 2000) {
                    val page = try {
                        val target = item.findDestinationPage(doc)
                        if (target == null) -1 else doc.pages.indexOf(target)
                    } catch (e: Exception) {
                        -1
                    }
                    out.add(mapOf("title" to (item.title ?: ""), "page" to page, "level" to level))
                    if (level < 6) walk(item.firstChild, level + 1)
                    item = item.nextSibling
                }
            }
            walk(root.firstChild, 0)
            return out
        }
    }

    /**
     * Every occurrence of [query]: its 0-based page, a short snippet and the
     * boxes to highlight, as [left, top, right, bottom] fractions of the page.
     */
    fun search(path: String, query: String, caseSensitive: Boolean): List<Map<String, Any>> {
        val needle = if (caseSensitive) query else query.lowercase()
        if (needle.isEmpty()) return emptyList()
        val hits = ArrayList<Map<String, Any>>()
        PDDocument.load(File(path)).use { doc ->
            for (pageIndex in 0 until doc.numberOfPages) {
                if (hits.size >= MAX_HITS) break
                val page = doc.getPage(pageIndex)
                val box = page.cropBox
                val rotated = page.rotation % 180 != 0
                val pageW = (if (rotated) box.height else box.width).toDouble()
                val pageH = (if (rotated) box.width else box.height).toDouble()

                val text = StringBuilder()
                // For each character of [text]: the position it came from, or null.
                val owners = ArrayList<TextPosition?>()
                val stripper = object : PDFTextStripper() {
                    override fun writeString(string: String?, positions: MutableList<TextPosition>?) {
                        if (positions != null) {
                            for (p in positions) {
                                val u = p.unicode ?: continue
                                for (ch in u) {
                                    text.append(ch)
                                    owners.add(p)
                                }
                            }
                        }
                        text.append('\n')
                        owners.add(null)
                    }
                }
                stripper.sortByPosition = true
                stripper.startPage = pageIndex + 1
                stripper.endPage = pageIndex + 1
                stripper.getText(doc)

                val hay = if (caseSensitive) text.toString() else text.toString().lowercase()
                // Lower-casing may change lengths; positions would drift, so skip then.
                if (hay.length != text.length) continue
                var from = 0
                while (hits.size < MAX_HITS) {
                    val i = hay.indexOf(needle, from)
                    if (i < 0) break
                    val end = i + needle.length
                    from = end
                    val rects = ArrayList<List<Double>>()
                    var current: DoubleArray? = null
                    var currentBase = 0.0
                    for (k in i until end) {
                        val p = owners[k] ?: continue
                        val left = p.xDirAdj.toDouble()
                        val right = left + p.widthDirAdj
                        val bottom = p.yDirAdj.toDouble()
                        val top = bottom - p.heightDir
                        if (current != null && Math.abs(bottom - currentBase) < p.heightDir / 2) {
                            current[0] = Math.min(current[0], left)
                            current[1] = Math.min(current[1], top)
                            current[2] = Math.max(current[2], right)
                            current[3] = Math.max(current[3], bottom)
                        } else {
                            current?.let { rects.add(norm(it, pageW, pageH)) }
                            current = doubleArrayOf(left, top, right, bottom)
                            currentBase = bottom
                        }
                    }
                    current?.let { rects.add(norm(it, pageW, pageH)) }
                    if (rects.isEmpty()) continue
                    val s = Math.max(0, i - 25)
                    val e = Math.min(text.length, end + 25)
                    hits.add(
                        mapOf(
                            "page" to pageIndex,
                            "snippet" to text.substring(s, e).replace('\n', ' ').trim(),
                            "rects" to rects,
                        )
                    )
                }
            }
        }
        return hits
    }

    private fun norm(r: DoubleArray, w: Double, h: Double): List<Double> = listOf(
        (r[0] / w).coerceIn(0.0, 1.0),
        (r[1] / h).coerceIn(0.0, 1.0),
        (r[2] / w).coerceIn(0.0, 1.0),
        (r[3] / h).coerceIn(0.0, 1.0),
    )

    private companion object {
        const val MAX_HITS = 500
    }
}
