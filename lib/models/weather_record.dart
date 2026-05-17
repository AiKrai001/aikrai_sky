import 'caiyun_weather_response.dart';

/// 本地天气数据表的一条记录。
///
/// 当前阶段按需求只保存“请求原始返回数据”，不提前拆分实时、分钟级、小时级、
/// 天级和预警字段。这样可以最大限度保留彩云接口的完整结构，后续做 UI 时再按
/// 页面需要解析具体节点。
class WeatherRecord {
  const WeatherRecord({
    this.id,
    required this.addressId,
    required this.weatherDate,
    required this.rawResponse,
    required this.createdAt,
    required this.updatedAt,
  });

  /// SQLite 自增主键。
  final int? id;

  /// 关联第一步保存的地址表 id。
  final int addressId;

  /// 天气数据所属日期，格式为 yyyy-MM-dd。
  ///
  /// 该字段和 [addressId] 组成唯一键，用于实现“同一地址同一天只保留最新一次”。
  final String weatherDate;

  /// 彩云天气综合接口返回的原始 JSON 字符串。
  final String rawResponse;

  /// 该地址当天首次创建天气记录的时间。
  final DateTime createdAt;

  /// 该地址当天最近一次更新天气记录的时间。
  final DateTime updatedAt;

  static const tableName = 'weather_data';

  static const columnId = 'id';
  static const columnAddressId = 'address_id';
  static const columnWeatherDate = 'weather_date';
  static const columnRawResponse = 'raw_response';
  static const columnCreatedAt = 'created_at';
  static const columnUpdatedAt = 'updated_at';

  /// 将 DateTime 转为天气表按天查询使用的 yyyy-MM-dd 字符串。
  static String formatWeatherDate(DateTime dateTime) {
    final localTime = dateTime.toLocal();
    final year = localTime.year.toString().padLeft(4, '0');
    final month = localTime.month.toString().padLeft(2, '0');
    final day = localTime.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  /// 将保存的原始 JSON 解析为彩云天气响应模型。
  ///
  /// UI 或业务层可以通过该 getter 随时访问 `realtime`、`daily` 等节点。
  CaiyunWeatherResponse get weather {
    return CaiyunWeatherResponse.fromRawJson(rawResponse);
  }

  Map<String, Object?> toMap() {
    return {
      if (id != null) columnId: id,
      columnAddressId: addressId,
      columnWeatherDate: weatherDate,
      columnRawResponse: rawResponse,
      columnCreatedAt: createdAt.toIso8601String(),
      columnUpdatedAt: updatedAt.toIso8601String(),
    };
  }

  factory WeatherRecord.fromMap(Map<String, Object?> map) {
    return WeatherRecord(
      id: map[columnId] as int?,
      addressId: map[columnAddressId] as int,
      weatherDate: map[columnWeatherDate] as String,
      rawResponse: map[columnRawResponse] as String,
      createdAt: DateTime.parse(map[columnCreatedAt] as String),
      updatedAt: DateTime.parse(map[columnUpdatedAt] as String),
    );
  }
}
