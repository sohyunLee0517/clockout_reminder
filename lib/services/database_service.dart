import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/attendance_record.dart';

/// 근태 기록을 sqflite 로컬 DB에 저장/조회한다.
class DatabaseService {
  DatabaseService._();
  static final DatabaseService instance = DatabaseService._();

  static const _dbName = 'attendance.db';
  static const _table = 'records';
  Database? _db;

  Future<Database> get _database async {
    if (_db != null) return _db!;
    _db = await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dir = await getDatabasesPath();
    final path = p.join(dir, _dbName);
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $_table (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            type TEXT NOT NULL,
            trigger TEXT NOT NULL,
            timestamp INTEGER NOT NULL,
            latitude REAL,
            longitude REAL,
            memo TEXT
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_timestamp ON $_table (timestamp DESC)',
        );
      },
    );
  }

  Future<int> insert(AttendanceRecord record) async {
    final db = await _database;
    final map = record.toMap()..remove('id');
    return db.insert(_table, map);
  }

  /// 최신순으로 기록을 가져온다.
  Future<List<AttendanceRecord>> getAll({int? limit}) async {
    final db = await _database;
    final rows = await db.query(
      _table,
      orderBy: 'timestamp DESC',
      limit: limit,
    );
    return rows.map(AttendanceRecord.fromMap).toList();
  }

  /// 특정 날짜(0시~24시) 범위의 기록.
  Future<List<AttendanceRecord>> getByDate(DateTime day) async {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    final db = await _database;
    final rows = await db.query(
      _table,
      where: 'timestamp >= ? AND timestamp < ?',
      whereArgs: [start.millisecondsSinceEpoch, end.millisecondsSinceEpoch],
      orderBy: 'timestamp DESC',
    );
    return rows.map(AttendanceRecord.fromMap).toList();
  }

  /// 오늘 이미 퇴근 체크를 했는지 여부.
  Future<bool> hasCheckedOutToday() async {
    final today = await getByDate(DateTime.now());
    return today.any((r) => r.type == AttendanceType.checkOut);
  }

  Future<AttendanceRecord?> latest() async {
    final all = await getAll(limit: 1);
    return all.isEmpty ? null : all.first;
  }

  Future<void> delete(int id) async {
    final db = await _database;
    await db.delete(_table, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> clearAll() async {
    final db = await _database;
    await db.delete(_table);
  }
}
