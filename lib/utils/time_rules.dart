import '../models/app_settings.dart';

/// 출퇴근 시간 계산 규칙.
class TimeRules {
  /// 시각을 [unitMinutes] 단위로 "올림"한다. (초는 버린다)
  ///
  /// 예) unit=10 → 8:09 이면 8:10, 8:10 이면 그대로 8:10
  ///     unit=60 → 8:30 이면 9:00, 9:00 이면 그대로 9:00
  static DateTime roundUpToUnit(DateTime t, int unitMinutes) {
    final base = DateTime(t.year, t.month, t.day, t.hour, t.minute);
    if (unitMinutes <= 1) return base;

    final minutesOfDay = base.hour * 60 + base.minute;
    final remainder = minutesOfDay % unitMinutes;
    if (remainder == 0) return base;

    final rounded = minutesOfDay - remainder + unitMinutes;
    final dayStart = DateTime(t.year, t.month, t.day);
    return dayStart.add(Duration(minutes: rounded));
  }

  /// 실제 출근시각([checkIn])과 설정으로부터 퇴근 예정시각을 계산한다.
  ///
  /// 퇴근시각 = 올림한 출근시각 + 근무시간 + 점심시간
  static DateTime computeClockOut(DateTime checkIn, AppSettings settings) {
    final effectiveStart = roundUpToUnit(checkIn, settings.roundUnitMinutes);
    return effectiveStart.add(Duration(minutes: settings.totalStayMinutes));
  }

  /// "8시간", "8시간 30분" 처럼 분을 사람이 읽기 좋게.
  static String formatDuration(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h > 0 && m > 0) return '$h시간 $m분';
    if (h > 0) return '$h시간';
    return '$m분';
  }
}
