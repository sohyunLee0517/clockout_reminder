/// 근태 기록 한 건을 나타내는 모델.
///
/// 출근(checkIn) / 퇴근(checkOut) 이벤트를 하나의 행으로 저장한다.
/// 위치 이탈·시간 트리거 등 어떤 사유로 기록되었는지도 함께 남긴다.
enum AttendanceType {
  checkIn, // 출근 (지오펜스 진입)
  checkOut; // 퇴근 (지오펜스 이탈 또는 수동 체크)

  String get label => this == AttendanceType.checkIn ? '출근' : '퇴근';
}

/// 기록이 만들어진 사유.
enum AttendanceTrigger {
  geofenceEnter, // 회사 반경 진입
  geofenceExit, // 회사 반경 이탈
  scheduledTime, // 퇴근 예정 시간 도달
  manual; // 사용자가 직접 체크

  String get label {
    switch (this) {
      case AttendanceTrigger.geofenceEnter:
        return '위치 진입';
      case AttendanceTrigger.geofenceExit:
        return '위치 이탈';
      case AttendanceTrigger.scheduledTime:
        return '예정 시간';
      case AttendanceTrigger.manual:
        return '직접 체크';
    }
  }
}

class AttendanceRecord {
  final int? id;
  final AttendanceType type;
  final AttendanceTrigger trigger;
  final DateTime timestamp;
  final double? latitude;
  final double? longitude;
  final String? memo;

  const AttendanceRecord({
    this.id,
    required this.type,
    required this.trigger,
    required this.timestamp,
    this.latitude,
    this.longitude,
    this.memo,
  });

  AttendanceRecord copyWith({
    int? id,
    AttendanceType? type,
    AttendanceTrigger? trigger,
    DateTime? timestamp,
    double? latitude,
    double? longitude,
    String? memo,
  }) {
    return AttendanceRecord(
      id: id ?? this.id,
      type: type ?? this.type,
      trigger: trigger ?? this.trigger,
      timestamp: timestamp ?? this.timestamp,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      memo: memo ?? this.memo,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'type': type.name,
      'trigger': trigger.name,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'latitude': latitude,
      'longitude': longitude,
      'memo': memo,
    };
  }

  factory AttendanceRecord.fromMap(Map<String, Object?> map) {
    return AttendanceRecord(
      id: map['id'] as int?,
      type: AttendanceType.values.byName(map['type'] as String),
      trigger: AttendanceTrigger.values.byName(map['trigger'] as String),
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
      latitude: map['latitude'] as double?,
      longitude: map['longitude'] as double?,
      memo: map['memo'] as String?,
    );
  }
}
