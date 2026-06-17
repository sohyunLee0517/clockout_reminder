import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_settings.dart';

/// 앱 설정을 shared_preferences 로 저장/조회한다.
class SettingsService {
  SettingsService._();
  static final SettingsService instance = SettingsService._();

  static const _kLat = 'office_lat';
  static const _kLng = 'office_lng';
  static const _kRadius = 'radius_m';
  static const _kWork = 'work_minutes';
  static const _kLunch = 'lunch_minutes';
  static const _kUnit = 'round_unit_minutes';
  static const _kGeofence = 'geofence_enabled';
  static const _kConfirm = 'confirm_on_arrival';
  static const _kClockOutAlarm = 'clockout_alarm_enabled';
  static const _kOvertimeSnooze = 'overtime_snooze_minutes';
  static const _kKakaoOnCheck = 'kakao_on_check';
  static const _kKakaoOnMissing = 'kakao_on_missing';
  static const _kSlackUrl = 'slack_webhook_url';
  static const _kSlackOnCheck = 'slack_on_check';
  static const _kSlackOnMissing = 'slack_on_missing';
  static const _kAnnualLeave = 'annual_leave_total';
  static const _kConfigured = 'configured';

  Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final d = AppSettings.defaults();
    return AppSettings(
      officeLatitude: prefs.getDouble(_kLat) ?? d.officeLatitude,
      officeLongitude: prefs.getDouble(_kLng) ?? d.officeLongitude,
      radiusMeters: prefs.getDouble(_kRadius) ?? d.radiusMeters,
      workMinutes: prefs.getInt(_kWork) ?? d.workMinutes,
      lunchMinutes: prefs.getInt(_kLunch) ?? d.lunchMinutes,
      roundUnitMinutes: prefs.getInt(_kUnit) ?? d.roundUnitMinutes,
      geofenceEnabled: prefs.getBool(_kGeofence) ?? d.geofenceEnabled,
      confirmOnArrival: prefs.getBool(_kConfirm) ?? d.confirmOnArrival,
      clockOutAlarmEnabled:
          prefs.getBool(_kClockOutAlarm) ?? d.clockOutAlarmEnabled,
      overtimeSnoozeMinutes:
          prefs.getInt(_kOvertimeSnooze) ?? d.overtimeSnoozeMinutes,
      kakaoOnCheck: prefs.getBool(_kKakaoOnCheck) ?? d.kakaoOnCheck,
      kakaoOnMissing: prefs.getBool(_kKakaoOnMissing) ?? d.kakaoOnMissing,
      slackWebhookUrl: prefs.getString(_kSlackUrl) ?? d.slackWebhookUrl,
      slackOnCheck: prefs.getBool(_kSlackOnCheck) ?? d.slackOnCheck,
      slackOnMissing: prefs.getBool(_kSlackOnMissing) ?? d.slackOnMissing,
      annualLeaveTotal: prefs.getDouble(_kAnnualLeave) ?? d.annualLeaveTotal,
      configured: prefs.getBool(_kConfigured) ?? d.configured,
    );
  }

  Future<void> save(AppSettings s) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kLat, s.officeLatitude);
    await prefs.setDouble(_kLng, s.officeLongitude);
    await prefs.setDouble(_kRadius, s.radiusMeters);
    await prefs.setInt(_kWork, s.workMinutes);
    await prefs.setInt(_kLunch, s.lunchMinutes);
    await prefs.setInt(_kUnit, s.roundUnitMinutes);
    await prefs.setBool(_kGeofence, s.geofenceEnabled);
    await prefs.setBool(_kConfirm, s.confirmOnArrival);
    await prefs.setBool(_kClockOutAlarm, s.clockOutAlarmEnabled);
    await prefs.setInt(_kOvertimeSnooze, s.overtimeSnoozeMinutes);
    await prefs.setBool(_kKakaoOnCheck, s.kakaoOnCheck);
    await prefs.setBool(_kKakaoOnMissing, s.kakaoOnMissing);
    await prefs.setString(_kSlackUrl, s.slackWebhookUrl);
    await prefs.setBool(_kSlackOnCheck, s.slackOnCheck);
    await prefs.setBool(_kSlackOnMissing, s.slackOnMissing);
    await prefs.setDouble(_kAnnualLeave, s.annualLeaveTotal);
    await prefs.setBool(_kConfigured, true);
  }
}
