import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:home_widget/home_widget.dart';

import '../models/attendance_record.dart';
import '../utils/time_rules.dart';
import 'attendance_controller.dart';
import 'database_service.dart';
import 'settings_service.dart';

/// iOS App Group / 위젯 식별자. (iOS Xcode 설정의 App Group 과 동일해야 함)
const String appGroupId = 'group.com.isohyeon.clockoutReminder';

/// Android 위젯 Provider 클래스명, iOS 위젯 kind.
const String androidWidgetProvider = 'ClockoutWidgetProvider';
const String iOSWidgetName = 'ClockoutWidget';

/// 홈 화면 위젯과 데이터를 주고받는다.
class WidgetService {
  /// 앱 시작 시 1회 호출 — App Group 설정 + 버튼 콜백 등록.
  static Future<void> init() async {
    await HomeWidget.setAppGroupId(appGroupId);
    await HomeWidget.registerInteractivityCallback(interactiveCallback);
  }

  /// 현재 출퇴근 상태를 위젯에 반영한다.
  static Future<void> sync() async {
    await HomeWidget.setAppGroupId(appGroupId);

    final db = DatabaseService.instance;
    final settings = await SettingsService.instance.load();
    final today = await db.getByDate(DateTime.now());

    AttendanceRecord? checkIn;
    AttendanceRecord? checkOut;
    for (final r in today) {
      if (r.type == AttendanceType.checkIn) checkIn ??= r;
      if (r.type == AttendanceType.checkOut) checkOut ??= r;
    }

    final String status;
    if (checkOut != null) {
      status = '퇴근 완료 🎉';
    } else if (checkIn != null) {
      status = '근무 중';
    } else {
      status = '출근 전';
    }

    final String subtitle;
    if (checkOut != null) {
      subtitle = '퇴근 ${_fmt(checkOut.timestamp)} · 오늘도 수고하셨어요';
    } else if (checkIn != null) {
      final eta = TimeRules.computeClockOut(checkIn.timestamp, settings);
      subtitle = '출근 ${_fmt(checkIn.timestamp)} · 예상 퇴근 ${_fmt(eta)}';
    } else {
      subtitle = '출근 버튼을 눌러 시작하세요';
    }

    await HomeWidget.saveWidgetData<String>('status', status);
    await HomeWidget.saveWidgetData<String>('subtitle', subtitle);
    await HomeWidget.saveWidgetData<bool>('can_checkin', checkIn == null);
    await HomeWidget.saveWidgetData<bool>(
        'can_checkout', checkIn != null && checkOut == null);

    await HomeWidget.updateWidget(
      androidName: androidWidgetProvider,
      iOSName: iOSWidgetName,
    );
  }

  /// "오후 5:38" 형식 (백그라운드 isolate 에서도 동작하도록 intl 없이 직접 포맷).
  static String _fmt(DateTime t) {
    final isPm = t.hour >= 12;
    var h = t.hour % 12;
    if (h == 0) h = 12;
    final m = t.minute.toString().padLeft(2, '0');
    return '${isPm ? '오후' : '오전'} $h:$m';
  }
}

/// 위젯 버튼이 눌렸을 때 백그라운드에서 실행되는 콜백.
/// (앱이 꺼져 있어도 호출됨 — 최상위 함수 + vm:entry-point 필수)
@pragma('vm:entry-point')
Future<void> interactiveCallback(Uri? uri) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  await HomeWidget.setAppGroupId(appGroupId);

  switch (uri?.host) {
    case 'checkin':
      await AttendanceController.staticGuardedCheckIn(
        trigger: AttendanceTrigger.manual,
      );
      break;
    case 'checkout':
      await AttendanceController.staticGuardedCheckOut(
        trigger: AttendanceTrigger.manual,
      );
      break;
  }
  await WidgetService.sync();
}
