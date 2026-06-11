import 'package:flutter/foundation.dart';
import 'package:geofence_service/geofence_service.dart';

import '../models/app_settings.dart';
import 'attendance_controller.dart';

/// geofence_service 를 감싸 회사 반경 진입/이탈을 감지하고,
/// 그에 따라 근태 기록 저장 + 퇴근 알림을 트리거한다.
///
/// 백그라운드에서도 동작하도록 foreground 위치 서비스를 사용한다.
class GeofenceManager {
  GeofenceManager._();
  static final GeofenceManager instance = GeofenceManager._();

  static const _officeId = 'office';

  final _service = GeofenceService.instance.setup(
    interval: 5000, // 위치 체크 주기(ms)
    accuracy: 100, // 위치 정확도(m)
    loiteringDelayMs: 60000,
    statusChangeDelayMs: 10000, // 상태 변화 디바운스
    useActivityRecognition: false,
    allowMockLocations: false,
    printDevLog: false,
    geofenceRadiusSortType: GeofenceRadiusSortType.DESC,
  );

  bool _running = false;
  bool get isRunning => _running;

  /// 마지막으로 감지된 지오펜스 상태 (UI 표시용).
  final ValueNotifier<GeofenceStatus?> status =
      ValueNotifier<GeofenceStatus?>(null);

  /// 설정값에 맞춰 지오펜스 감시를 시작한다.
  Future<void> start(AppSettings settings) async {
    if (!settings.geofenceEnabled) {
      await stop();
      return;
    }

    final geofence = Geofence(
      id: _officeId,
      latitude: settings.officeLatitude,
      longitude: settings.officeLongitude,
      radius: [
        GeofenceRadius(id: 'office_radius', length: settings.radiusMeters),
      ],
    );

    _service.addGeofenceStatusChangeListener(_onStatusChanged);
    _service.addStreamErrorListener(_onError);

    try {
      await _service.start([geofence]);
      _running = true;
    } catch (e) {
      debugPrint('지오펜스 시작 실패: $e');
      _running = false;
    }
  }

  Future<void> stop() async {
    if (!_running) return;
    _service.removeGeofenceStatusChangeListener(_onStatusChanged);
    _service.removeStreamErrorListener(_onError);
    await _service.stop();
    _running = false;
  }

  /// 설정이 바뀌면 재시작한다.
  Future<void> restart(AppSettings settings) async {
    await stop();
    await start(settings);
  }

  Future<void> _onStatusChanged(
    Geofence geofence,
    GeofenceRadius geofenceRadius,
    GeofenceStatus geofenceStatus,
    Location location,
  ) async {
    status.value = geofenceStatus;

    final controller = AttendanceController.instance;
    switch (geofenceStatus) {
      case GeofenceStatus.ENTER:
        // 도착 → "출근하시겠습니까?" 확인 흐름.
        await controller.onArrival(
          latitude: location.latitude,
          longitude: location.longitude,
        );
        break;
      case GeofenceStatus.EXIT:
        // 자동 퇴근하지 않고 "퇴근하셨나요?" 확인 흐름(응답 없으면 5분마다 반복).
        await controller.onDeparture(
          latitude: location.latitude,
          longitude: location.longitude,
        );
        break;
      case GeofenceStatus.DWELL:
        break;
    }
  }

  void _onError(dynamic error) {
    debugPrint('지오펜스 오류: $error');
  }
}
