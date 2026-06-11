import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../models/attendance_record.dart';
import 'attendance_controller.dart';

/// 백그라운드(앱이 꺼진 상태)에서 알림 액션 탭을 처리하는 최상위 핸들러.
@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) async {
  if (response.actionId == NotificationService.actionConfirmCheckIn) {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    await AttendanceController.performCheckIn(
      trigger: AttendanceTrigger.geofenceEnter,
    );
  }
}

/// 로컬 푸시 알림을 담당한다.
///
/// - 도착 시 "출근하시겠습니까?" 알림 (액션 버튼)
/// - 계산된 퇴근시각 1회 예약 알림
/// - 즉시 알림
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();

  static const _channelId = 'clockout_channel';
  static const _channelName = '퇴근 알림';
  static const _channelDesc = '퇴근/출근 체크 리마인더 알림';

  static const instantNotificationId = 1001;
  static const clockOutNotificationId = 1002;
  static const arrivalNotificationId = 1003;

  static const actionConfirmCheckIn = 'confirm_checkin';
  static const _arrivalCategory = 'arrival_category';

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
          actions: [
            AndroidNotificationAction(actionConfirmCheckIn, '출근하기',
                showsUserInterface: true),
          ],
        ),
        iOS: DarwinNotificationDetails(categoryIdentifier: _arrivalCategory),
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

  /// 회사 도착 시 "출근하시겠습니까?" 알림(액션 버튼 포함).
  Future<void> showArrivalPrompt() async {
    await init();
    await _plugin.show(
      id: arrivalNotificationId,
      title: '회사에 도착했어요',
      body: '출근하시겠습니까? "출근하기"를 누르면 퇴근 알림이 설정됩니다.',
      notificationDetails: _arrivalDetails,
      payload: 'arrival',
    );
  }

  Future<void> cancelArrivalPrompt() async {
    await _plugin.cancel(id: arrivalNotificationId);
  }

  /// 계산된 퇴근시각([when])에 1회 푸시 예약.
  Future<void> scheduleClockOutAt(
    DateTime when, {
    String title = '퇴근 시간입니다 🕔',
    String body = '오늘 근무 끝! 퇴근 체크 잊지 마세요.',
  }) async {
    await init();
    await cancelClockOut();

    final scheduled = tz.TZDateTime.from(when, tz.local);
    // 이미 지난 시각이면 예약하지 않는다.
    if (scheduled.isBefore(tz.TZDateTime.now(tz.local))) return;

    try {
      await _plugin.zonedSchedule(
        id: clockOutNotificationId,
        title: title,
        body: body,
        scheduledDate: scheduled,
        notificationDetails: _basicDetails,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch (e) {
      debugPrint('퇴근 알림 예약 실패: $e');
    }
  }

  Future<void> cancelClockOut() async {
    await _plugin.cancel(id: clockOutNotificationId);
  }
}
