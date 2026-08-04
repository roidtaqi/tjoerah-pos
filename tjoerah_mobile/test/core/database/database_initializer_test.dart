import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:tjoerah_mobile/core/database/database_initializer.dart';

void main() {
  test('desktop database factory can open and query SQLite', () async {
    initializeDatabaseFactory();

    final database = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await db.execute(
            'CREATE TABLE catalog_probe (id INTEGER PRIMARY KEY, name TEXT)',
          );
        },
      ),
    );
    addTearDown(database.close);

    await database.insert('catalog_probe', {'name': 'Kopi Tjoerah'});
    final rows = await database.query('catalog_probe');

    expect(rows, [
      {'id': 1, 'name': 'Kopi Tjoerah'},
    ]);
  });
}
