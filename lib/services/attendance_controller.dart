import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_settings.dart';
import '../models/attendance_record.dart';
import '../utils/time_rules.dart';
import 'database_service.dart';
import 'kakao_service.dart';
import 'location_gate.dart';
import 'notification_service.dart';
import 'settings_service.dart';
import 'slack_service.dart';

/// 출퇴근 시도 결과.
enum AttendanceResult {
  ok, // 정상 처리
  outside, // 회사 반경 밖이라 차단
  unknown, // 위치를 확인할 수 없어 차단
  noop, // 이미 처리됨(중복) 등
}

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

    await _recordArrival(); // 도착시각 기록(출근 미입력 판단 기준)

    if (settings.confirmOnArrival) {
      await NotificationService.instance.startArrivalReminders();
      pendingArrival.value =
          PendingArrival(latitude: latitude, longitude: longitude);
      // 5분 뒤에도 미체크면 "출근 미입력" 채널 전송 (앱/지오펜스 살아있을 때).
      Timer(const Duration(minutes: 5), checkArrivalMissing);
    } else {
      await confirmCheckIn(
        trigger: AttendanceTrigger.geofenceEnter,
        latitude: latitude,
        longitude: longitude,
      );
    }
  }

  // ── 출근 미입력: 도착 후 5분 경과해도 미체크 ──
  static const _kArrivalDate = 'arrival_date';
  static const _kArrivalTime = 'arrival_time_millis';
  static const _kArrivalMissingSent = 'arrival_missing_sent';

  /// 오늘 첫 도착시각을 기록한다.
  Future<void> _recordArrival() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_kArrivalDate) != _todayKey()) {
      await prefs.setString(_kArrivalDate, _todayKey());
      await prefs.setInt(
          _kArrivalTime, DateTime.now().millisecondsSinceEpoch);
      await prefs.remove(_kArrivalMissingSent);
    }
  }

  /// 출근 안 찍고 반경을 벗어나면 출근 미입력 추적 취소(이벤트 아님).
  Future<void> clearArrivalTracking() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kArrivalDate);
    await prefs.remove(_kArrivalTime);
  }

  /// 도착 후 5분 경과 + 미체크면 "출근 미입력" 채널 전송(중복 방지).
  Future<void> checkArrivalMissing() async {
    if (await isCheckedInToday()) return;
    if (await isArrivalDismissedToday()) return; // 의도적 미출근은 제외
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_kArrivalDate) != _todayKey()) return;
    if (prefs.getString(_kArrivalMissingSent) == _todayKey()) return;
    final at = prefs.getInt(_kArrivalTime);
    if (at == null) return;
    final arrived = DateTime.fromMillisecondsSinceEpoch(at);
    if (DateTime.now().difference(arrived) < const Duration(minutes: 5)) {
      return;
    }
    await prefs.setString(_kArrivalMissingSent, _todayKey());
    await _notifyChannels(
      '🟡 출근 미입력 — 회사 도착 후 출근 체크를 안 했어요 (${_fmtTime(DateTime.now())})',
      isMissing: true,
    );
  }

  // ── 퇴근 미입력: 이탈 후 5분 경과해도 미응답 ──
  static const _kDepartDate = 'depart_date';
  static const _kDepartTime = 'depart_time_millis';
  static const _kDepartMissingSent = 'depart_missing_sent';
  static const _kDepartResponded = 'depart_responded';

  /// 오늘 첫 이탈 시각을 기록한다.
  Future<void> _recordDeparture() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_kDepartDate) != _todayKey()) {
      await prefs.setString(_kDepartDate, _todayKey());
      await prefs.setInt(
          _kDepartTime, DateTime.now().millisecondsSinceEpoch);
      await prefs.remove(_kDepartMissingSent);
      await prefs.remove(_kDepartResponded);
    }
  }

  /// 이탈 푸시에 응답(퇴근/연장근무)했음을 기록 → 미입력 채널 전송 안 함.
  Future<void> _markDepartureResponded() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDepartResponded, _todayKey());
  }

  /// 이탈 후 5분 경과 + 미응답(미퇴근)이면 "퇴근 미입력" 채널 전송(중복 방지).
  Future<void> checkDepartureMissing() async {
    if (!await isCheckedInToday()) return; // 출근 안 했으면 대상 아님
    if (await DatabaseService.instance.hasCheckedOutToday()) return; // 퇴근함=응답
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_kDepartResponded) == _todayKey()) return; // 연장근무 등 응답
    if (prefs.getString(_kDepartDate) != _todayKey()) return;
    if (prefs.getString(_kDepartMissingSent) == _todayKey()) return;
    final at = prefs.getInt(_kDepartTime);
    if (at == null) return;
    final left = DateTime.fromMillisecondsSinceEpoch(at);
    if (DateTime.now().difference(left) < const Duration(minutes: 5)) return;
    await prefs.setString(_kDepartMissingSent, _todayKey());
    await _notifyChannels(
      '⚠️ 퇴근 미입력 — 회사를 벗어났는데 퇴근 체크를 안 했어요 (${_fmtTime(DateTime.now())})',
      isMissing: true,
    );
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

  // ── 위치 게이트가 적용된 출퇴근 (회사 반경 안에서만 가능) ──

  /// 반경 검사 후 출근. 결과에 따라 UI/알림에서 피드백할 수 있다.
  Future<AttendanceResult> guardedCheckIn({
    required AttendanceTrigger trigger,
    double? latitude,
    double? longitude,
  }) async {
    if (await isCheckedInToday()) return AttendanceResult.noop;
    final inside = await LocationGate.isInsideOffice(settings);
    if (inside == false) return AttendanceResult.outside;
    if (inside == null) return AttendanceResult.unknown;
    await confirmCheckIn(
        trigger: trigger, latitude: latitude, longitude: longitude);
    return AttendanceResult.ok;
  }

  /// 반경 검사 후 퇴근.
  Future<AttendanceResult> guardedCheckOut({
    required AttendanceTrigger trigger,
    double? latitude,
    double? longitude,
  }) async {
    final db = DatabaseService.instance;
    if (!await isCheckedInToday()) return AttendanceResult.noop;
    if (await db.hasCheckedOutToday()) return AttendanceResult.noop;
    final inside = await LocationGate.isInsideOffice(settings);
    if (inside == false) return AttendanceResult.outside;
    if (inside == null) return AttendanceResult.unknown;
    await checkOut(
        trigger: trigger, latitude: latitude, longitude: longitude);
    return AttendanceResult.ok;
  }

  /// 백그라운드(위젯/알림 액션)용 정적 출근 — 차단 시 알림으로 안내.
  static Future<void> staticGuardedCheckIn({
    required AttendanceTrigger trigger,
    double? latitude,
    double? longitude,
  }) async {
    final s = await SettingsService.instance.load();
    final inside = await LocationGate.isInsideOffice(s);
    if (inside != true) {
      await NotificationService.instance.showInstant(
        title: '출근하지 못했어요',
        body: inside == false
            ? '회사 반경 안에서만 출근할 수 있어요.'
            : '현재 위치를 확인할 수 없어요. 위치 권한·GPS를 확인해 주세요.',
      );
      return;
    }
    await performCheckIn(
        trigger: trigger, latitude: latitude, longitude: longitude);
  }

  /// 백그라운드(위젯/알림 액션)용 정적 퇴근 — 차단 시 알림으로 안내.
  static Future<void> staticGuardedCheckOut({
    required AttendanceTrigger trigger,
    double? latitude,
    double? longitude,
  }) async {
    final s = await SettingsService.instance.load();
    final inside = await LocationGate.isInsideOffice(s);
    if (inside != true) {
      await NotificationService.instance.showInstant(
        title: '퇴근하지 못했어요',
        body: inside == false
            ? '회사 반경 안에서만 퇴근할 수 있어요.'
            : '현재 위치를 확인할 수 없어요. 위치 권한·GPS를 확인해 주세요.',
      );
      return;
    }
    await performCheckOut(
        trigger: trigger, latitude: latitude, longitude: longitude);
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
    await _notifyCheck(checkIn: true);
  }

  /// 외부 채널(카카오/슬랙)로 이벤트 알림을 보낸다.
  /// [isMissing] 이면 "미입력" 카테고리, 아니면 "출퇴근 체크" 카테고리로 분기.
  Future<void> _notifyChannels(String message, {required bool isMissing}) async {
    // 카카오
    final kakaoOn = isMissing ? settings.kakaoOnMissing : settings.kakaoOnCheck;
    if (kakaoOn) {
      await KakaoService.sendToMe(message);
    }
    // 슬랙
    final slackOn = isMissing ? settings.slackOnMissing : settings.slackOnCheck;
    if (slackOn && settings.slackWebhookUrl.trim().isNotEmpty) {
      await SlackService.send(settings.slackWebhookUrl, message);
    }
  }

  Future<void> _notifyCheck({required bool checkIn}) async {
    final t = _fmtTime(DateTime.now());
    final String msg;
    if (checkIn) {
      final eta = scheduledClockOut != null
          ? ' · 예상 퇴근 ${_fmtTime(scheduledClockOut!)}'
          : '';
      msg = '🟢 출근 체크 — $t$eta';
    } else {
      msg = '🔴 퇴근 체크 — $t · 오늘도 수고하셨어요!';
    }
    await _notifyChannels(msg, isMissing: false);
  }

  static String _fmtTime(DateTime t) {
    final pm = t.hour >= 12;
    var h = t.hour % 12;
    if (h == 0) h = 12;
    return '${pm ? '오후' : '오전'} $h:${t.minute.toString().padLeft(2, '0')}';
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

    await _recordDeparture(); // 이탈 시각 기록(퇴근 미입력 판단 기준)

    await NotificationService.instance.scheduleClockOutReminders(
      firstAt: DateTime.now().add(const Duration(minutes: 5)),
      showFirstNow: true,
      title: '회사를 벗어났어요',
      body: '퇴근 체크를 안 하셨어요. 퇴근은 회사 반경 안에서 찍어주세요.',
    );
    pendingDeparture.value =
        PendingDeparture(latitude: latitude, longitude: longitude);

    // 5분 뒤에도 미응답이면 "퇴근 미입력" 채널 전송(앱/지오펜스 살아있을 때).
    Timer(const Duration(minutes: 5), checkDepartureMissing);
  }

  /// "아직 근무중" / "연장근무" → 리마인더 스누즈(일정 시간 후 재개).
  /// [minutes] 미지정 시 설정값(overtimeSnoozeMinutes)을 사용.
  Future<void> snooze({int? minutes}) async {
    pendingDeparture.value = null;
    await _markDepartureResponded(); // 응답함 → 퇴근 미입력 채널 전송 안 함
    await NotificationService.instance.snoozeReminders(
      snoozeMinutes: minutes ?? settings.overtimeSnoozeMinutes,
    );
  }

  /// 백그라운드(알림 액션)용 정적 스누즈 — 설정값을 로드해 사용.
  static Future<void> performSnooze() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDepartResponded, _todayKey()); // 응답함
    final s = await SettingsService.instance.load();
    await NotificationService.instance
        .snoozeReminders(snoozeMinutes: s.overtimeSnoozeMinutes);
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
    await _notifyCheck(checkIn: false);
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
