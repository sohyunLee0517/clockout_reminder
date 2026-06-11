import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/attendance_record.dart';
import '../services/database_service.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<AttendanceRecord> _records = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final records = await DatabaseService.instance.getAll(limit: 500);
    if (!mounted) return;
    setState(() {
      _records = records;
      _loading = false;
    });
  }

  Future<void> _confirmClear() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('전체 삭제'),
        content: const Text('모든 근태 기록을 삭제할까요? 되돌릴 수 없습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (yes == true) {
      await DatabaseService.instance.clearAll();
      await _load();
    }
  }

  /// 날짜별로 그룹핑.
  Map<String, List<AttendanceRecord>> get _grouped {
    final fmt = DateFormat('yyyy-MM-dd');
    final map = <String, List<AttendanceRecord>>{};
    for (final r in _records) {
      map.putIfAbsent(fmt.format(r.timestamp), () => []).add(r);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('근태 기록'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: '전체 삭제',
            onPressed: _records.isEmpty ? null : _confirmClear,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _records.isEmpty
              ? Center(
                  child: Text('기록이 없습니다.',
                      style: theme.textTheme.bodyLarge
                          ?.copyWith(color: theme.disabledColor)),
                )
              : ListView(
                  children: _grouped.entries.map((entry) {
                    return _dayGroup(theme, entry.key, entry.value);
                  }).toList(),
                ),
    );
  }

  Widget _dayGroup(
      ThemeData theme, String dateKey, List<AttendanceRecord> items) {
    final date = DateTime.parse(dateKey);
    final header = DateFormat('M월 d일 (E)', 'ko').format(date);
    final timeFmt = DateFormat('a h:mm', 'ko');

    final checkIn =
        items.where((r) => r.type == AttendanceType.checkIn).firstOrNull;
    final checkOut =
        items.where((r) => r.type == AttendanceType.checkOut).firstOrNull;
    String? worked;
    if (checkIn != null && checkOut != null) {
      final d = checkOut.timestamp.difference(checkIn.timestamp);
      if (!d.isNegative) {
        worked = '${d.inHours}시간 ${d.inMinutes % 60}분 근무';
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(header,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              if (worked != null)
                Text(worked,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.primary)),
            ],
          ),
        ),
        ...items.map((r) => Dismissible(
              key: ValueKey(r.id),
              direction: DismissDirection.endToStart,
              background: Container(
                color: theme.colorScheme.errorContainer,
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 24),
                child: Icon(Icons.delete,
                    color: theme.colorScheme.onErrorContainer),
              ),
              onDismissed: (_) async {
                if (r.id != null) {
                  await DatabaseService.instance.delete(r.id!);
                }
                setState(() => _records.remove(r));
              },
              child: ListTile(
                leading: Icon(
                  r.type == AttendanceType.checkIn
                      ? Icons.login
                      : Icons.logout,
                  color: r.type == AttendanceType.checkIn
                      ? theme.colorScheme.primary
                      : theme.colorScheme.tertiary,
                ),
                title: Text('${r.type.label} · ${r.trigger.label}'),
                subtitle: Text(timeFmt.format(r.timestamp)),
              ),
            )),
        const Divider(height: 1),
      ],
    );
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
