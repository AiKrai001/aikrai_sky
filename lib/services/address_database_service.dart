import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import '../models/address_record.dart';
import '../models/weather_record.dart';

/// 地址表 SQLite 访问服务。
///
/// 当前阶段只需要创建表、插入记录、读取最新记录。把数据库逻辑单独封装后，
/// 页面和定位服务都不需要关心 SQL 细节，后续扩展“历史地址列表”也更直接。
class AddressDatabaseService {
  AddressDatabaseService._();

  /// 单例实例，避免应用生命周期内重复打开多个数据库连接。
  static final AddressDatabaseService instance = AddressDatabaseService._();

  static const _databaseName = 'aikrai_sky.db';
  static const _databaseVersion = 2;

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
      onUpgrade: _upgradeDatabase,
    );
    _database = openedDatabase;
    return openedDatabase;
  }

  /// 创建地址表。
  ///
  /// [created_at] 使用文本保存 ISO8601 时间，按字符串倒序即可得到最新记录。
  Future<void> _createDatabase(Database db, int version) async {
    await _createAddressTable(db);
    await _createWeatherDataTable(db);
  }

  /// 处理数据库升级。
  ///
  /// v1 只有地址表；v2 新增天气数据表，不影响已有地址记录。
  Future<void> _upgradeDatabase(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) {
      await _createWeatherDataTable(db);
    }
  }

  /// 创建地址表。
  Future<void> _createAddressTable(Database db) async {
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

  /// 创建天气数据表。
  ///
  /// [address_id] 关联地址表；[weather_date] 用于按天归档。同一个地址同一天
  /// 重复请求时通过唯一索引更新原始返回数据，而不是插入多条历史数据。
  Future<void> _createWeatherDataTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${WeatherRecord.tableName} (
        ${WeatherRecord.columnId} INTEGER PRIMARY KEY AUTOINCREMENT,
        ${WeatherRecord.columnAddressId} INTEGER NOT NULL,
        ${WeatherRecord.columnWeatherDate} TEXT NOT NULL,
        ${WeatherRecord.columnRawResponse} TEXT NOT NULL,
        ${WeatherRecord.columnCreatedAt} TEXT NOT NULL,
        ${WeatherRecord.columnUpdatedAt} TEXT NOT NULL,
        FOREIGN KEY (${WeatherRecord.columnAddressId})
          REFERENCES ${AddressRecord.tableName} (${AddressRecord.columnId})
          ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_weather_data_address_date
      ON ${WeatherRecord.tableName} (
        ${WeatherRecord.columnAddressId},
        ${WeatherRecord.columnWeatherDate}
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

  /// 根据经纬度查询已保存的地址记录。
  ///
  /// 这里按需求判断“相同经纬度”才复用旧记录，因此使用数据库中保存的 double
  /// 值做精确匹配，不做距离近似或小数截断。
  Future<AddressRecord?> fetchAddressByCoordinates({
    required double latitude,
    required double longitude,
  }) async {
    final db = await database;
    final rows = await db.query(
      AddressRecord.tableName,
      where:
          '${AddressRecord.columnLatitude} = ? AND '
          '${AddressRecord.columnLongitude} = ?',
      whereArgs: [latitude, longitude],
      orderBy: '${AddressRecord.columnCreatedAt} DESC',
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }
    return AddressRecord.fromMap(rows.first);
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

  /// 分页查询地址表记录。
  ///
  /// [date] 为空时查询全部地址；不为空时只查询该本地日期创建的地址记录。
  /// 数据按创建时间倒序返回，保证页面从新到旧展示。
  Future<List<AddressRecord>> fetchAddressRecords({
    DateTime? date,
    required int limit,
    required int offset,
  }) async {
    final db = await database;
    final dateRange = _buildDateRange(date);
    final rows = await db.query(
      AddressRecord.tableName,
      where: dateRange?.whereClause,
      whereArgs: dateRange?.whereArgs,
      orderBy: '${AddressRecord.columnCreatedAt} DESC',
      limit: limit,
      offset: offset,
    );

    return rows.map(AddressRecord.fromMap).toList();
  }

  /// 查询地址表全部记录。
  ///
  /// 首页顶部位置切换需要一次性拿到所有已保存位置，圆点数量和左右滑动页数
  /// 都直接由这里的记录数决定。
  Future<List<AddressRecord>> fetchAllAddressRecords() async {
    final db = await database;
    final rows = await db.query(
      AddressRecord.tableName,
      orderBy: '${AddressRecord.columnCreatedAt} DESC',
    );

    return rows.map(AddressRecord.fromMap).toList();
  }

  /// 统计地址表记录数，用于计算分页按钮状态。
  Future<int> countAddressRecords({DateTime? date}) async {
    final db = await database;
    final dateRange = _buildDateRange(date);
    final rows = await db.rawQuery('''
      SELECT COUNT(*) AS total
      FROM ${AddressRecord.tableName}
      ${dateRange == null ? '' : 'WHERE ${dateRange.whereClause}'}
      ''', dateRange?.whereArgs);

    return Sqflite.firstIntValue(rows) ?? 0;
  }

  /// 按“地址 id + 日期”保存天气原始数据。
  ///
  /// 如果同一个地址当天已经保存过天气数据，只更新 [rawResponse] 和 [updatedAt]；
  /// 如果没有保存过，则插入新记录并设置创建时间。
  Future<WeatherRecord> upsertWeatherRecord({
    required int addressId,
    required String weatherDate,
    required String rawResponse,
    required DateTime now,
  }) async {
    final db = await database;

    final existingRows = await db.query(
      WeatherRecord.tableName,
      where:
          '${WeatherRecord.columnAddressId} = ? AND '
          '${WeatherRecord.columnWeatherDate} = ?',
      whereArgs: [addressId, weatherDate],
      limit: 1,
    );

    if (existingRows.isEmpty) {
      final newRecord = WeatherRecord(
        addressId: addressId,
        weatherDate: weatherDate,
        rawResponse: rawResponse,
        createdAt: now,
        updatedAt: now,
      );
      final id = await db.insert(WeatherRecord.tableName, newRecord.toMap());

      return WeatherRecord.fromMap({
        ...newRecord.toMap(),
        WeatherRecord.columnId: id,
      });
    }

    final existingRecord = WeatherRecord.fromMap(existingRows.first);
    final updatedRecord = WeatherRecord(
      id: existingRecord.id,
      addressId: existingRecord.addressId,
      weatherDate: existingRecord.weatherDate,
      rawResponse: rawResponse,
      createdAt: existingRecord.createdAt,
      updatedAt: now,
    );

    await db.update(
      WeatherRecord.tableName,
      updatedRecord.toMap(),
      where: '${WeatherRecord.columnId} = ?',
      whereArgs: [existingRecord.id],
    );

    return updatedRecord;
  }

  /// 查询某个地址最新保存的一条天气数据，用于 UI 展示保存状态。
  Future<WeatherRecord?> fetchLatestWeatherByAddressId(int addressId) async {
    final db = await database;
    final rows = await db.query(
      WeatherRecord.tableName,
      where: '${WeatherRecord.columnAddressId} = ?',
      whereArgs: [addressId],
      orderBy: '${WeatherRecord.columnUpdatedAt} DESC',
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }
    return WeatherRecord.fromMap(rows.first);
  }

  /// 分页查询天气数据表记录。
  ///
  /// [date] 为空时查询全部天气数据；不为空时按 [weather_date] 查询指定日期。
  /// 数据按更新时间倒序返回，保证同一天重复更新后的记录排在前面。
  Future<List<WeatherRecord>> fetchWeatherRecords({
    DateTime? date,
    required int limit,
    required int offset,
  }) async {
    final db = await database;
    final weatherDate = date == null
        ? null
        : WeatherRecord.formatWeatherDate(date);
    final rows = await db.query(
      WeatherRecord.tableName,
      where: weatherDate == null
          ? null
          : '${WeatherRecord.columnWeatherDate} = ?',
      whereArgs: weatherDate == null ? null : [weatherDate],
      orderBy: '${WeatherRecord.columnUpdatedAt} DESC',
      limit: limit,
      offset: offset,
    );

    return rows.map(WeatherRecord.fromMap).toList();
  }

  /// 统计天气数据表记录数，用于计算分页按钮状态。
  Future<int> countWeatherRecords({DateTime? date}) async {
    final db = await database;
    final weatherDate = date == null
        ? null
        : WeatherRecord.formatWeatherDate(date);
    final rows = await db.rawQuery('''
      SELECT COUNT(*) AS total
      FROM ${WeatherRecord.tableName}
      ${weatherDate == null ? '' : 'WHERE ${WeatherRecord.columnWeatherDate} = ?'}
      ''', weatherDate == null ? null : [weatherDate]);

    return Sqflite.firstIntValue(rows) ?? 0;
  }

  /// 查询某个地址在指定日期保存的天气数据。
  ///
  /// [date] 会按本地时区格式化为 yyyy-MM-dd，对应天气表中的 [weather_date]。
  Future<WeatherRecord?> fetchWeatherByAddressIdAndDate({
    required int addressId,
    required DateTime date,
  }) {
    return fetchWeatherByAddressIdAndWeatherDate(
      addressId: addressId,
      weatherDate: WeatherRecord.formatWeatherDate(date),
    );
  }

  /// 查询某个地址在指定 yyyy-MM-dd 日期保存的天气数据。
  ///
  /// 当调用方已经从路由、筛选器或数据库中拿到日期字符串时，可以直接使用该方法。
  Future<WeatherRecord?> fetchWeatherByAddressIdAndWeatherDate({
    required int addressId,
    required String weatherDate,
  }) async {
    final db = await database;
    final rows = await db.query(
      WeatherRecord.tableName,
      where:
          '${WeatherRecord.columnAddressId} = ? AND '
          '${WeatherRecord.columnWeatherDate} = ?',
      whereArgs: [addressId, weatherDate],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }
    return WeatherRecord.fromMap(rows.first);
  }

  /// 构造 created_at 的日期范围查询条件。
  ///
  /// SQLite 中 created_at 以 ISO8601 字符串保存，所以同一格式的起止时间可以
  /// 直接做字符串范围比较，查询某日 00:00:00 到次日 00:00:00 前的记录。
  _DateRangeQuery? _buildDateRange(DateTime? date) {
    if (date == null) {
      return null;
    }

    final localDate = date.toLocal();
    final start = DateTime(localDate.year, localDate.month, localDate.day);
    final end = start.add(const Duration(days: 1));

    return _DateRangeQuery(
      whereClause:
          '${AddressRecord.columnCreatedAt} >= ? AND '
          '${AddressRecord.columnCreatedAt} < ?',
      whereArgs: [start.toIso8601String(), end.toIso8601String()],
    );
  }
}

/// 数据库日期范围查询条件。
///
/// 用小对象承载 where 和 whereArgs，可以避免分页查询和计数查询重复拼接条件。
class _DateRangeQuery {
  const _DateRangeQuery({required this.whereClause, required this.whereArgs});

  final String whereClause;
  final List<Object?> whereArgs;
}
