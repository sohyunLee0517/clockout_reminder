import 'package:flutter/foundation.dart';

import '../models/app_settings.dart';
import '../models/attendance_record.dart';
import '../utils/time_rules.dart';
import 'database_service.dart';
import 'notification_service.dart';
import 'settings_service.dart';

/// 도착 후 출근 확인 대기 상태 (UI 다이얼로그 표시용).
class PendingArrival {
  final double? latitude;
  final double? longitude;
  const PendingArrival({this.latitude, this.longitude});
}

/// 출근/퇴근 흐름과 퇴근시각 계산·예약을 한곳에서 관리한다.
class AttendanceController {
  AttendanceController._();
  static final AttendanceController instance = AttendanceController._();

  AppSettings settings = AppSettings.defaults();

  /// 기록이 바뀔 때마다 증가 (화면 새로고침 트리거).
  final ValueNotifier<int> changed = ValueNotifier<int>(0);

  /// 도착 확인 대기 — null 이 아니면 UI 에서 "출근하시겠습니까?" 다이얼로그를 띄운다.
  final ValueNotifier<PendingArrival?> pendingArrival =
      ValueNotifier<PendingArrival?>(null);

  /// 오늘 계산된 퇴근 예정시각 (없으면 null).
  DateTime? scheduledClockOut;

  Future<void> loadSettings() async {
    settings = await SettingsService.instance.load();
  }

  /// 설정 변경 저장 + 오늘 출근 상태면 퇴근시각 재계산/재예약.
  Future<void> updateSettings(AppSettings s) async {
    settings = s;
    await SettingsService.instance.save(s);

    final checkIn = await _todayCheckIn();
    final checkedOut = await DatabaseService.instance.hasCheckedOutToday();
    if (checkIn != null && !checkedOut && s.clockOutAlarmEnabled) {
      final out = TimeRules.computeClockOut(checkIn.timestamp, s);
      scheduledClockOut = out;
      await NotificationService.instance.scheduleClockOutAt(out);
    } else if (!s.clockOutAlarmEnabled) {
      await NotificationService.instance.cancelClockOut();
      scheduledClockOut = null;
    }
    changed.value++;
  }

  /// 회사 반경 진입 시 호출. 확인 옵션에 따라 다이얼로그/알림 또는 자동 출근.
  Future<void> onArrival({double? latitude, double? longitude}) async {
    if (await isCheckedInToday()) return;
    if (settings.confirmOnArrival) {
      await NotificationService.instance.showArrivalPrompt();
      pendingArrival.value =
          PendingArrival(latitude: latitude, longitude: longitude);
    } else {
      await confirmCheckIn(
        trigger: AttendanceTrigger.geofenceEnter,
        latitude: latitude,
        longitude: longitude,
      );
    }
  }

  Future<bool> isCheckedInToday() async {
    return (await _todayCheckIn()) != null;
  }

  Future<AttendanceRecord?> _todayCheckIn() async {
    final today = await DatabaseService.instance.getByDate(DateTime.now());
    for (final r in today) {
      if (r.type == AttendanceType.checkIn) return r;
    }
    return null;
  }

  /// 출근 확정: 기록 저장 + 퇴근시각 계산·예약.
  Future<void> confirmCheckIn({
    required AttendanceTrigger trigger,
    double? latitude,
    double? longitude,
  }) async {
    final out = await performCheckIn(
      trigger: trigger,
      latitude: latitude,
      longitude: longitude,
    );
    scheduledClockOut = out;
    pendingArrival.value = null;
    await NotificationService.instance.cancelArrivalPrompt();
    changed.value++;
  }

  /// 도착 확인 거절 (오늘은 출근 처리 안 함).
  Future<void> dismissArrival() async {
    pendingArrival.value = null;
    await NotificationService.instance.cancelArrivalPrompt();
  }

  /// 퇴근 처리: 기록 저장 + 예약된 퇴근 알림 취소.
  Future<void> checkOut({
    required AttendanceTrigger trigger,
    double? latitude,
    double? longitude,
  }) async {
    final db = DatabaseService.instance;
    if (await db.hasCheckedOutToday()) return;
    await db.insert(AttendanceRecord(
      type: AttendanceType.checkOut,
      trigger: trigger,
      timestamp: DateTime.now(),
      latitude: latitude,
      longitude: longitude,
    ));
    await NotificationService.instance.cancelClockOut();
    scheduledClockOut = null;
    changed.value++;
  }

  /// 포그라운드/백그라운드 공용 순수 로직.
  /// 출근 기록을 남기고 (없을 때만) 퇴근시각을 계산해 예약한다.
  /// 반환값: 예약된 퇴근 예정시각 (알림 비활성 시 null).
  static Future<DateTime?> performCheckIn({
    required AttendanceTrigger trigger,
    double? latitude,
    double? longitude,
  }) async {
    final db = DatabaseService.instance;
    final settings = await SettingsService.instance.load();
    final today = await db.getByDate(DateTime.now());

    AttendanceRecord? existing;
    for (final r in today) {
      if (r.type == AttendanceType.checkIn) {
        existing = r;
        break;
      }
    }

    final DateTime checkInTime;
    if (existing != null) {
      checkInTime = existing.timestamp;
    } else {
      final now = DateTime.now();
      await db.insert(AttendanceRecord(
        type: AttendanceType.checkIn,
        trigger: trigger,
        timestamp: now,
        latitude: latitude,
        longitude: longitude,
      ));
      checkInTime = now;
    }

    if (!settings.clockOutAlarmEnabled) return null;
    final out = TimeRules.computeClockOut(checkInTime, settings);
    await NotificationService.instance.scheduleClockOutAt(out);
    return out;
  }
}
