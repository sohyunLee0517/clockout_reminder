import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/leave_record.dart';
import '../services/attendance_controller.dart';
import '../services/database_service.dart';
import '../services/settings_service.dart';

class LeaveScreen extends StatefulWidget {
  const LeaveScreen({super.key});

  @override
  State<LeaveScreen> createState() => _LeaveScreenState();
}

class _LeaveScreenState extends State<LeaveScreen> {
  final _controller = AttendanceController.instance;
  late int _year;
  List<LeaveRecord> _leaves = [];
  double _total = 15;
  bool _loading = true;

  double get _used => _leaves
      .where((l) => !l.isPlanned)
      .fold(0.0, (s, l) => s + l.amount);
  double get _planned =>
      _leaves.where((l) => l.isPlanned).fold(0.0, (s, l) => s + l.amount);
  double get _remaining => _total - _used - _planned;

  /// 1일 소정근로시간(시간차 환산 기준).
  double get _dailyWorkHours => _controller.settings.workMinutes / 60.0;

  @override
  void initState() {
    super.initState();
    _year = DateTime.now().year;
    _load();
  }

  Future<void> _load() async {
    final leaves = await DatabaseService.instance.getLeavesByYear(_year);
    final total = await SettingsService.instance.annualLeaveTotalFor(_year);
    if (!mounted) return;
    setState(() {
      _leaves = leaves;
      _total = total;
      _loading = false;
    });
  }

