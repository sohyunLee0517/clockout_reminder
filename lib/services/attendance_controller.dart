import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

/// 반경 이탈 후 퇴근 확인 대기 상태 (UI 다이얼로그 표시용).
class PendingDeparture {
  final double? latitude;
  final double? longitude;
  const PendingDeparture({this.latitude, this.longitude});
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

  /// 이탈 후 퇴근 확인 대기 — null 이 아니면 "퇴근하셨나요?" 다이얼로그를 띄운다.
  final ValueNotifier<PendingDeparture?> pendingDeparture =
      ValueNotifier<PendingDeparture?>(null);

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
      await NotificationService.instance.scheduleClockOutReminders(firstAt: out);
    } else if (!s.clockOutAlarmEnabled) {
      await NotificationService.instance.cancelClockOutReminders();
      scheduledClockOut = null;
    }
    changed.value++;
  }

  /// 회사 반경 진입 시 호출. 확인 옵션에 따라 다이얼로그/알림 또는 자동 출근.
  /// 출근을 누르지 않으면 5분 간격으로 반복 알림(오늘 "출근 안하기" 시 종료).
  Future<void> onArrival({double? latitude, double? longitude}) async {
    if (await isCheckedInToday()) return;
    if (await isArrivalDismissedToday()) return; // 오늘 "출근 안하기" 누름
    if (settings.confirmOnArrival) {
      await NotificationService.instance.startArrivalReminders();
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

  // ── "오늘 출근 안하기" 플래그 (날짜 기준, 다음 날 자동 해제) ──
  static const _kArrivalDismissed = 'arrival_dismissed_date';

  static String _todayKey() {
    final n = DateTime.now();
    return '${n.year}-${n.month}-${n.day}';
  }

  static Future<bool> isArrivalDismissedToday() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kArrivalDismissed) == _todayKey();
  }

  static Future<void> markArrivalDismissedToday() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kArrivalDismissed, _todayKey());
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
    await NotificationService.instance.cancelArrivalReminders();
    changed.value++;
  }

  /// 도착 확인 대기 해제(이미 출근한 경우 등). 오늘 알림은 종료하지 않음.
  Future<void> dismissArrival() async {
    pendingArrival.value = null;
    await NotificationService.instance.cancelArrivalReminders();
  }

  /// "출근 안하기" → 오늘 하루 도착 알림 종료.
  Future<void> skipArrivalToday() async {
    pendingArrival.value = null;
    await markArrivalDismissedToday();
    await NotificationService.instance.cancelArrivalReminders();
  }

  /// 출근 취소: 오늘 출근(과 퇴근) 기록 삭제 + 모든 리마인더 취소 → "출근 전".
  Future<void> cancelCheckIn() async {
    final db = DatabaseService.instance;
    final today = await db.getByDate(DateTime.now());
    for (final r in today) {
      if ((r.type == AttendanceType.checkIn ||
              r.type == AttendanceType.checkOut) &&
          r.id != null) {
        await db.delete(r.id!);
      }
    }
    scheduledClockOut = null;
    pendingArrival.value = null;
    pendingDeparture.value = null;
    await NotificationService.instance.cancelClockOutReminders();
    await NotificationService.instance.cancelArrivalReminders();
    changed.value++;
  }

  /// 퇴근 취소: 오늘 퇴근 기록만 삭제 → 다시 "근무 중", 퇴근 리마인더 재설정.
  Future<void> cancelCheckOut() async {
    final db = DatabaseService.instance;
    final today = await db.getByDate(DateTime.now());
    AttendanceRecord? checkIn;
    for (final r in today) {
      if (r.type == AttendanceType.checkOut && r.id != null) {
        await db.delete(r.id!);
      }
      if (r.type == AttendanceType.checkIn) checkIn = r;
    }
    pendingDeparture.value = null;
    if (checkIn != null && settings.clockOutAlarmEnabled) {
      final out = TimeRules.computeClockOut(checkIn.timestamp, settings);
      scheduledClockOut = out;
      await NotificationService.instance.scheduleClockOutReminders(firstAt: out);
    }
    changed.value++;
  }

  /// 회사 반경 이탈 시 호출. 자동 퇴근하지 않고 "퇴근하셨나요?" 를 물어본다.
  /// 응답이 없으면 5분 간격으로 계속 알림(반경 이탈 즉시 1회 + 시리즈).
  Future<void> onDeparture({double? latitude, double? longitude}) async {
    // 출근하지 않았거나 이미 퇴근했으면 물어볼 필요 없음.
    if (!await isCheckedInToday()) return;
    if (await DatabaseService.instance.hasCheckedOutToday()) return;

    await NotificationService.instance.scheduleClockOutReminders(
      firstAt: DateTime.now().add(const Duration(minutes: 5)),
      showFirstNow: true,
      title: '회사를 벗어났어요',
      body: '퇴근하셨나요? "퇴근하기"를 누르면 기록됩니다.',
    );
    pendingDeparture.value =
        PendingDeparture(latitude: latitude, longitude: longitude);
  }

  /// "아직 근무중" / "연장근무" → 리마인더 스누즈(일정 시간 후 재개).
  Future<void> snooze() async {
    pendingDeparture.value = null;
    await NotificationService.instance.snoozeReminders();
  }

  /// 퇴근 처리: 기록 저장 + 모든 퇴근 리마인더 취소.
  Future<void> checkOut({
    required AttendanceTrigger trigger,
    double? latitude,
    double? longitude,
  }) async {
    await performCheckOut(
      trigger: trigger,
      latitude: latitude,
      longitude: longitude,
    );
    scheduledClockOut = null;
    pendingDeparture.value = null;
    changed.value++;
  }

  /// 포그라운드/백그라운드(위젯 버튼) 공용 순수 퇴근 로직.
  static Future<void> performCheckOut({
    required AttendanceTrigger trigger,
    double? latitude,
    double? longitude,
  }) async {
    final db = DatabaseService.instance;
    final today = await db.getByDate(DateTime.now());
    final hasCheckIn = today.any((r) => r.type == AttendanceType.checkIn);
    final hasCheckOut = today.any((r) => r.type == AttendanceType.checkOut);
    if (!hasCheckIn || hasCheckOut) return; // 출근 전이거나 이미 퇴근함
    await db.insert(AttendanceRecord(
      type: AttendanceType.checkOut,
      trigger: trigger,
      timestamp: DateTime.now(),
      latitude: latitude,
      longitude: longitude,
    ));
    await NotificationService.instance.cancelClockOutReminders();
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
    // 퇴근 예정시각부터 5분 간격으로 "퇴근하셨나요?" 반복 알림.
    await NotificationService.instance.scheduleClockOutReminders(firstAt: out);
    return out;
  }
}
