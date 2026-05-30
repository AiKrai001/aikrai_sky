import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/address_record.dart';
import '../models/weather_record.dart';
import 'address_database_service.dart';

/// 彩云天气综合接口服务。
///
/// 综合接口一次返回预警、实时、分钟级、小时级、天级和关键预报摘要，适合作为
/// 天气首页的基础数据源。当前阶段先保存完整原始 JSON，后续 UI 再按模块解析。
class CaiyunWeatherService {
  const CaiyunWeatherService({this.databaseService, http.Client? httpClient})
    : _httpClient = httpClient;

  /// 生产环境默认使用项目内置 token；后续发布版本建议改为后端代理或 dart-define。
  static const _token = String.fromEnvironment('CAIYUN_TOKEN');

  static final _baseUri = Uri.parse('https://api.caiyunapp.com');

  final AddressDatabaseService? databaseService;
  final http.Client? _httpClient;

  AddressDatabaseService get _database =>
      databaseService ?? AddressDatabaseService.instance;

  /// 根据地址记录的经纬度请求彩云综合天气，并按地址和日期保存最新原始数据。
  Future<WeatherRecord> fetchAndSaveWeather(AddressRecord address) async {
    final addressId = address.id;
    if (addressId == null) {
      throw const CaiyunWeatherException('地址记录缺少 id，无法关联保存天气数据。');
    }

    final now = DateTime.now();
    debugPrint(
      '[AiKraiSky][WeatherApi] 请求彩云天气：'
      'addressId=$addressId, lat=${address.latitude}, lng=${address.longitude}, '
      'district=${address.district}',
    );
    final rawResponse = await _fetchWeatherRawJson(address);

    return _database.upsertWeatherRecord(
      addressId: addressId,
      weatherDate: WeatherRecord.formatWeatherDate(now),
      rawResponse: rawResponse,
      now: now,
    );
  }

  /// 从本地天气表读取某个地址在某一天保存的天气数据。
  ///
  /// 返回的 [WeatherRecord] 可通过 `record.weather` 直接解析为
  /// [CaiyunWeatherResponse]，用于读取实时、预警、小时级和天级等数据。
  Future<WeatherRecord?> fetchSavedWeatherByDate({
    required int addressId,
    required DateTime date,
  }) {
    return _database.fetchWeatherByAddressIdAndDate(
      addressId: addressId,
      date: date,
    );
  }

  /// 调用彩云 v2.6 综合天气接口，并返回原始响应文本。
  Future<String> _fetchWeatherRawJson(AddressRecord address) async {
    final uri = _baseUri.replace(
      pathSegments: [
        'v2.6',
        _token,
        '${address.longitude},${address.latitude}',
        'weather',
      ],
      queryParameters: const {
        // 请求预警信息；综合接口默认还会包含 realtime/minutely/hourly/daily。
        'alert': 'true',
        // 天气首页先取 24 小时和 7 天数据，避免一次请求过大。
        'hourlysteps': '24',
        'dailysteps': '7',
        'lang': 'zh_CN',
        'unit': 'metric',
      },
    );

    final client = _httpClient ?? http.Client();
    final shouldCloseClient = _httpClient == null;

    try {
      final response = await client
          .get(uri)
          .timeout(const Duration(seconds: 15));
      debugPrint(
        '[AiKraiSky][WeatherApi] 彩云天气 HTTP 状态：'
        '${response.statusCode}, lat=${address.latitude}, lng=${address.longitude}',
      );
      if (response.statusCode != 200) {
        throw CaiyunWeatherException('彩云天气请求失败：HTTP ${response.statusCode}');
      }

      final decodedBody = jsonDecode(response.body);
      if (decodedBody is! Map<String, Object?>) {
        throw const CaiyunWeatherException('彩云天气返回数据不是 JSON 对象。');
      }

      final status = decodedBody['status'];
      if (status != 'ok') {
        throw CaiyunWeatherException('彩云天气返回状态异常：$status');
      }

      // 保存原始响应文本，确保后续页面可以完整访问所有字段。
      return response.body;
    } finally {
      if (shouldCloseClient) {
        client.close();
      }
    }
  }
}

/// 彩云天气请求与保存流程的业务异常。
class CaiyunWeatherException implements Exception {
  const CaiyunWeatherException(this.message);

  final String message;

  @override
  String toString() => message;
}