  static String _fmtDays(double d) {
    if (d == d.roundToDouble()) return '${d.toInt()}';
    return d.toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('연차 관리'),
        actions: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            tooltip: '이전 해',
            onPressed: () => setState(() {
              _year--;
              _loading = true;
              _load();
            }),
          ),
          Center(child: Text('$_year', style: theme.textTheme.titleMedium)),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: '다음 해',
            onPressed: () => setState(() {
              _year++;
              _loading = true;
              _load();
            }),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addOrEdit(),
        icon: const Icon(Icons.add),
        label: const Text('연차 추가'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _summaryCard(theme),
                const SizedBox(height: 16),
                Text('$_year년 연차 내역', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                if (_leaves.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                      child: Text('등록된 연차가 없어요.',
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: theme.disabledColor)),
                    ),
                  )
                else
                  ..._leaves.reversed.map((l) => _leaveTile(theme, l)),
              ],
            ),
    );
  }

  Widget _summaryCard(ThemeData theme) {
    final remainingColor =
        _remaining < 0 ? theme.colorScheme.error : theme.colorScheme.primary;
    final progress = _total > 0
        ? ((_used + _planned) / _total).clamp(0.0, 1.0)
        : 0.0;
    return Card(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('잔여 연차', style: theme.textTheme.labelLarge),
                TextButton.icon(
                  onPressed: _editTotal,
                  icon: const Icon(Icons.edit, size: 16),
                  label: Text('총 ${_fmtDays(_total)}일'),
                ),
              ],
            ),
            Text('${_fmtDays(_remaining)}일',
                style: theme.textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.bold, color: remainingColor)),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 10,
                backgroundColor: theme.colorScheme.surface,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _stat(theme, '사용', '${_fmtDays(_used)}일'),
                const SizedBox(width: 24),
                _stat(theme, '예정', '${_fmtDays(_planned)}일'),
                const SizedBox(width: 24),
                _stat(theme, '총', '${_fmtDays(_total)}일'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(ThemeData theme, String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.bodySmall),
          Text(value,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
        ],
      );

  Widget _leaveTile(ThemeData theme, LeaveRecord l) {
    final df = DateFormat('M월 d일 (E)', 'ko');
    return Dismissible(
      key: ValueKey(l.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: theme.colorScheme.errorContainer,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: Icon(Icons.delete, color: theme.colorScheme.onErrorContainer),
      ),
      onDismissed: (_) async {
        if (l.id != null) await DatabaseService.instance.deleteLeave(l.id!);
        setState(() => _leaves.remove(l));
      },
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: l.isPlanned
              ? theme.colorScheme.tertiaryContainer
              : theme.colorScheme.secondaryContainer,
          child: Text(_fmtDays(l.amount),
              style: theme.textTheme.labelLarge),
        ),
        title: Text(df.format(l.date)),
        subtitle: Text(
            '${l.type.label}${l.memo != null && l.memo!.isNotEmpty ? ' · ${l.memo}' : ''}'),
        trailing: Chip(
          label: Text(l.isPlanned ? '예정' : '사용',
              style: theme.textTheme.labelSmall),
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
        ),
        onTap: () => _addOrEdit(existing: l),
      ),
    );
  }

  Future<void> _editTotal() async {
    final controllerText =
        TextEditingController(text: _fmtDays(_total));
    final result = await showDialog<double>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('총 연차 일수'),
        content: TextField(
          controller: controllerText,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(suffixText: '일'),
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('취소')),
          FilledButton(
            onPressed: () => Navigator.pop(
                context, double.tryParse(controllerText.text.trim())),
            child: const Text('저장'),
          ),
        ],
      ),
    );
    if (result != null && result >= 0) {
      await SettingsService.instance.setAnnualLeaveTotalFor(_year, result);
      await _load();
    }
  }

  Future<void> _addOrEdit({LeaveRecord? existing}) async {
    DateTime date = existing?.date ?? DateTime.now();
    LeaveType type = existing?.type ?? LeaveType.annual;
    final memoCtrl = TextEditingController(text: existing?.memo ?? '');
    final hoursCtrl = TextEditingController(
        text: existing?.hours != null ? _fmtDays(existing!.hours!) : '');

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheet) {
            String chipLabel(LeaveType t) => t == LeaveType.hourly
                ? t.label
                : '${t.label} (${_fmtDays(t.defaultAmount)})';
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(existing == null ? '연차 추가' : '연차 수정',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 16),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.calendar_today),
                    title: Text(DateFormat('yyyy년 M월 d일 (E)', 'ko').format(date)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: date,
                        firstDate: DateTime(_year - 1),
                        lastDate: DateTime(_year + 2, 12, 31),
                      );
                      if (picked != null) setSheet(() => date = picked);
                    },
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: LeaveType.values.map((t) {
                      return ChoiceChip(
                        label: Text(chipLabel(t)),
                        selected: type == t,
                        onSelected: (_) => setSheet(() => type = t),
                      );
                    }).toList(),
                  ),
                  if (type == LeaveType.hourly) ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: hoursCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      decoration: InputDecoration(
                        labelText: '사용 시간',
                        suffixText: '시간',
                        helperText:
                            '1일 = ${_fmtDays(_dailyWorkHours)}시간 기준으로 차감',
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: memoCtrl,
                    decoration: const InputDecoration(
                      labelText: '메모 (선택)',
                      hintText: '예: 가족 여행',
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(48)),
                      child: const Text('저장'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (saved == true) {
      double? hours;
      double amount;
      if (type == LeaveType.hourly) {
        hours = double.tryParse(hoursCtrl.text.trim());
        if (hours == null || hours <= 0) {
          _snack('사용 시간을 입력해 주세요.');
          return;
        }
        amount = _dailyWorkHours > 0 ? hours / _dailyWorkHours : 0;
      } else {
        amount = type.defaultAmount;
      }
      final record = LeaveRecord(
        id: existing?.id,
        date: date,
        type: type,
        amount: amount,
        hours: hours,
        memo: memoCtrl.text.trim().isEmpty ? null : memoCtrl.text.trim(),
      );
      if (existing == null) {
        await DatabaseService.instance.insertLeave(record);
      } else {
        await DatabaseService.instance.updateLeave(record);
      }
      _year = date.year; // 연도 보정
      await _load();
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}
