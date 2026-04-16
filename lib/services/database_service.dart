import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseService {
  static Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDB();
    return _db!;
  }

  Future<Database> _initDB() async {
    String path = join(await getDatabasesPath(), 'offlinemaps.db');
    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE saved_locations (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT,
            lat REAL,
            lng REAL,6
            address TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE trip_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            distance REAL,
            duration REAL,
            date TEXT
          )
        ''');
      },
    );
  }
}
