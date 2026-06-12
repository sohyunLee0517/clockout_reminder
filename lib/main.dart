import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';

import 'config/kakao_config.dart';
import 'models/app_settings.dart';
import 'models/attendance_record.dart';
import 'screens/home_screen.dart';
import 'services/attendance_controller.dart';
import 'services/geofence_manager.dart';
import 'services/notification_service.dart';
import 'services/widget_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 한국어 날짜 포맷 데이터 로드.
  await initializeDateFormatting('ko');

  // 카카오 SDK 초기화(네이티브 앱 키가 설정된 경우에만).
  if (isKakaoConfigured) {
    KakaoSdk.init(nativeAppKey: kakaoNativeAppKey);
  }

  // 알림 시스템 초기화 + 포그라운드 알림 응답 핸들러 연결.
  await NotificationService.instance.init();
  NotificationService.instance.onResponse = (response) async {
    final controller = AttendanceController.instance;
    switch (response.actionId) {
      case NotificationService.actionConfirmCheckIn:
        final r = await controller.guardedCheckIn(
          trigger: AttendanceTrigger.geofenceEnter,
        );
        await _notifyIfBlocked(r, isCheckIn: true);
        break;
      case NotificationService.actionIgnoreArrival:
        await controller.ignoreArrival();
        break;
      case NotificationService.actionConfirmCheckOut:
        final r = await controller.guardedCheckOut(
          trigger: AttendanceTrigger.manual,
        );
        await _notifyIfBlocked(r, isCheckIn: false);
        break;
      case NotificationService.actionOvertime:
        await controller.snooze();
        break;
      case NotificationService.actionIgnoreDeparture:
        await controller.ignoreDeparture();
        break;
    }
    await WidgetService.sync();
  };

  // 홈 위젯 초기화(App Group + 버튼 콜백 등록).
  await WidgetService.init();

  // 저장된 설정을 컨트롤러에 로드.
  final controller = AttendanceController.instance;
  await controller.loadSettings();
  final settings = controller.settings;

  // 이미 구성되어 있으면 위치 감시를 자동 시작.
  if (settings.configured && settings.geofenceEnabled) {
    await GeofenceManager.instance.start(settings);
  }

  // 위젯에 현재 상태 반영.
  await WidgetService.sync();

  runApp(ClockOutApp(initialSettings: settings));
}

/// 알림 액션으로 출퇴근이 반경 밖이라 차단됐을 때 안내 알림.
Future<void> _notifyIfBlocked(AttendanceResult r,
    {required bool isCheckIn}) async {
  if (r == AttendanceResult.outside || r == AttendanceResult.unknown) {
    await NotificationService.instance.showInstant(
      title: isCheckIn ? '출근하지 못했어요' : '퇴근하지 못했어요',
      body: r == AttendanceResult.outside
          ? '회사 반경 안에서만 ${isCheckIn ? '출근' : '퇴근'}할 수 있어요.'
          : '현재 위치를 확인할 수 없어요. 위치 권한·GPS를 확인해 주세요.',
    );
  }
}

class ClockOutApp extends StatelessWidget {
  final AppSettings initialSettings;
  const ClockOutApp({super.key, required this.initialSettings});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '퇴근 알림',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ko'),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('ko'), Locale('en')],
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3A6EA5),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3A6EA5),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: HomeScreen(initialSettings: initialSettings),
    );
  }
}
