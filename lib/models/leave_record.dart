/// 연차 종류 (소진 일수 포함).
enum LeaveType {
  annual(1.0, '연차'),
  morningHalf(0.5, '오전 반차'),
  afternoonHalf(0.5, '오후 반차');

  final double amount; // 차감 일수
  final String label;
  const LeaveType(this.amount, this.label);
}

/// 연차 사용/계획 한 건.
class LeaveRecord {
  final int? id;
  final DateTime date; // 연차 날짜 (자정 기준)
  final LeaveType type;
  final String? memo;

  const LeaveRecord({
    this.id,
    required this.date,
    required this.type,
    this.memo,
  });

  double get amount => type.amount;

  /// 미래 날짜면 "계획", 과거/오늘이면 "사용".
  bool get isPlanned {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return date.isAfter(today);
  }

  LeaveRecord copyWith({int? id, DateTime? date, LeaveType? type, String? memo}) {
    return LeaveRecord(
      id: id ?? this.id,
      date: date ?? this.date,
      type: type ?? this.type,
      memo: memo ?? this.memo,
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'date': DateTime(date.year, date.month, date.day).millisecondsSinceEpoch,
        'type': type.name,
        'memo': memo,
      };

  factory LeaveRecord.fromMap(Map<String, Object?> map) => LeaveRecord(
        id: map['id'] as int?,
        date: DateTime.fromMillisecondsSinceEpoch(map['date'] as int),
        type: LeaveType.values.byName(map['type'] as String),
        memo: map['memo'] as String?,
      );
}
