import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../models/attendance_record.dart';
import 'attendance_controller.dart';
import 'widget_service.dart';

/// 백그라운드(앱이 꺼진 상태)에서 알림 액션 탭을 처리하는 최상위 핸들러.
@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  await NotificationService.instance.init();

  switch (response.actionId) {
    case NotificationService.actionConfirmCheckIn:
      await AttendanceController.performCheckIn(
        trigger: AttendanceTrigger.geofenceEnter,
      );
      break;
    case NotificationService.actionConfirmCheckOut:
      await AttendanceController.performCheckOut(
        trigger: AttendanceTrigger.manual,
      );
      break;
    case NotificationService.actionOvertime:
      // 연장근무 → 리마인더 스누즈(일정 시간 후 재개)
      await NotificationService.instance.snoozeReminders();
      break;
    case NotificationService.actionSkipCheckIn:
      // 출근 안하기 → 오늘 하루 도착 알림 종료
      await AttendanceController.markArrivalDismissedToday();
      await NotificationService.instance.cancelArrivalReminders();
      break;
  }
  await WidgetService.sync();
}

/// 로컬 푸시 알림을 담당한다.
///
/// - 도착 시 "출근하시겠습니까?" 알림
/// - 이탈/퇴근시각 도달 시 "퇴근하셨나요?" 알림 (응답할 때까지 5분 간격 반복)
/// - [퇴근하기] / [연장근무] 액션
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();

  static const _channelId = 'clockout_channel';
  static const _channelName = '퇴근 알림';
  static const _channelDesc = '퇴근/출근 체크 리마인더 알림';

  static const instantNotificationId = 1001;

  // 퇴근 리마인더 시리즈 (5분 간격 반복) ID 범위: base ~ base+count+1
  static const _reminderBaseId = 2000;
  // 출근(도착) 리마인더 시리즈 ID 범위: base ~ base+count+1
  static const _arrivalBaseId = 2100;
  static const _reminderCount = 24; // 5분 × 24 = 약 2시간 동안 반복
  static const _reminderIntervalMin = 5;

  static const actionConfirmCheckIn = 'confirm_checkin';
  static const actionSkipCheckIn = 'skip_checkin';
  static const actionConfirmCheckOut = 'confirm_checkout';
  static const actionOvertime = 'overtime';
  static const _arrivalCategory = 'arrival_category';
  static const _reminderCategory = 'clockout_reminder_category';

  /// 포그라운드에서 알림(액션) 탭을 받았을 때 호출되는 콜백. main 에서 연결한다.
  void Function(NotificationResponse response)? onResponse;

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    tz.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation('Asia/Seoul'));
    } catch (_) {}

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    final iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
      notificationCategories: [
        DarwinNotificationCategory(
          _arrivalCategory,
          actions: [
            DarwinNotificationAction.plain(actionConfirmCheckIn, '출근하기'),
            DarwinNotificationAction.plain(actionSkipCheckIn, '출근 안하기'),
          ],
        ),
        DarwinNotificationCategory(
          _reminderCategory,
          actions: [
            DarwinNotificationAction.plain(actionConfirmCheckOut, '퇴근하기'),
            DarwinNotificationAction.plain(actionOvertime, '연장근무'),
          ],
        ),
      ],
    );

    await _plugin.initialize(
      settings: InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: (response) => onResponse?.call(response),
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );

    final androidImpl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDesc,
        importance: Importance.high,
      ),
    );

    _initialized = true;
  }

  Future<bool> requestPermission() async {
    await init();
    final iosImpl = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    final iosGranted = await iosImpl?.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );

    final androidImpl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final androidGranted = await androidImpl?.requestNotificationsPermission();

    return iosGranted ?? androidGranted ?? true;
  }

  NotificationDetails get _basicDetails => const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      );

  NotificationDetails get _arrivalDetails => const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          importance: Importance.high,
          priority: Priority.high,
          category: AndroidNotificationCategory.reminder,
          actions: [
            AndroidNotificationAction(actionConfirmCheckIn, '출근하기',
                showsUserInterface: true),
            AndroidNotificationAction(actionSkipCheckIn, '출근 안하기',
                showsUserInterface: true),
          ],
        ),
        iOS: DarwinNotificationDetails(categoryIdentifier: _arrivalCategory),
      );

  /// 퇴근 리마인더용 상세 ([퇴근하기] / [연장근무] 액션 포함).
  NotificationDetails get _reminderDetails => const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          importance: Importance.high,
          priority: Priority.high,
          category: AndroidNotificationCategory.reminder,
          actions: [
            AndroidNotificationAction(actionConfirmCheckOut, '퇴근하기',
                showsUserInterface: true),
            AndroidNotificationAction(actionOvertime, '연장근무',
                showsUserInterface: true),
          ],
        ),
        iOS: DarwinNotificationDetails(categoryIdentifier: _reminderCategory),
      );

  /// 즉시 알림.
  Future<void> showInstant({
    required String title,
    required String body,
  }) async {
    await init();
    await _plugin.show(
      id: instantNotificationId,
      title: title,
      body: body,
      notificationDetails: _basicDetails,
    );
  }

  /// 회사 도착 시 "출근하시겠습니까?" 리마인더 시작.
  /// 즉시 1회 + 5분 간격 반복(응답할 때까지). [출근하기]/[출근 안하기] 액션 포함.
  Future<void> startArrivalReminders() async {
    await init();
    await cancelArrivalReminders();

    const title = '회사에 도착했어요';
    const body = '출근하시겠습니까? "출근하기"를 누르면 퇴근 알림이 설정됩니다.';
    final now = tz.TZDateTime.now(tz.local);

    // 즉시 1회
    await _plugin.show(
      id: _arrivalBaseId,
      title: title,
      body: body,
      notificationDetails: _arrivalDetails,
      payload: 'arrival',
    );

    // 5분 간격 반복 예약
    for (int i = 0; i < _reminderCount; i++) {
      final when = now.add(Duration(minutes: (i + 1) * _reminderIntervalMin));
      try {
        await _plugin.zonedSchedule(
          id: _arrivalBaseId + 1 + i,
          title: title,
          body: body,
          scheduledDate: when,
          notificationDetails: _arrivalDetails,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: 'arrival',
        );
      } catch (e) {
        debugPrint('출근 리마인더 예약 실패: $e');
      }
    }
  }

  /// 출근(도착) 리마인더 시리즈를 모두 취소한다.
  Future<void> cancelArrivalReminders() async {
    for (int i = 0; i <= _reminderCount + 1; i++) {
      await _plugin.cancel(id: _arrivalBaseId + i);
    }
  }

  /// 퇴근 리마인더 시리즈를 시작한다.
  ///
  /// [firstAt] 부터 5분 간격으로 반복 알림을 예약한다.
  /// [showFirstNow] 가 true 면 즉시 한 번 먼저 띄운다(반경 이탈 시).
  /// 응답(퇴근/연장근무)하면 [cancelClockOutReminders] 로 전부 취소된다.
  Future<void> scheduleClockOutReminders({
    required DateTime firstAt,
    bool showFirstNow = false,
    String title = '퇴근 시간입니다 🕔',
    String body = '퇴근하셨나요? 더 근무하시면 "연장근무"를 눌러주세요.',
  }) async {
    await init();
    await cancelClockOutReminders();

    final now = tz.TZDateTime.now(tz.local);

    if (showFirstNow) {
      await _plugin.show(
        id: _reminderBaseId,
        title: title,
        body: body,
        notificationDetails: _reminderDetails,
        payload: 'clockout',
      );
    }

    for (int i = 0; i < _reminderCount; i++) {
      final when = tz.TZDateTime.from(firstAt, tz.local)
          .add(Duration(minutes: i * _reminderIntervalMin));
      if (!when.isAfter(now)) continue; // 이미 지난 시각은 건너뜀
      try {
        await _plugin.zonedSchedule(
          id: _reminderBaseId + 1 + i,
          title: title,
          body: body,
          scheduledDate: when,
          notificationDetails: _reminderDetails,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: 'clockout',
        );
      } catch (e) {
        debugPrint('퇴근 리마인더 예약 실패: $e');
      }
    }
  }

  /// 퇴근 리마인더 시리즈를 모두 취소한다.
  Future<void> cancelClockOutReminders() async {
    for (int i = 0; i <= _reminderCount + 1; i++) {
      await _plugin.cancel(id: _reminderBaseId + i);
    }
  }

  /// 연장근무/아직 근무중 → 리마인더를 [snoozeMinutes] 후 다시 5분 간격으로 재개.
  Future<void> snoozeReminders({int snoozeMinutes = 60}) async {
    final resume = DateTime.now().add(Duration(minutes: snoozeMinutes));
    await scheduleClockOutReminders(
      firstAt: resume,
      title: '아직 근무 중이신가요?',
      body: '퇴근하셨다면 "퇴근하기", 계속 근무하시면 "연장근무"를 눌러주세요.',
    );
  }
}
