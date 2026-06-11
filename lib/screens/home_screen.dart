import 'package:flutter/material.dart';
import 'package:geofence_service/geofence_service.dart';
import 'package:intl/intl.dart';

import '../models/app_settings.dart';
import '../models/attendance_record.dart';
import '../services/attendance_controller.dart';
import '../services/database_service.dart';
import '../services/geofence_manager.dart';
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller.changed.addListener(_refresh);
    _controller.pendingArrival.addListener(_maybeShowArrivalDialog);
    _controller.pendingDeparture.addListener(_maybeShowDepartureDialog);
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.changed.removeListener(_refresh);
    _controller.pendingArrival.removeListener(_maybeShowArrivalDialog);
    _controller.pendingDeparture.removeListener(_maybeShowDepartureDialog);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refresh();
      _maybeShowArrivalDialog();
      _maybeShowDepartureDialog();
    }
  }

  Future<void> _bootstrap() async {
    if (!_settings.configured) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openSettings());
    }
    await _refresh();
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
    // 이미 출근했거나 오늘 "출근 안하기" 를 누른 상태면 대기 해제.
    if (await _controller.isCheckedInToday() ||
        await AttendanceController.isArrivalDismissedToday()) {
      _controller.pendingArrival.value = null;
      return;
    }
    if (!mounted) return;
    _dialogOpen = true;
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('회사에 도착했어요'),
        content: const Text('출근하시겠습니까?\n"출근 안하기"를 누르면 오늘은 더 묻지 않아요.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'skip'),
            child: const Text('출근 안하기'),
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
      await _controller.confirmCheckIn(
        trigger: AttendanceTrigger.geofenceEnter,
        latitude: pending.latitude,
        longitude: pending.longitude,
      );
      _showClockOutSnack();
    } else if (result == 'skip') {
      await _controller.skipArrivalToday();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('오늘은 출근 알림을 끌게요.')),
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
        content: const Text('퇴근하셨나요?\n아직 근무 중이면 "연장근무"를 누르세요.'),
        actions: [
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
      await _controller.checkOut(
        trigger: AttendanceTrigger.geofenceExit,
        latitude: pending.latitude,
        longitude: pending.longitude,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('퇴근이 기록되었습니다. 수고하셨어요!')),
        );
      }
    } else if (result == 'overtime') {
      await _controller.snooze();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('연장근무로 처리했어요. 잠시 후 다시 알려드릴게요.')),
        );
      }
    }
  }

  void _showClockOutSnack() {
    final out = _controller.scheduledClockOut ?? _predictedClockOut;
    if (out == null || !mounted) return;
    final t = DateFormat('a h:mm', 'ko').format(out);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('출근 완료! 퇴근 알림이 $t 부터 설정되었습니다.')),
    );
  }

  Future<void> _manualCheckIn() async {
    await _controller.confirmCheckIn(trigger: AttendanceTrigger.manual);
    _showClockOutSnack();
  }

  Future<void> _manualCheckOut() async {
    await _controller.checkOut(trigger: AttendanceTrigger.manual);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('퇴근이 기록되었습니다. 수고하셨어요!')),
      );
    }
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
        title: const Text('퇴근 알림'),
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

  Widget _actionButtons(ThemeData theme) {
    final checkedIn = _checkIn != null;
    final checkedOut = _checkOut != null;

    // 주 동작 버튼 (상태에 따라 출근하기 / 퇴근하기 / 완료)
    final Widget primary;
    if (!checkedIn) {
      primary = FilledButton.icon(
        onPressed: _manualCheckIn,
        icon: const Icon(Icons.login),
        label: const Text('출근하기'),
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
      );
    } else if (!checkedOut) {
      primary = FilledButton.icon(
        onPressed: _manualCheckOut,
        icon: const Icon(Icons.logout),
        label: const Text('퇴근하기'),
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
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
            )),
      ],
    );
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
