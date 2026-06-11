import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';

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

  // 알림 시스템 초기화 + 포그라운드 알림 응답 핸들러 연결.
  await NotificationService.instance.init();
  NotificationService.instance.onResponse = (response) async {
    if (response.actionId == NotificationService.actionConfirmCheckIn) {
      await AttendanceController.instance.confirmCheckIn(
        trigger: AttendanceTrigger.geofenceEnter,
      );
    }
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
