package com.allinone.all_in_one

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import org.json.JSONObject

/** Data pushed by the app for the home-screen widgets. */
object WidgetData {
    private const val FILE = "aio_widgets"

    fun save(context: Context, json: String) {
        context.getSharedPreferences(FILE, Context.MODE_PRIVATE).edit().putString("data", json).apply()
        refresh(context)
    }

    fun read(context: Context): JSONObject = try {
        JSONObject(context.getSharedPreferences(FILE, Context.MODE_PRIVATE).getString("data", "{}") ?: "{}")
    } catch (e: Exception) {
        JSONObject()
    }

    fun refresh(context: Context) {
        val manager = AppWidgetManager.getInstance(context)
        for (cls in listOf(TasksWidget::class.java, NoteWidget::class.java)) {
            val ids = manager.getAppWidgetIds(ComponentName(context, cls))
            if (ids.isNotEmpty()) {
                val intent = Intent(context, cls).setAction(AppWidgetManager.ACTION_APPWIDGET_UPDATE)
                    .putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
                context.sendBroadcast(intent)
            }
        }
    }

    /** Opens the app on [target] ("new_note", "new_task" or "home"). */
    fun open(context: Context, target: String, code: Int): PendingIntent {
        val intent = Intent(context, MainActivity::class.java)
            .setAction("com.allinone.OPEN")
            .putExtra(ShareIntake.TARGET, target)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        return PendingIntent.getActivity(
            context, code, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}

/** "Tâches du jour": the next tasks, a tap opens the app, "+" adds one. */
class TasksWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        val data = WidgetData.read(context)
        val tasks = data.optJSONArray("tasks")
        val lines = StringBuilder()
        if (tasks != null) {
            for (i in 0 until minOf(tasks.length(), 6)) {
                if (i > 0) lines.append('\n')
                lines.append("•  ").append(tasks.optString(i))
            }
        }
        for (id in ids) {
            val views = RemoteViews(context.packageName, R.layout.widget_tasks)
            views.setTextViewText(R.id.widget_title, data.optString("tasksTitle", "Tâches du jour"))
            views.setTextViewText(
                R.id.widget_body,
                if (lines.isEmpty()) data.optString("tasksEmpty", "Rien de prévu") else lines.toString(),
            )
            views.setOnClickPendingIntent(R.id.widget_root, WidgetData.open(context, "home", 1))
            views.setOnClickPendingIntent(R.id.widget_add, WidgetData.open(context, "new_task", 2))
            manager.updateAppWidget(id, views)
        }
    }
}

/** "Note rapide": one tap on a blank note. */
class NoteWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        val data = WidgetData.read(context)
        for (id in ids) {
            val views = RemoteViews(context.packageName, R.layout.widget_note)
            views.setTextViewText(R.id.widget_label, data.optString("noteLabel", "Note rapide"))
            views.setOnClickPendingIntent(R.id.widget_root, WidgetData.open(context, "new_note", 3))
            manager.updateAppWidget(id, views)
        }
    }
}
