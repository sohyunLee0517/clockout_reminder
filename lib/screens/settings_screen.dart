import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../models/app_settings.dart';
import '../services/permission_service.dart';
import '../utils/time_rules.dart';
import 'map_picker_screen.dart';

class SettingsScreen extends StatefulWidget {
  final AppSettings settings;
  const SettingsScreen({super.key, required this.settings});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late AppSettings _draft;

  static const _unitOptions = <int>[1, 5, 10, 15, 30, 60];

  @override
  void initState() {
    super.initState();
    _draft = widget.settings;
  }

  Future<void> _pickOnMap() async {
    final picked = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(
        builder: (_) => MapPickerScreen(
          initial: LatLng(_draft.officeLatitude, _draft.officeLongitude),
          radiusMeters: _draft.radiusMeters,
        ),
      ),
    );
    if (picked != null) {
      setState(() {
        _draft = _draft.copyWith(
          officeLatitude: picked.latitude,
          officeLongitude: picked.longitude,
        );
      });
    }
  }

  Future<void> _pickMinutes({
    required String title,
    required int current,
    int maxHours = 14,
  }) async {
    final result =
        await _pickMinutesValue(title: title, current: current, maxHours: maxHours);
    if (result == null) return;
    setState(() {
      if (title.contains('근무')) {
        _draft = _draft.copyWith(workMinutes: result);
      } else {
        _draft = _draft.copyWith(lunchMinutes: result);
      }
    });
  }

  /// 시/분 선택 다이얼로그 — 선택한 총 분을 반환(취소 시 null).
  Future<int?> _pickMinutesValue({
    required String title,
    required int current,
    int maxHours = 14,
  }) async {
    int hours = current ~/ 60;
    int minutes = current % 60;
    return showDialog<int>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            return AlertDialog(
              title: Text(title),
              content: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _numberDropdown(
                    value: hours,
                    items: List.generate(maxHours + 1, (i) => i),
                    suffix: '시간',
                    onChanged: (v) => setLocal(() => hours = v),
                  ),
                  const SizedBox(width: 12),
                  _numberDropdown(
                    value: minutes,
                    items: const [0, 5, 10, 15, 20, 30, 40, 45, 50, 55],
                    suffix: '분',
                    onChanged: (v) => setLocal(() => minutes = v),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('취소'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, hours * 60 + minutes),
                  child: const Text('확인'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// 연장근무 스누즈 시간 선택 — 프리셋 + 직접 입력.
  Future<void> _pickSnooze() async {
    const presets = <int>[30, 60, 90, 120, 180];
    final result = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('연장근무 스누즈'),
        children: [
          for (final m in presets)
            ListTile(
              title: Text(TimeRules.formatDuration(m)),
              trailing: m == _draft.overtimeSnoozeMinutes
                  ? Icon(Icons.check,
                      color: Theme.of(context).colorScheme.primary)
                  : null,
              onTap: () => Navigator.pop(context, m),
            ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.edit),
            title: const Text('직접 입력'),
            onTap: () => Navigator.pop(context, -1),
          ),
        ],
      ),
    );
    if (result == null) return;
    if (result == -1) {
      final custom = await _pickMinutesValue(
        title: '연장근무 스누즈',
        current: _draft.overtimeSnoozeMinutes,
        maxHours: 6,
      );
      if (custom != null && custom > 0) {
        setState(
            () => _draft = _draft.copyWith(overtimeSnoozeMinutes: custom));
      }
    } else {
      setState(() => _draft = _draft.copyWith(overtimeSnoozeMinutes: result));
    }
  }

  Widget _numberDropdown({
    required int value,
    required List<int> items,
    required String suffix,
    required ValueChanged<int> onChanged,
  }) {
    return DropdownButton<int>(
      value: items.contains(value) ? value : items.first,
      items: items
          .map((e) => DropdownMenuItem(value: e, child: Text('$e$suffix')))
          .toList(),
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }

  Future<void> _pickUnit() async {
    final result = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('출퇴근 시간 단위'),
        children: _unitOptions.map((u) {
          final selected = u == _draft.roundUnitMinutes;
          return ListTile(
            title: Text(_unitLabel(u)),
            trailing: selected
                ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary)
                : null,
            onTap: () => Navigator.pop(context, u),
          );
        }).toList(),
      ),
    );
    if (result != null) {
      setState(() => _draft = _draft.copyWith(roundUnitMinutes: result));
    }
  }

  String _unitLabel(int u) => u == 60 ? '1시간' : '$u분';

  void _save() {
    Navigator.of(context).pop(_draft.copyWith(configured: true));
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 예시 미리보기: 지금 출근하면 퇴근시각.
    final previewOut = TimeRules.computeClockOut(DateTime.now(), _draft);
    final previewStr =
        '${previewOut.hour.toString().padLeft(2, '0')}:${previewOut.minute.toString().padLeft(2, '0')}';

    return Scaffold(
      appBar: AppBar(
        title: const Text('설정'),
        actions: [
          TextButton(onPressed: _save, child: const Text('저장')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionTitle(theme, '회사 위치'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.map),
                  title: const Text('지도에서 회사 위치 지정'),
                  subtitle: Text(
                    '위도 ${_draft.officeLatitude.toStringAsFixed(6)}, '
                    '경도 ${_draft.officeLongitude.toStringAsFixed(6)}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _pickOnMap,
                ),
                const Divider(height: 1),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('감지 반경'),
                          Text('${_draft.radiusMeters.round()} m',
                              style: theme.textTheme.titleMedium),
                        ],
                      ),
                      Slider(
                        value: _draft.radiusMeters,
                        min: 50,
                        max: 1000,
                        divisions: 19,
                        label: '${_draft.radiusMeters.round()} m',
                        onChanged: (v) => setState(
                            () => _draft = _draft.copyWith(radiusMeters: v)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _sectionTitle(theme, '근무 규칙'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.work_outline),
                  title: const Text('근무 시간'),
                  trailing: Text(
                    TimeRules.formatDuration(_draft.workMinutes),
                    style: theme.textTheme.titleMedium,
                  ),
                  onTap: () => _pickMinutes(
                    title: '근무 시간',
                    current: _draft.workMinutes,
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.restaurant),
                  title: const Text('점심(휴게) 시간'),
                  trailing: Text(
                    TimeRules.formatDuration(_draft.lunchMinutes),
                    style: theme.textTheme.titleMedium,
                  ),
                  onTap: () => _pickMinutes(
                    title: '점심 시간',
                    current: _draft.lunchMinutes,
                    maxHours: 3,
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.schedule),
                  title: const Text('출퇴근 시간 단위'),
                  subtitle:
                      const Text('출근시각을 이 단위로 올림해 근무시간을 계산'),
                  trailing: Text(
                    _unitLabel(_draft.roundUnitMinutes),
                    style: theme.textTheme.titleMedium,
                  ),
                  onTap: _pickUnit,
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.lightbulb_outline,
                            size: 18, color: theme.colorScheme.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '지금 출근한다면 예상 퇴근시각은 $previewStr 입니다.',
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _sectionTitle(theme, '알림'),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('위치 기반 감지'),
                  subtitle: const Text('회사 반경 진입/이탈 자동 감지'),
                  value: _draft.geofenceEnabled,
                  onChanged: (v) => setState(
                      () => _draft = _draft.copyWith(geofenceEnabled: v)),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('도착 시 출근 확인'),
                  subtitle: const Text('"출근하시겠습니까?" 확인 후 알림 설정'),
                  value: _draft.confirmOnArrival,
                  onChanged: (v) => setState(
                      () => _draft = _draft.copyWith(confirmOnArrival: v)),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('퇴근 시간 푸시'),
                  subtitle: const Text('계산된 퇴근시각에 알림 전송'),
                  value: _draft.clockOutAlarmEnabled,
                  onChanged: (v) => setState(
                      () => _draft = _draft.copyWith(clockOutAlarmEnabled: v)),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.snooze),
                  title: const Text('연장근무 스누즈'),
                  subtitle: const Text('"연장근무" 선택 시 다시 알리기까지의 시간'),
                  trailing: Text(
                    TimeRules.formatDuration(_draft.overtimeSnoozeMinutes),
                    style: theme.textTheme.titleMedium,
                  ),
                  onTap: _pickSnooze,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _sectionTitle(theme, '권한'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.notifications_active),
                  title: const Text('알림 권한 요청'),
                  onTap: () async {
                    final ok = await PermissionService.instance
                        .ensureNotificationPermission();
                    _snack(ok ? '알림 권한이 허용되었습니다.' : '알림 권한이 거부되었습니다.');
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.my_location),
                  title: const Text('백그라운드 위치 권한 요청'),
                  subtitle: const Text('앱을 닫아도 감지하려면 "항상 허용" 필요'),
                  onTap: () async {
                    final loc = await PermissionService.instance
                        .ensureLocationPermission();
                    if (!loc.isGranted) {
                      _snack(loc.message);
                      return;
                    }
                    final bg = await PermissionService.instance
                        .ensureBackgroundLocation();
                    _snack(bg
                        ? '백그라운드 위치 권한이 허용되었습니다.'
                        : '설정에서 "항상 허용"으로 변경해 주세요.');
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.open_in_new),
                  title: const Text('앱 설정 열기'),
                  onTap: () => PermissionService.instance.openSettings(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _save,
            style:
                FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            child: const Text('저장하고 적용'),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(ThemeData theme, String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(text,
          style: theme.textTheme.titleSmall
              ?.copyWith(color: theme.colorScheme.primary)),
    );
  }
}
