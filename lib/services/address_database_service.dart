import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import '../models/address_record.dart';

/// 地址表 SQLite 访问服务。
///
/// 当前阶段只需要创建表、插入记录、读取最新记录。把数据库逻辑单独封装后，
/// 页面和定位服务都不需要关心 SQL 细节，后续扩展“历史地址列表”也更直接。
class AddressDatabaseService {
  AddressDatabaseService._();

  /// 单例实例，避免应用生命周期内重复打开多个数据库连接。
  static final AddressDatabaseService instance = AddressDatabaseService._();

  static const _databaseName = 'aikrai_sky.db';
  static const _databaseVersion = 1;

  Database? _database;

  /// 获取数据库连接；第一次调用时创建数据库和地址表。
  Future<Database> get database async {
    final existingDatabase = _database;
    if (existingDatabase != null) {
      return existingDatabase;
    }

    final databaseDirectory = await getDatabasesPath();
    final databasePath = path.join(databaseDirectory, _databaseName);

    final openedDatabase = await openDatabase(
      databasePath,
      version: _databaseVersion,
      onCreate: _createDatabase,
    );
    _database = openedDatabase;
    return openedDatabase;
  }

  /// 创建地址表。
  ///
  /// [created_at] 使用文本保存 ISO8601 时间，按字符串倒序即可得到最新记录。
  Future<void> _createDatabase(Database db, int version) async {
    await db.execute('''
      CREATE TABLE ${AddressRecord.tableName} (
        ${AddressRecord.columnId} INTEGER PRIMARY KEY AUTOINCREMENT,
        ${AddressRecord.columnLatitude} REAL NOT NULL,
        ${AddressRecord.columnLongitude} REAL NOT NULL,
        ${AddressRecord.columnProvince} TEXT NOT NULL,
        ${AddressRecord.columnCity} TEXT NOT NULL,
        ${AddressRecord.columnDistrict} TEXT NOT NULL,
        ${AddressRecord.columnDetailAddress} TEXT NOT NULL,
        ${AddressRecord.columnCreatedAt} TEXT NOT NULL
      )
    ''');
  }

  /// 插入一条地址记录，并返回带自增主键的完整对象。
  Future<AddressRecord> insertAddress(AddressRecord address) async {
    final db = await database;
    final id = await db.insert(
      AddressRecord.tableName,
      address.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    return address.copyWith(id: id);
  }

  /// 查询最新一条地址记录，用于 App 启动后展示当前已保存的位置。
  Future<AddressRecord?> fetchLatestAddress() async {
    final db = await database;
    final rows = await db.query(
      AddressRecord.tableName,
      orderBy: '${AddressRecord.columnCreatedAt} DESC',
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }
    return AddressRecord.fromMap(rows.first);
  }
}
