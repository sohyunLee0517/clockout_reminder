import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import 'notification_service.dart';

/// 위치·알림 권한 요청을 한곳에서 처리한다.
class PermissionService {
  PermissionService._();
  static final PermissionService instance = PermissionService._();

  /// 위치 권한 결과.
  Future<LocationPermissionResult> ensureLocationPermission() async {
    // 위치 서비스(GPS) 자체가 켜져 있는지.
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return LocationPermissionResult.serviceDisabled;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      return LocationPermissionResult.denied;
    }
    if (permission == LocationPermission.deniedForever) {
      return LocationPermissionResult.deniedForever;
    }

    return LocationPermissionResult.granted;
  }

  /// 백그라운드(항상 허용) 위치 권한. 지오펜스가 백그라운드에서 동작하려면 필요.
  Future<bool> ensureBackgroundLocation() async {
    final status = await Permission.locationAlways.request();
    return status.isGranted;
  }

  /// 알림 권한.
  Future<bool> ensureNotificationPermission() async {
    return NotificationService.instance.requestPermission();
  }

  Future<void> openSettings() => openAppSettings();
}

enum LocationPermissionResult {
  granted,
  denied,
  deniedForever,
  serviceDisabled;

  String get message {
    switch (this) {
      case LocationPermissionResult.granted:
        return '위치 권한이 허용되었습니다.';
      case LocationPermissionResult.denied:
        return '위치 권한이 거부되었습니다. 다시 시도해 주세요.';
      case LocationPermissionResult.deniedForever:
        return '위치 권한이 영구 거부되었습니다. 설정에서 직접 허용해 주세요.';
      case LocationPermissionResult.serviceDisabled:
        return '위치 서비스(GPS)가 꺼져 있습니다. 켜고 다시 시도해 주세요.';
    }
  }

  bool get isGranted => this == LocationPermissionResult.granted;
}
