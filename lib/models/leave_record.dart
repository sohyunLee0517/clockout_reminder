/// 연차 종류.
enum LeaveType {
  annual(1.0, '연차'),
  half(0.5, '반차'),
  quarter(0.25, '반반차'),
  hourly(0.0, '시간차'); // amount 는 입력 시간으로 계산

  final double defaultAmount; // 기본 차감 일수
  final String label;
  const LeaveType(this.defaultAmount, this.label);
}

/// 연차 사용/계획 한 건.
class LeaveRecord {
  final int? id;
  final DateTime date; // 연차 날짜 (자정 기준)
  final LeaveType type;
  final double amount; // 실제 차감 일수 (시간차는 계산값)
  final double? hours; // 시간차일 때 입력 시간
  final String? memo;

  const LeaveRecord({
    this.id,
    required this.date,
    required this.type,
    required this.amount,
    this.hours,
    this.memo,
  });

  /// 미래 날짜면 "계획", 과거/오늘이면 "사용".
  bool get isPlanned {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return date.isAfter(today);
  }

  LeaveRecord copyWith({
    int? id,
    DateTime? date,
    LeaveType? type,
    double? amount,
    double? hours,
    String? memo,
  }) {
    return LeaveRecord(
      id: id ?? this.id,
      date: date ?? this.date,
      type: type ?? this.type,
      amount: amount ?? this.amount,
      hours: hours ?? this.hours,
      memo: memo ?? this.memo,
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'date': DateTime(date.year, date.month, date.day).millisecondsSinceEpoch,
        'type': type.name,
        'amount': amount,
        'hours': hours,
        'memo': memo,
      };

  factory LeaveRecord.fromMap(Map<String, Object?> map) {
    final type = LeaveType.values.byName(map['type'] as String);
    return LeaveRecord(
      id: map['id'] as int?,
      date: DateTime.fromMillisecondsSinceEpoch(map['date'] as int),
      type: type,
      // 구버전(amount 컬럼 없던 행) 대비: 없으면 종류 기본값.
      amount: (map['amount'] as num?)?.toDouble() ?? type.defaultAmount,
      hours: (map['hours'] as num?)?.toDouble(),
      memo: map['memo'] as String?,
    );
  }
}
