import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../../../core/database/database_helper.dart';

class OfflineAttendanceAction {
  const OfflineAttendanceAction({
    required this.id,
    required this.action,
    required this.payload,
    required this.photoPath,
    required this.status,
  });

  factory OfflineAttendanceAction.fromRow(Map<String, dynamic> row) {
    return OfflineAttendanceAction(
      id: row['id'].toString(),
      action: row['action'].toString(),
      payload: Map<String, dynamic>.from(
        jsonDecode(row['payload'].toString()) as Map,
      ),
      photoPath: row['photo_path'].toString(),
      status: row['status']?.toString() ?? 'pending',
    );
  }

  final String id;
  final String action;
  final Map<String, dynamic> payload;
  final String photoPath;
  final String status;
}

class AttendanceOfflineQueue {
  Future<void> enqueue({
    required String id,
    required String action,
    required Map<String, dynamic> payload,
    required String photoPath,
  }) async {
    final directory = Directory(
      path.join(
        (await getApplicationDocumentsDirectory()).path,
        'attendance_queue',
      ),
    );
    await directory.create(recursive: true);
    final extension = path.extension(photoPath).isEmpty
        ? '.jpg'
        : path.extension(photoPath);
    final persistentPath = path.join(directory.path, '$id$extension');
    await File(photoPath).copy(persistentPath);

    final db = await DatabaseHelper.instance.database;
    await db.insert('offline_attendance_actions', {
      'id': id,
      'action': action,
      'payload': jsonEncode(payload),
      'photo_path': persistentPath,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'status': 'pending',
    });
  }

  Future<List<OfflineAttendanceAction>> pending() async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'offline_attendance_actions',
      where: 'status = ?',
      whereArgs: ['pending'],
      orderBy: 'created_at ASC',
    );
    return rows.map(OfflineAttendanceAction.fromRow).toList();
  }

  Future<int> pendingCount() async {
    final db = await DatabaseHelper.instance.database;
    final result = await db.rawQuery(
      "SELECT COUNT(*) AS total FROM offline_attendance_actions WHERE status = 'pending'",
    );
    return (result.first['total'] as num?)?.toInt() ?? 0;
  }

  Future<void> complete(OfflineAttendanceAction action) async {
    final db = await DatabaseHelper.instance.database;
    await db.delete(
      'offline_attendance_actions',
      where: 'id = ?',
      whereArgs: [action.id],
    );
    final photo = File(action.photoPath);
    if (await photo.exists()) await photo.delete();
  }

  Future<void> fail(OfflineAttendanceAction action, String message) async {
    final db = await DatabaseHelper.instance.database;
    await db.update(
      'offline_attendance_actions',
      {'status': 'failed', 'error_message': message},
      where: 'id = ?',
      whereArgs: [action.id],
    );
  }
}
