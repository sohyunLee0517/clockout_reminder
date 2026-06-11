package com.isohyeon.clockout_reminder

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/// 출퇴근 버튼 홈 위젯.
class ClockoutWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.clockout_widget).apply {
                setTextViewText(
                    R.id.widget_status,
                    widgetData.getString("status", "출근 전"),
                )
                setTextViewText(
                    R.id.widget_subtitle,
                    widgetData.getString("subtitle", "출근 버튼을 눌러 시작하세요"),
                )

                // 위젯 본문 탭 → 앱 열기
                setOnClickPendingIntent(
                    R.id.widget_root,
                    HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java),
                )

                // 출근 버튼 → 백그라운드 콜백(clockoutwidget://checkin)
                setOnClickPendingIntent(
                    R.id.btn_checkin,
                    HomeWidgetBackgroundIntent.getBroadcast(
                        context,
                        Uri.parse("clockoutwidget://checkin"),
                    ),
                )

                // 퇴근 버튼 → 백그라운드 콜백(clockoutwidget://checkout)
                setOnClickPendingIntent(
                    R.id.btn_checkout,
                    HomeWidgetBackgroundIntent.getBroadcast(
                        context,
                        Uri.parse("clockoutwidget://checkout"),
                    ),
                )
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
