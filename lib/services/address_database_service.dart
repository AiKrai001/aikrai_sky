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
  static const _databaseVersion = 5;

  /// App 状态表以 key-value 形式保存跨启动状态。
  ///
  /// 当前只需要记录“上一次真正定位到的位置 id”，后续如果要保存上次选中页、
  /// 刷新时间等，也可以继续复用这张表。
  static const _appStateTableName = 'app_state';
  static const _appStateColumnKey = 'key';
  static const _appStateColumnValue = 'value';
  static const _appStateColumnUpdatedAt = 'updated_at';
  static const _lastLocatedAddressIdKey = 'last_located_address_id';

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
      onConfigure: _configureDatabase,
      onCreate: _createDatabase,
      onUpgrade: _upgradeDatabase,
    );
    _database = openedDatabase;
    return openedDatabase;
  }

  /// 打开外键约束，让地址删除时关联天气数据的约束行为保持一致。
  Future<void> _configureDatabase(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  /// 创建地址表。
  ///
  /// 时间字段使用文本保存 ISO8601 时间，按字符串倒序即可得到最新记录。
  Future<void> _createDatabase(Database db, int version) async {
    await _createAddressTable(db);
    await _createWeatherDataTable(db);
    await _createAppStateTable(db);
  }

  /// 处理数据库升级。
  ///
  /// 处理旧版本升级。
  ///
  /// 当前开发阶段大结构变化仍可通过卸载重装处理；这里补充轻量列迁移，
  /// 方便开发机直接覆盖安装后继续调试位置排序。
  Future<void> _upgradeDatabase(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) {
      await _createWeatherDataTable(db);
    }
    if (oldVersion < 4) {
      await _addAddressSortOrderColumn(db);
    }
    if (oldVersion < 5) {
      await _createAppStateTable(db);
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
        ${AddressRecord.columnSortOrder} INTEGER NOT NULL,
        ${AddressRecord.columnCreatedAt} TEXT NOT NULL,
        ${AddressRecord.columnUpdatedAt} TEXT NOT NULL
      )
    ''');
  }

  /// v4 迁移：给地址表补充手动排序字段。
  Future<void> _addAddressSortOrderColumn(Database db) async {
    final columns = await db.rawQuery(
      'PRAGMA table_info(${AddressRecord.tableName})',
    );
    final hasSortOrderColumn = columns.any(
      (column) => column['name'] == AddressRecord.columnSortOrder,
    );
    if (hasSortOrderColumn) {
      return;
    }

    await db.execute('''
      ALTER TABLE ${AddressRecord.tableName}
      ADD COLUMN ${AddressRecord.columnSortOrder} INTEGER NOT NULL DEFAULT 0
    ''');
    await db.execute('''
      UPDATE ${AddressRecord.tableName}
      SET ${AddressRecord.columnSortOrder} = ${AddressRecord.columnId}
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

  /// 创建 App 状态表。
  Future<void> _createAppStateTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_appStateTableName (
        $_appStateColumnKey TEXT PRIMARY KEY,
        $_appStateColumnValue TEXT NOT NULL,
        $_appStateColumnUpdatedAt TEXT NOT NULL
      )
    ''');
  }

  /// 插入一条地址记录，并返回带自增主键的完整对象。
  Future<AddressRecord> insertAddress(AddressRecord address) async {
    final db = await database;
    final addressToInsert = address.sortOrder < 0
        ? address.copyWith(sortOrder: await _nextAddressSortOrder(db))
        : address;
    final id = await db.insert(
      AddressRecord.tableName,
      addressToInsert.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    return addressToInsert.copyWith(id: id);
  }

  /// 获取下一个排序值，让新位置默认追加到列表底部。
  Future<int> _nextAddressSortOrder(Database db) async {
    final rows = await db.rawQuery('''
      SELECT MAX(${AddressRecord.columnSortOrder}) AS max_sort_order
      FROM ${AddressRecord.tableName}
    ''');
    final maxSortOrder = Sqflite.firstIntValue(rows);
    return (maxSortOrder ?? -1) + 1;
  }

  /// 按区保存地址记录。
  ///
  /// 定位经纬度末尾会轻微漂移，所以这里不再用经纬度判断是否同一位置。
  /// 如果地址表里已经存在相同 [district]，保留原 id 和创建时间，只更新本次
  /// 定位得到的经纬度、省、市、区、详细地址和更新时间；如果不存在则插入新记录。
  Future<AddressRecord> upsertAddressByDistrict(AddressRecord address) async {
    final normalizedDistrict = address.district.trim();
    if (normalizedDistrict.isEmpty) {
      return insertAddress(address);
    }

    final existingAddress = await fetchAddressByDistrict(normalizedDistrict);
    if (existingAddress == null) {
      return insertAddress(address);
    }

    final updatedAddress = address.copyWith(
      id: existingAddress.id,
      createdAt: existingAddress.createdAt,
      sortOrder: existingAddress.sortOrder,
      updatedAt: DateTime.now(),
    );
    final values = updatedAddress.toMap()..remove(AddressRecord.columnId);
    final db = await database;
    await db.update(
      AddressRecord.tableName,
      values,
      where: '${AddressRecord.columnId} = ?',
      whereArgs: [existingAddress.id],
    );

    return updatedAddress;
  }

  /// 根据区查询已保存的地址记录。
  ///
  /// 旧版本可能已经保存了同一区的多条记录；这里取更新时间最新的一条更新，
  /// 不主动清理旧数据，避免影响已经关联的天气记录。
  Future<AddressRecord?> fetchAddressByDistrict(String district) async {
    final normalizedDistrict = district.trim();
    if (normalizedDistrict.isEmpty) {
      return null;
    }

    final db = await database;
    final rows = await db.query(
      AddressRecord.tableName,
      where: '${AddressRecord.columnDistrict} = ?',
      whereArgs: [normalizedDistrict],
      orderBy: '${AddressRecord.columnUpdatedAt} DESC',
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }
    return AddressRecord.fromMap(rows.first);
  }

  /// 根据经纬度查询已保存的地址记录。
  ///
  /// 该方法保留给调试或旧逻辑兼容；当前定位保存规则已改为按区更新/新增，
  /// 不再用经纬度末尾数字判断是否同一位置。
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
      orderBy: '${AddressRecord.columnUpdatedAt} DESC',
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
      orderBy: '${AddressRecord.columnUpdatedAt} DESC',
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }
    return AddressRecord.fromMap(rows.first);
  }

  /// 根据主键查询地址记录。
  Future<AddressRecord?> fetchAddressById(int addressId) async {
    final db = await database;
    final rows = await db.query(
      AddressRecord.tableName,
      where: '${AddressRecord.columnId} = ?',
      whereArgs: [addressId],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }
    return AddressRecord.fromMap(rows.first);
  }

  /// 保存上一次成功定位到的地址 id。
  Future<void> saveLastLocatedAddressId(int addressId) {
    return _setAppStateValue(
      key: _lastLocatedAddressIdKey,
      value: addressId.toString(),
    );
  }

  /// 读取上一次成功定位到的地址。
  ///
  /// 如果 app_state 中的 id 已经被删除，返回 null，让启动流程自然兜底到
  /// 地址表中的其他记录或空状态。
  Future<AddressRecord?> fetchLastLocatedAddress() async {
    final value = await _fetchAppStateValue(_lastLocatedAddressIdKey);
    final addressId = value == null ? null : int.tryParse(value);
    if (addressId == null) {
      return null;
    }
    return fetchAddressById(addressId);
  }

  /// 写入或更新一条 App 状态。
  Future<void> _setAppStateValue({
    required String key,
    required String value,
  }) async {
    final db = await database;
    await db.insert(_appStateTableName, {
      _appStateColumnKey: key,
      _appStateColumnValue: value,
      _appStateColumnUpdatedAt: DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// 读取一条 App 状态值。
  Future<String?> _fetchAppStateValue(String key) async {
    final db = await database;
    final rows = await db.query(
      _appStateTableName,
      columns: const [_appStateColumnValue],
      where: '$_appStateColumnKey = ?',
      whereArgs: [key],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }
    return rows.first[_appStateColumnValue] as String?;
  }

  /// 分页查询地址表记录。
  ///
  /// [date] 为空时查询全部地址；不为空时只查询该本地日期更新的地址记录。
  /// 数据按更新时间倒序返回，保证页面从新到旧展示。
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
      orderBy: '${AddressRecord.columnUpdatedAt} DESC',
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
      orderBy:
          '${AddressRecord.columnSortOrder} ASC, '
          '${AddressRecord.columnUpdatedAt} DESC',
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

  /// 按用户拖动后的顺序批量更新地址排序。
  Future<void> updateAddressSortOrders(List<AddressRecord> addresses) async {
    final db = await database;
    await db.transaction((txn) async {
      for (var index = 0; index < addresses.length; index += 1) {
        final addressId = addresses[index].id;
        if (addressId == null) {
          continue;
        }
        await txn.update(
          AddressRecord.tableName,
          {AddressRecord.columnSortOrder: index},
          where: '${AddressRecord.columnId} = ?',
          whereArgs: [addressId],
        );
      }
    });
  }

  /// 删除一个位置，并同步删除它关联的天气记录。
  Future<void> deleteAddressById(int addressId) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete(
        WeatherRecord.tableName,
        where: '${WeatherRecord.columnAddressId} = ?',
        whereArgs: [addressId],
      );
      await txn.delete(
        AddressRecord.tableName,
        where: '${AddressRecord.columnId} = ?',
        whereArgs: [addressId],
      );
      await txn.delete(
        _appStateTableName,
        where: '$_appStateColumnKey = ? AND $_appStateColumnValue = ?',
        whereArgs: [_lastLocatedAddressIdKey, addressId.toString()],
      );
    });
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

  /// 构造 updated_at 的日期范围查询条件。
  ///
  /// SQLite 中 updated_at 以 ISO8601 字符串保存，所以同一格式的起止时间可以
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
          '${AddressRecord.columnUpdatedAt} >= ? AND '
          '${AddressRecord.columnUpdatedAt} < ?',
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
