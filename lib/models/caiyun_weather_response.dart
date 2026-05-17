import 'dart:convert';

/// 彩云天气 v2.6 综合接口响应模型。
///
/// 综合接口返回的子结构很多，且不同能力模块会继续演进。这里将顶层字段和常用
/// `result` 字段做成强类型，复杂子节点保留为 Map，后续 UI 需要展示实时天气、
/// 预警、分钟级、小时级或天级数据时，可以继续在对应 Map 上细化模型。
class CaiyunWeatherResponse {
  const CaiyunWeatherResponse({
    required this.status,
    required this.apiVersion,
    required this.apiStatus,
    required this.lang,
    required this.unit,
    required this.tzshift,
    required this.timezone,
    required this.serverTime,
    required this.location,
    required this.result,
    required this.rawJson,
  });

  /// 返回状态，成功时通常为 ok。
  final String status;

  /// API 版本，例如 v2.6。
  final String apiVersion;

  /// API 状态，例如 alpha。
  final String apiStatus;

  /// 返回语言，例如 zh_CN。
  final String lang;

  /// 单位制，例如 metric。
  final String unit;

  /// 时区偏移秒数。
  final int tzshift;

  /// 时区名称，例如 Asia/Shanghai。
  final String timezone;

  /// 服务端时间戳，单位为秒。
  final int serverTime;

  /// 接口返回的位置数组，文档示例为 [纬度, 经度]。
  final List<double> location;

  /// 综合天气结果主体。
  final CaiyunWeatherResult result;

  /// 原始 JSON Map，保留所有接口字段，避免模型未覆盖字段丢失。
  final Map<String, Object?> rawJson;

  /// 从数据库保存的原始 JSON 字符串解析为响应模型。
  factory CaiyunWeatherResponse.fromRawJson(String rawJsonText) {
    final decodedJson = jsonDecode(rawJsonText);
    if (decodedJson is! Map<String, Object?>) {
      throw const FormatException('彩云天气原始数据不是 JSON 对象。');
    }
    return CaiyunWeatherResponse.fromJson(decodedJson);
  }

  /// 从 JSON Map 解析响应模型。
  factory CaiyunWeatherResponse.fromJson(Map<String, Object?> json) {
    return CaiyunWeatherResponse(
      status: _readString(json, 'status'),
      apiVersion: _readString(json, 'api_version'),
      apiStatus: _readString(json, 'api_status'),
      lang: _readString(json, 'lang'),
      unit: _readString(json, 'unit'),
      tzshift: _readInt(json, 'tzshift'),
      timezone: _readString(json, 'timezone'),
      serverTime: _readInt(json, 'server_time'),
      location: _readDoubleList(json, 'location'),
      result: CaiyunWeatherResult.fromJson(_readMap(json, 'result')),
      rawJson: json,
    );
  }
}

/// 彩云天气综合接口 result 节点。
///
/// [alert]、[realtime]、[minutely]、[hourly]、[daily] 分别对应预警、实时、
/// 分钟级、小时级和天级数据；先保留 Map 结构，便于直接读取文档中的原始字段。
class CaiyunWeatherResult {
  const CaiyunWeatherResult({
    required this.alert,
    required this.realtime,
    required this.minutely,
    required this.hourly,
    required this.daily,
    required this.primary,
    required this.forecastKeypoint,
    required this.rawJson,
  });

  /// 预警信息。
  final Map<String, Object?> alert;

  /// 实时天气数据。
  final Map<String, Object?> realtime;

  /// 分钟级降水数据。
  final Map<String, Object?> minutely;

  /// 小时级天气数据。
  final Map<String, Object?> hourly;

  /// 天级天气数据。
  final Map<String, Object?> daily;

  /// 主要数据标识。
  final int primary;

  /// 天气预报关键点，例如“未来两小时不会下雨，放心出门吧”。
  final String forecastKeypoint;

  /// result 原始 JSON Map。
  final Map<String, Object?> rawJson;

  factory CaiyunWeatherResult.fromJson(Map<String, Object?> json) {
    return CaiyunWeatherResult(
      alert: _readMap(json, 'alert'),
      realtime: _readMap(json, 'realtime'),
      minutely: _readMap(json, 'minutely'),
      hourly: _readMap(json, 'hourly'),
      daily: _readMap(json, 'daily'),
      primary: _readInt(json, 'primary'),
      forecastKeypoint: _readString(json, 'forecast_keypoint'),
      rawJson: json,
    );
  }
}

String _readString(Map<String, Object?> json, String key) {
  final value = json[key];
  return value is String ? value : '';
}

int _readInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return 0;
}

List<double> _readDoubleList(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! List<Object?>) {
    return const [];
  }
  return [
    for (final item in value)
      if (item is num) item.toDouble(),
  ];
}

Map<String, Object?> _readMap(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return const {};
}
