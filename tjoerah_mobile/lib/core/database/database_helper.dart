import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('tjoerah_pos.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 4,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Version 1 was an early incompatible prototype cache.
      await db.execute('DROP TABLE IF EXISTS table_sessions');
      await db.execute('DROP TABLE IF EXISTS dining_tables');
      await db.execute('DROP TABLE IF EXISTS floors');
      await db.execute('DROP TABLE IF EXISTS offline_inventory_incidents');
      await db.execute('DROP TABLE IF EXISTS recipe_items');
      await db.execute('DROP TABLE IF EXISTS recipes');
      await db.execute('DROP TABLE IF EXISTS inventory_items');
      await db.execute('DROP TABLE IF EXISTS offline_orders');
      await db.execute('DROP TABLE IF EXISTS products');
      await db.execute('DROP TABLE IF EXISTS categories');
      await _createDB(db, newVersion);
      return;
    }

    if (oldVersion < 3) await _createCustomersTable(db);
    if (oldVersion < 4) {
      await db.execute('ALTER TABLE products ADD COLUMN station TEXT');
    }
  }

  Future<void> _createDB(Database db, int version) async {
    // Categories Table
    await db.execute('''
      CREATE TABLE categories (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        sort_order INTEGER DEFAULT 0
      )
    ''');

    // Products Table
    await db.execute('''
      CREATE TABLE products (
        id TEXT PRIMARY KEY,
        category_id TEXT NOT NULL,
        name TEXT NOT NULL,
        sku TEXT,
        price REAL NOT NULL,
        is_active INTEGER DEFAULT 1,
        station TEXT,
        FOREIGN KEY (category_id) REFERENCES categories (id) ON DELETE CASCADE
      )
    ''');

    // Offline Orders Queue Table
    await db.execute('''
      CREATE TABLE offline_orders (
        id TEXT PRIMARY KEY,
        payload TEXT NOT NULL,
        created_at TEXT NOT NULL,
        status TEXT DEFAULT 'pending'
      )
    ''');

    // Inventory Items Table
    await db.execute('''
      CREATE TABLE inventory_items (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        sku TEXT,
        unit TEXT,
        current_stock REAL DEFAULT 0,
        weighted_average_cost REAL DEFAULT 0,
        is_active INTEGER DEFAULT 1
      )
    ''');

    // Recipes Table
    await db.execute('''
      CREATE TABLE recipes (
        id TEXT PRIMARY KEY,
        product_id TEXT,
        name TEXT NOT NULL,
        current_cost REAL DEFAULT 0,
        yield_quantity REAL DEFAULT 1,
        yield_unit TEXT,
        is_synced INTEGER DEFAULT 1
      )
    ''');

    // Recipe Items Table
    await db.execute('''
      CREATE TABLE recipe_items (
        id TEXT PRIMARY KEY,
        recipe_id TEXT NOT NULL,
        inventory_item_id TEXT,
        child_recipe_id TEXT,
        quantity REAL NOT NULL,
        unit TEXT,
        waste_percent REAL DEFAULT 0,
        unit_cost REAL DEFAULT 0,
        total_cost REAL DEFAULT 0,
        FOREIGN KEY (recipe_id) REFERENCES recipes (id) ON DELETE CASCADE
      )
    ''');

    // Offline Inventory Incidents (Adjustments / Wastage)
    await db.execute('''
      CREATE TABLE offline_inventory_incidents (
        id TEXT PRIMARY KEY,
        type TEXT NOT NULL,
        payload TEXT NOT NULL,
        created_at TEXT NOT NULL,
        status TEXT DEFAULT 'pending'
      )
    ''');

    // Floors Table
    await db.execute('''
      CREATE TABLE floors (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        sort_order INTEGER DEFAULT 0
      )
    ''');

    // Dining Tables Table
    await db.execute('''
      CREATE TABLE dining_tables (
        id TEXT PRIMARY KEY,
        floor_id TEXT,
        name TEXT NOT NULL,
        capacity INTEGER DEFAULT 1,
        status TEXT DEFAULT 'available',
        position_x REAL DEFAULT 0,
        position_y REAL DEFAULT 0
      )
    ''');

    // Table Sessions
    await db.execute('''
      CREATE TABLE table_sessions (
        id TEXT PRIMARY KEY,
        table_id TEXT NOT NULL,
        order_id TEXT,
        status TEXT DEFAULT 'open',
        opened_at TEXT NOT NULL,
        closed_at TEXT,
        merged_to_session_id TEXT
      )
    ''');

    await _createCustomersTable(db);
  }

  Future<void> _createCustomersTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS customers (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        phone TEXT,
        email TEXT,
        birthday TEXT,
        notes TEXT,
        total_spent REAL DEFAULT 0,
        visit_count INTEGER DEFAULT 0,
        last_purchase_at TEXT,
        is_synced INTEGER DEFAULT 1,
        updated_at TEXT NOT NULL
      )
    ''');
  }

  Future<void> clearCatalog() async {
    final db = await instance.database;
    await db.delete('products');
    await db.delete('categories');
    await db.delete('inventory_items');
    await db.delete('recipes');
    await db.delete('recipe_items');
    await db.delete('floors');
    await db.delete('dining_tables');
    await db.delete('table_sessions');
  }

  Future<Map<String, dynamic>> getShiftReport(DateTime date) async {
    final db = await instance.database;
    final startOfDay = DateTime(
      date.year,
      date.month,
      date.day,
    ).toIso8601String();
    final endOfDay = DateTime(
      date.year,
      date.month,
      date.day,
      23,
      59,
      59,
    ).toIso8601String();

    // Sum totals using JSON1 extension
    final salesResult = await db.rawQuery(
      '''
      SELECT 
        COUNT(id) as total_orders,
        SUM(CAST(json_extract(payload, '\$.total') AS REAL)) as total_revenue
      FROM offline_orders
      WHERE created_at >= ? AND created_at <= ?
    ''',
      [startOfDay, endOfDay],
    );

    // Payment method breakdown
    final methodsResult = await db.rawQuery(
      '''
      SELECT 
        json_extract(payload, '\$.paymentMethod') as payment_method,
        SUM(CAST(json_extract(payload, '\$.total') AS REAL)) as amount
      FROM offline_orders
      WHERE created_at >= ? AND created_at <= ?
      GROUP BY payment_method
    ''',
      [startOfDay, endOfDay],
    );

    final totalOrders = Sqflite.firstIntValue(salesResult) ?? 0;
    final totalRevenue =
        (salesResult.first['total_revenue'] as num?)?.toDouble() ?? 0.0;

    final Map<String, double> paymentBreakdown = {};
    for (var row in methodsResult) {
      final method = row['payment_method'] as String? ?? 'unknown';
      final amount = (row['amount'] as num?)?.toDouble() ?? 0.0;
      paymentBreakdown[method] = amount;
    }

    return {
      'total_orders': totalOrders,
      'total_revenue': totalRevenue,
      'payment_breakdown': paymentBreakdown,
    };
  }
}
