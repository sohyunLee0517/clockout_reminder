import 'package:geofence_service/geofence_service.dart' show GeofenceStatus;
import 'package:geolocator/geolocator.dart';

import '../models/app_settings.dart';
import 'geofence_manager.dart';

/// 현재 위치가 회사 반경 안인지 판단한다.
///
/// 반환:
/// - true  : 회사 반경 안
/// - false : 회사 반경 밖
/// - null  : 알 수 없음(위치 서비스 꺼짐/권한 없음/타임아웃)
class LocationGate {
  static Future<bool?> isInsideOffice(AppSettings settings) async {
    // 1) 지오펜스가 동작 중이면 그 상태를 우선 사용(빠름, 포그라운드).
    final st = GeofenceManager.instance.status.value;
    if (st == GeofenceStatus.ENTER || st == GeofenceStatus.DWELL) return true;
    if (st == GeofenceStatus.EXIT) return false;

    // 2) 단발성 현재 위치로 거리 계산(백그라운드/지오펜스 미동작 시).
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return null;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );
      final distance = Geolocator.distanceBetween(
        pos.latitude,
        pos.longitude,
        settings.officeLatitude,
        settings.officeLongitude,
      );
      return distance <= settings.radiusMeters;
    } catch (_) {
      return null;
    }
  }
}
