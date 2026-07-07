package com.example.menstrul_track

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Home-screen widget for LunaTrack. Renders the two strings pushed from Dart
 * (`value` + `caption`, see HomeWidgetService) and opens the app when tapped.
 * The provider only re-renders the last pushed data — the countdown is computed
 * in Dart and refreshed whenever the app runs.
 */
class LunaWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.luna_widget).apply {
                setTextViewText(
                    R.id.widget_value,
                    widgetData.getString("value", "—") ?: "—",
                )
                setTextViewText(
                    R.id.widget_caption,
                    widgetData.getString("caption", "Tap to log your period")
                        ?: "Tap to log your period",
                )
                val pendingIntent =
                    HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java)
                setOnClickPendingIntent(R.id.widget_root, pendingIntent)
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
