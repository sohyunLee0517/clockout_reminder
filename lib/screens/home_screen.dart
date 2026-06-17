import 'dart:async';

import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:geofence_service/geofence_service.dart';
import 'package:intl/intl.dart';

import '../models/app_settings.dart';
import '../models/attendance_record.dart';
import '../models/leave_record.dart';
import '../services/attendance_controller.dart';
import '../services/database_service.dart';
import '../services/geofence_manager.dart';
import '../services/location_gate.dart';
import '../services/widget_service.dart';
import '../utils/time_rules.dart';
import 'history_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  final AppSettings initialSettings;
  const HomeScreen({super.key, required this.initialSettings});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final _controller = AttendanceController.instance;
  AppSettings get _settings => _controller.settings;

  List<AttendanceRecord> _today = [];
  bool _loading = true;
  bool _dialogOpen = false;

  /// 현재 회사 반경 안인지: true=안, false=밖, null=알 수 없음.
  bool? _insideOffice;
  Timer? _insideTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller.changed.addListener(_refresh);
    _controller.pendingArrival.addListener(_maybeShowArrivalDialog);
    _controller.pendingDeparture.addListener(_maybeShowDepartureDialog);
    GeofenceManager.instance.status.addListener(_updateInsideState);
    // 화면이 열려 있는 동안 주기적으로 반경 안/밖 갱신.
    _insideTimer =
        Timer.periodic(const Duration(seconds: 45), (_) => _updateInsideState());
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.changed.removeListener(_refresh);
    _controller.pendingArrival.removeListener(_maybeShowArrivalDialog);
    _controller.pendingDeparture.removeListener(_maybeShowDepartureDialog);
    GeofenceManager.instance.status.removeListener(_updateInsideState);
    _insideTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refresh();
      _updateInsideState();
      _controller.checkArrivalMissing();
      _controller.checkDepartureMissing();
      _maybeShowArrivalDialog();
      _maybeShowDepartureDialog();
    }
  }

  Future<void> _updateInsideState() async {
    final v = await LocationGate.isInsideOffice(_settings);
    if (mounted && v != _insideOffice) setState(() => _insideOffice = v);
  }

  void _toast(String msg) {
    Fluttertoast.showToast(
      msg: msg,
      gravity: ToastGravity.BOTTOM,
      toastLength: Toast.LENGTH_SHORT,
    );
  }

  Future<void> _bootstrap() async {
    if (!_settings.configured) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openSettings());
    }
    await _refresh();
    _updateInsideState();
    _maybeShowArrivalDialog();
    _maybeShowDepartureDialog();
  }

  Future<void> _refresh() async {
    final today = await DatabaseService.instance.getByDate(DateTime.now());
    // 홈 화면이 갱신될 때마다 위젯도 최신 상태로 동기화.
    await WidgetService.sync();
    if (!mounted) return;
    setState(() {
      _today = today;
      _loading = false;
    });
  }

  AttendanceRecord? get _checkIn =>
      _today.where((r) => r.type == AttendanceType.checkIn).firstOrNull;
  AttendanceRecord? get _checkOut =>
      _today.where((r) => r.type == AttendanceType.checkOut).firstOrNull;

  DateTime? get _predictedClockOut {
    if (_checkIn == null) return null;
    return TimeRules.computeClockOut(_checkIn!.timestamp, _settings);
  }

  Future<void> _maybeShowArrivalDialog() async {
    final pending = _controller.pendingArrival.value;
    if (pending == null || _dialogOpen || !mounted) return;
    // 이미 출근했으면 대기 해제.
    if (await _controller.isCheckedInToday()) {
      _controller.pendingArrival.value = null;
      return;
    }
    // 오늘이 연차면 "연차 확인" 다이얼로그로 분기.
    final leave = await _controller.todayLeave();
    if (!mounted) return;
    if (leave != null) {
      _controller.pendingArrival.value = null;
      await _showLeaveArrivalDialog(leave, pending);
      return;
    }
    _dialogOpen = true;
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('회사에 도착했어요'),
        content: const Text('출근하시겠습니까?\n잠깐 들른 거면 "무시"를 누르세요. (회사 재진입 시 다시 알림)'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'ignore'),
            child: const Text('무시'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'checkin'),
            child: const Text('출근하기'),
          ),
        ],
      ),
    );
    _dialogOpen = false;
    if (result == 'checkin') {
      final r = await _controller.guardedCheckIn(
        trigger: AttendanceTrigger.geofenceEnter,
        latitude: pending.latitude,
        longitude: pending.longitude,
      );
      if (_showBlockedToast(r, isCheckIn: true)) return;
      _showClockOutSnack();
    } else if (result == 'ignore') {
      await _controller.ignoreArrival();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('출근 알림을 무시했어요. (회사 재진입 시 리셋)')),
        );
      }
    }
  }

  /// 연차일에 회사 도착 → 연차 유지 vs 출근(연차 취소) 확인.
  Future<void> _showLeaveArrivalDialog(
      LeaveRecord leave, PendingArrival pending) async {
    _dialogOpen = true;
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('오늘 연차예요'),
        content: Text(
            '오늘은 ${leave.type.label}(으)로 등록돼 있어요.\n연차가 맞나요, 아니면 출근하셨나요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'keep'),
            child: const Text('연차 맞아요'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'checkin'),
            child: const Text('출근할게요'),
          ),
        ],
      ),
    );
    _dialogOpen = false;
    if (result == 'checkin') {
      final r = await _controller.guardedCheckIn(
        trigger: AttendanceTrigger.geofenceEnter,
        latitude: pending.latitude,
        longitude: pending.longitude,
      );
      if (_showBlockedToast(r, isCheckIn: true)) return;
      await _controller.cancelTodayLeave(); // 출근했으니 연차 취소
      _showClockOutSnack();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('출근 처리하고 오늘 연차는 취소했어요.')),
        );
      }
    } else if (result == 'keep') {
      await _controller.ignoreArrival();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('연차로 유지할게요. 푹 쉬세요!')),
        );
      }
    }
  }

  Future<void> _maybeShowDepartureDialog() async {
    final pending = _controller.pendingDeparture.value;
    if (pending == null || _dialogOpen || !mounted) return;
    // 이미 퇴근했으면 대기 해제.
    if (await DatabaseService.instance.hasCheckedOutToday()) {
      _controller.pendingDeparture.value = null;
      return;
    }
    if (!mounted) return;
    _dialogOpen = true;
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('회사를 벗어났어요'),
        content: const Text(
            '퇴근하셨나요?\n잠깐 외출이면 "무시", 더 일하면 "연장근무"를 누르세요.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'ignore'),
            child: const Text('무시'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'overtime'),
            child: const Text('연장근무'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'checkout'),
            child: const Text('퇴근하기'),
          ),
        ],
      ),
    );
    _dialogOpen = false;
    if (result == 'checkout') {
      final r = await _controller.guardedCheckOut(
        trigger: AttendanceTrigger.geofenceExit,
        latitude: pending.latitude,
        longitude: pending.longitude,
      );
      if (_showBlockedToast(r, isCheckIn: false)) return;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('퇴근이 기록되었습니다. 수고하셨어요!')),
        );
      }
      await _maybeAskEarlyLeave(DateTime.now());
    } else if (result == 'ignore') {
      await _controller.ignoreDeparture();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('퇴근 알림을 무시했어요. (회사 재진입 시 리셋)')),
        );
      }
    } else if (result == 'overtime') {
      final minutes = await _chooseSnoozeMinutes();
      if (minutes == null) return; // 취소 시 그대로 대기(알림 계속)
      await _controller.snooze(minutes: minutes);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '연장근무로 처리했어요. ${TimeRules.formatDuration(minutes)} 후 다시 알려드릴게요.'),
          ),
        );
      }
    }
  }

  /// 연장근무 스누즈 시간 빠른 선택 (기본값 = 설정값).
  Future<int?> _chooseSnoozeMinutes() async {
    final current = _controller.settings.overtimeSnoozeMinutes;
    final options = <int>{30, 60, 120, current}.toList()..sort();
    return showDialog<int>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('얼마나 미룰까요?'),
        children: [
          for (final m in options)
            ListTile(
              title: Text(TimeRules.formatDuration(m)),
              trailing: m == current
                  ? const Text('기본', style: TextStyle(fontSize: 12))
                  : null,
              onTap: () => Navigator.pop(context, m),
            ),
        ],
      ),
    );
  }

  void _showClockOutSnack() {
    final out = _controller.scheduledClockOut ?? _predictedClockOut;
    if (out == null || !mounted) return;
    final t = DateFormat('a h:mm', 'ko').format(out);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('출근 완료! 퇴근 알림이 $t 부터 설정되었습니다.')),
    );
  }

  /// 반경 밖/위치 불명 시 토스트 안내. 차단되면 true 반환.
  bool _showBlockedToast(AttendanceResult r, {required bool isCheckIn}) {
    if (r == AttendanceResult.ok || r == AttendanceResult.noop) return false;
    final what = isCheckIn ? '출근' : '퇴근';
    _toast(r == AttendanceResult.outside
        ? '회사 반경 밖이에요. 회사 근처에서만 $what할 수 있어요.'
        : '현재 위치를 확인할 수 없어요. 위치 권한·GPS를 확인해 주세요.');
    return true;
  }

  Future<void> _manualCheckIn() async {
    final r = await _controller.guardedCheckIn(trigger: AttendanceTrigger.manual);
    if (_showBlockedToast(r, isCheckIn: true)) return;
    _showClockOutSnack();
  }

  Future<void> _manualCheckOut() async {
    final r =
        await _controller.guardedCheckOut(trigger: AttendanceTrigger.manual);
    if (_showBlockedToast(r, isCheckIn: false)) return;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('퇴근이 기록되었습니다. 수고하셨어요!')),
      );
    }
    await _maybeAskEarlyLeave(DateTime.now());
  }

  static String _fmtDays(double d) =>
      d == d.roundToDouble() ? '${d.toInt()}' : d.toStringAsFixed(2);

  /// 예상 퇴근보다 30분 이상 일찍 퇴근 시 → 연차 사용 여부 묻기.
  Future<void> _maybeAskEarlyLeave(DateTime checkoutTime) async {
    final checkIn = _checkIn;
    if (checkIn == null) return;
    if (await _controller.todayLeave() != null) return; // 이미 연차 등록됨
    final predicted = TimeRules.computeClockOut(checkIn.timestamp, _settings);
    if (!checkoutTime.isBefore(predicted.subtract(const Duration(minutes: 30)))) {
      return; // 충분히 일찍이 아니면 묻지 않음
    }
    if (!mounted) return;
    final df = DateFormat('a h:mm', 'ko');
    final type = await showDialog<LeaveType>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('일찍 퇴근하셨네요'),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
            child: Text(
                '예상 퇴근 ${df.format(predicted)} 보다 일찍 퇴근했어요.\n연차를 사용하셨나요?'),
          ),
          for (final t in LeaveType.values)
            ListTile(
              leading: const Icon(Icons.event_available),
              title: Text(t.label),
              onTap: () => Navigator.pop(context, t),
            ),
          const Divider(height: 1),
          ListTile(
            title: const Text('아니오 (연차 아님)'),
            onTap: () => Navigator.pop(context),
          ),
        ],
      ),
    );
    if (type == null) return;

    double amount;
    double? hours;
    if (type == LeaveType.hourly) {
      hours = await _askHours();
      if (hours == null) return;
      amount = _controller.dailyWorkHours > 0
          ? hours / _controller.dailyWorkHours
          : 0;
    } else {
      amount = type.defaultAmount;
    }
    final now = DateTime.now();
    await _controller.addLeave(LeaveRecord(
      date: DateTime(now.year, now.month, now.day),
      type: type,
      amount: amount,
      hours: hours,
      memo: '조기 퇴근',
    ));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${type.label} ${_fmtDays(amount)}일 차감했어요.')),
      );
    }
  }

  /// 시간차 사용 시간 입력.
  Future<double?> _askHours() async {
    final ctrl = TextEditingController();
    return showDialog<double>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('시간차 사용 시간'),
        content: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(suffixText: '시간'),
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('취소')),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, double.tryParse(ctrl.text.trim())),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  Future<void> _cancelCheckIn() async {
    await _controller.cancelCheckIn();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('출근을 취소했어요. (오늘 기록 초기화)')),
      );
    }
  }

  Future<void> _cancelCheckOut() async {
    await _controller.cancelCheckOut();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('퇴근을 취소했어요. 다시 근무 중이에요.')),
      );
    }
  }

  Future<void> _openSettings() async {
    final updated = await Navigator.of(context).push<AppSettings>(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(settings: _settings),
      ),
    );
    if (updated != null) {
      await _controller.updateSettings(updated);
      await GeofenceManager.instance.restart(updated);
    }
    if (mounted) setState(() {});
    await _refresh();
  }

  void _openHistory() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const HistoryScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('정직한근태씨'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: '기록',
            onPressed: _openHistory,
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: '설정',
            onPressed: _openSettings,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _statusCard(theme),
                  const SizedBox(height: 16),
                  _geofenceCard(theme),
                  const SizedBox(height: 16),
                  _actionButtons(theme),
                  const SizedBox(height: 24),
                  _todayTimeline(theme),
                ],
              ),
            ),
    );
  }

  Widget _statusCard(ThemeData theme) {
    final df = DateFormat('a h:mm', 'ko');
    final done = _checkOut != null;
    final out = _predictedClockOut;
    return Card(
      color: done
          ? theme.colorScheme.secondaryContainer
          : theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              DateFormat('M월 d일 (E)', 'ko').format(DateTime.now()),
              style: theme.textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            Text(
              done
                  ? '오늘 퇴근 완료 🎉'
                  : _checkIn != null
                      ? '근무 중'
                      : '출근 전',
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _stat('출근',
                    _checkIn == null ? '-' : df.format(_checkIn!.timestamp)),
                const SizedBox(width: 20),
                _stat('퇴근',
                    _checkOut == null ? '-' : df.format(_checkOut!.timestamp)),
                const SizedBox(width: 20),
                _stat(
                  '예상 퇴근',
                  (out == null || done) ? '-' : df.format(out),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, String value) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.bodySmall),
        const SizedBox(height: 2),
        Text(value,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _geofenceCard(ThemeData theme) {
    return ValueListenableBuilder<GeofenceStatus?>(
      valueListenable: GeofenceManager.instance.status,
      builder: (context, status, _) {
        final running = GeofenceManager.instance.isRunning;
        final (icon, text, color) = _statusVisual(status, running, theme);
        return Card(
          child: ListTile(
            leading: Icon(icon, color: color),
            title: Text(_settings.geofenceEnabled ? '위치 감지' : '위치 감지 꺼짐'),
            subtitle: Text(text),
          ),
        );
      },
    );
  }

  (IconData, String, Color) _statusVisual(
      GeofenceStatus? status, bool running, ThemeData theme) {
    if (!_settings.geofenceEnabled) {
      return (Icons.location_off, '설정에서 위치 감지를 켤 수 있어요.', theme.disabledColor);
    }
    if (!running) {
      return (Icons.gps_off, '감지 대기 중. 권한을 확인해 주세요.', theme.colorScheme.error);
    }
    switch (status) {
      case GeofenceStatus.ENTER:
      case GeofenceStatus.DWELL:
        return (Icons.business, '회사 반경 안에 있어요.', theme.colorScheme.primary);
      case GeofenceStatus.EXIT:
        return (
          Icons.directions_walk,
          '회사 반경을 벗어났어요.',
          theme.colorScheme.tertiary
        );
      case null:
        return (Icons.gps_fixed, '위치 감지 작동 중...', theme.colorScheme.primary);
    }
  }

  /// 반경 밖이면 비활성 모양 + 누르면 토스트, 안이면 정상 동작하는 주 버튼.
  Widget _gatedPrimary({
    required IconData icon,
    required String label,
    required VoidCallback onAction,
  }) {
    final outside = _insideOffice == false;
    if (outside) {
      return FilledButton.icon(
        onPressed: () =>
            _toast('회사 반경 밖이에요. 회사 근처에서만 출퇴근할 수 있어요.'),
        icon: Icon(icon),
        label: Text(label),
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          backgroundColor: Theme.of(context).disabledColor.withValues(alpha: 0.12),
          foregroundColor: Theme.of(context).disabledColor,
          elevation: 0,
        ),
      );
    }
    return FilledButton.icon(
      onPressed: onAction,
      icon: Icon(icon),
      label: Text(label),
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
    );
  }

  Widget _actionButtons(ThemeData theme) {
    final checkedIn = _checkIn != null;
    final checkedOut = _checkOut != null;

    // 주 동작 버튼 (상태에 따라 출근하기 / 퇴근하기 / 완료)
    final Widget primary;
    if (!checkedIn) {
      primary = _gatedPrimary(
        icon: Icons.login,
        label: '출근하기',
        onAction: _manualCheckIn,
      );
    } else if (!checkedOut) {
      primary = _gatedPrimary(
        icon: Icons.logout,
        label: '퇴근하기',
        onAction: _manualCheckOut,
      );
    } else {
      primary = FilledButton.icon(
        onPressed: null,
        icon: const Icon(Icons.check_circle),
        label: const Text('오늘 근무 완료'),
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
      );
    }

    // 잘못 누른 경우를 위한 취소 버튼들
    final cancels = <Widget>[];
    if (checkedIn) {
      cancels.add(Expanded(
        child: OutlinedButton.icon(
          onPressed: _cancelCheckIn,
          icon: const Icon(Icons.undo, size: 18),
          label: const Text('출근 취소'),
        ),
      ));
    }
    if (checkedOut) {
      if (cancels.isNotEmpty) cancels.add(const SizedBox(width: 12));
      cancels.add(Expanded(
        child: OutlinedButton.icon(
          onPressed: _cancelCheckOut,
          icon: const Icon(Icons.undo, size: 18),
          label: const Text('퇴근 취소'),
        ),
      ));
    }

    return Column(
      children: [
        primary,
        if (cancels.isNotEmpty) ...[
          const SizedBox(height: 10),
          Row(children: cancels),
        ],
      ],
    );
  }

  Widget _todayTimeline(ThemeData theme) {
    if (_today.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: Text('오늘 기록이 아직 없어요.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.disabledColor)),
        ),
      );
    }
    final df = DateFormat('a h:mm:ss', 'ko');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('오늘 기록', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        ..._today.map((r) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                r.type == AttendanceType.checkIn ? Icons.login : Icons.logout,
                color: r.type == AttendanceType.checkIn
                    ? theme.colorScheme.primary
                    : theme.colorScheme.tertiary,
              ),
              title: Text('${r.type.label} · ${r.trigger.label}'),
              subtitle: Text(df.format(r.timestamp)),
              trailing: const Icon(Icons.edit, size: 18),
              onTap: () => _editRecordTime(r),
            )),
        const SizedBox(height: 4),
        Text('항목을 탭하면 시간을 수정할 수 있어요.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.disabledColor)),
      ],
    );
  }

  /// 기록 시각 수기 수정 (시:분 선택).
  Future<void> _editRecordTime(AttendanceRecord r) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(r.timestamp),
      helpText: '${r.type.label} 시간 수정',
    );
    if (picked == null) return;
    final d = r.timestamp;
    final newTime = DateTime(d.year, d.month, d.day, picked.hour, picked.minute);
    await _controller.updateRecordTime(r, newTime);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(
            '${r.type.label} 시간을 ${DateFormat('a h:mm', 'ko').format(newTime)} 로 변경했어요.')),
      );
    }
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
