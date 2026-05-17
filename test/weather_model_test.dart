import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:aikrai_sky/models/caiyun_weather_response.dart';
import 'package:aikrai_sky/models/weather_record.dart';

void main() {
  test('CaiyunWeatherResponse parses common weather nodes', () {
    final rawJson = jsonEncode({
      'status': 'ok',
      'api_version': 'v2.6',
      'api_status': 'alpha',
      'lang': 'zh_CN',
      'unit': 'metric',
      'tzshift': 28800,
      'timezone': 'Asia/Shanghai',
      'server_time': 1640758065,
      'location': [31.2646, 121.5051],
      'result': {
        'alert': {'status': 'ok'},
        'realtime': {'temperature': 20.5, 'skycon': 'CLEAR_DAY'},
        'minutely': {'description': '未来两小时不会下雨'},
        'hourly': {'description': '未来 24 小时晴'},
        'daily': {'status': 'ok'},
        'primary': 0,
        'forecast_keypoint': '未来两小时不会下雨，放心出门吧',
      },
    });

    final response = CaiyunWeatherResponse.fromRawJson(rawJson);

    expect(response.status, 'ok');
    expect(response.apiVersion, 'v2.6');
    expect(response.location, [31.2646, 121.5051]);
    expect(response.result.forecastKeypoint, '未来两小时不会下雨，放心出门吧');
    expect(response.result.realtime['skycon'], 'CLEAR_DAY');
  });

  test('WeatherRecord exposes parsed Caiyun weather response', () {
    final record = WeatherRecord(
      addressId: 1,
      weatherDate: '2026-05-17',
      rawResponse: jsonEncode({
        'status': 'ok',
        'api_version': 'v2.6',
        'api_status': 'alpha',
        'lang': 'zh_CN',
        'unit': 'metric',
        'tzshift': 28800,
        'timezone': 'Asia/Shanghai',
        'server_time': 1640758065,
        'location': [31.2646, 121.5051],
        'result': {
          'alert': {},
          'realtime': {},
          'minutely': {},
          'hourly': {},
          'daily': {},
          'primary': 0,
          'forecast_keypoint': '测试天气摘要',
        },
      }),
      createdAt: DateTime(2026, 5, 17, 10),
      updatedAt: DateTime(2026, 5, 17, 11),
    );

    expect(record.weather.result.forecastKeypoint, '测试天气摘要');
  });

  test('WeatherRecord formats DateTime as local weather date', () {
    final weatherDate = WeatherRecord.formatWeatherDate(
      DateTime(2026, 5, 7, 9, 30),
    );

    expect(weatherDate, '2026-05-07');
  });
}