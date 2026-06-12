/// 사용자가 설정 화면에서 지정하는 값들.
///
/// shared_preferences 에 저장된다. (SettingsService 참고)
class AppSettings {
  /// 회사 위치 위도/경도
  final double officeLatitude;
  final double officeLongitude;

  /// 회사로 인정할 반경(미터)
  final double radiusMeters;

  /// 근무 시간(분). 예: 480 = 8시간
  final int workMinutes;

  /// 점심(휴게) 시간(분). 예: 60 = 1시간. 퇴근시각 계산에 더해진다.
  final int lunchMinutes;

  /// 출퇴근 시간 단위(분) — 출근시각을 이 단위로 "올림"한 뒤 근무시간을 센다.
  /// 예: 10분 단위면 8:09 → 8:10, 60분 단위면 8:30 → 9:00.
  final int roundUnitMinutes;

  /// 위치 기반 감지 사용 여부
  final bool geofenceEnabled;

  /// 도착 시 "출근하시겠습니까?" 확인 후 알림 설정 여부.
  /// false 면 도착 즉시 자동으로 출근 처리.
  final bool confirmOnArrival;

  /// 계산된 퇴근시각에 푸시 알림을 보낼지 여부.
  final bool clockOutAlarmEnabled;

  /// 연장근무 선택 시 리마인더를 미룰(스누즈) 시간(분). 기본 60분.
  final int overtimeSnoozeMinutes;

  // ── 외부 연동: 카카오(나에게 보내기) ──
  /// 출퇴근 체크(실제 기록) 시 카톡 전송.
  final bool kakaoOnCheck;

  /// 출퇴근 미입력(퇴근 안 찍고 이탈 등) 시 카톡 전송.
  final bool kakaoOnMissing;

  // ── 외부 연동: 슬랙(Incoming Webhook) ──
  final String slackWebhookUrl;

  /// 출퇴근 체크 시 슬랙 전송.
  final bool slackOnCheck;

  /// 출퇴근 미입력 시 슬랙 전송.
  final bool slackOnMissing;

  /// 설정이 한 번이라도 저장되었는지 (초기 온보딩 판단용)
  final bool configured;

  const AppSettings({
    required this.officeLatitude,
    required this.officeLongitude,
    required this.radiusMeters,
    required this.workMinutes,
    required this.lunchMinutes,
    required this.roundUnitMinutes,
    required this.geofenceEnabled,
    required this.confirmOnArrival,
    required this.clockOutAlarmEnabled,
    required this.overtimeSnoozeMinutes,
    required this.kakaoOnCheck,
    required this.kakaoOnMissing,
    required this.slackWebhookUrl,
    required this.slackOnCheck,
    required this.slackOnMissing,
    required this.configured,
  });

  /// 기본값: 서울시청 좌표, 반경 150m, 근무 8시간 + 점심 1시간, 10분 단위.
  factory AppSettings.defaults() {
    return const AppSettings(
      officeLatitude: 37.5662952,
      officeLongitude: 126.9779451,
      radiusMeters: 150,
      workMinutes: 480,
      lunchMinutes: 60,
      roundUnitMinutes: 10,
      geofenceEnabled: true,
      confirmOnArrival: true,
      clockOutAlarmEnabled: true,
      overtimeSnoozeMinutes: 60,
      kakaoOnCheck: false,
      kakaoOnMissing: false,
      slackWebhookUrl: '',
      slackOnCheck: false,
      slackOnMissing: false,
      configured: false,
    );
  }

  /// 총 체류 시간(근무+점심) 분.
  int get totalStayMinutes => workMinutes + lunchMinutes;

  AppSettings copyWith({
    double? officeLatitude,
    double? officeLongitude,
    double? radiusMeters,
    int? workMinutes,
    int? lunchMinutes,
    int? roundUnitMinutes,
    bool? geofenceEnabled,
    bool? confirmOnArrival,
    bool? clockOutAlarmEnabled,
    int? overtimeSnoozeMinutes,
    bool? kakaoOnCheck,
    bool? kakaoOnMissing,
    String? slackWebhookUrl,
    bool? slackOnCheck,
    bool? slackOnMissing,
    bool? configured,
  }) {
    return AppSettings(
      officeLatitude: officeLatitude ?? this.officeLatitude,
      officeLongitude: officeLongitude ?? this.officeLongitude,
      radiusMeters: radiusMeters ?? this.radiusMeters,
      workMinutes: workMinutes ?? this.workMinutes,
      lunchMinutes: lunchMinutes ?? this.lunchMinutes,
      roundUnitMinutes: roundUnitMinutes ?? this.roundUnitMinutes,
      geofenceEnabled: geofenceEnabled ?? this.geofenceEnabled,
      confirmOnArrival: confirmOnArrival ?? this.confirmOnArrival,
      clockOutAlarmEnabled: clockOutAlarmEnabled ?? this.clockOutAlarmEnabled,
      overtimeSnoozeMinutes:
          overtimeSnoozeMinutes ?? this.overtimeSnoozeMinutes,
      kakaoOnCheck: kakaoOnCheck ?? this.kakaoOnCheck,
      kakaoOnMissing: kakaoOnMissing ?? this.kakaoOnMissing,
      slackWebhookUrl: slackWebhookUrl ?? this.slackWebhookUrl,
      slackOnCheck: slackOnCheck ?? this.slackOnCheck,
      slackOnMissing: slackOnMissing ?? this.slackOnMissing,
      configured: configured ?? this.configured,
    );
  }
}
