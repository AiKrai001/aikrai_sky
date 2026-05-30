import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:aikrai_sky/models/address_record.dart';
import 'package:aikrai_sky/models/caiyun_weather_response.dart';
import 'package:aikrai_sky/models/weather_display_data.dart';
import 'package:aikrai_sky/models/weather_record.dart';

void main() {
  test(
    'AddressRecord copyWith keeps identity while replacing address fields',
    () {
      final createdAt = DateTime(2026, 5, 24, 9);
      final original = AddressRecord(
        id: 7,
        latitude: 31.2646001,
        longitude: 121.5051001,
        province: '上海市',
        city: '上海市',
        district: '虹口区',
        detailAddress: '上海市虹口区旧地址',
        sortOrder: 0,
        createdAt: createdAt,
        updatedAt: createdAt,
      );

      final updated = original.copyWith(
        latitude: 31.2646999,
        longitude: 121.5051999,
        detailAddress: '上海市虹口区新地址',
      );

      expect(updated.id, 7);
      expect(updated.createdAt, createdAt);
      expect(updated.updatedAt, createdAt);
      expect(updated.district, '虹口区');
      expect(updated.latitude, 31.2646999);
      expect(updated.longitude, 121.5051999);
      expect(updated.detailAddress, '上海市虹口区新地址');
    },
  );

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

  test('WeatherBackgroundStyle keeps non-rain weather sky blue', () {
    final cloudy = WeatherBackgroundStyle.fromSkycon('CLOUDY');
    final snow = WeatherBackgroundStyle.fromSkycon('LIGHT_SNOW');
    final rain = WeatherBackgroundStyle.fromSkycon('MODERATE_RAIN');

    expect(cloudy.topColor, 0xFF4DA1D9);
    expect(cloudy.bottomColor, 0xFF226A9A);
    expect(cloudy.showRain, isFalse);
    expect(snow.topColor, 0xFF4DA1D9);
    expect(snow.showRain, isFalse);
    expect(rain.showRain, isFalse);
  });

  test(
    'WeatherDisplayData keeps hourly local time and aligns skycon by datetime',
    () {
      final rawResponse = jsonEncode({
        'status': 'ok',
        'api_version': 'v2.6',
        'api_status': 'active',
        'lang': 'zh_CN',
        'unit': 'metric',
        'tzshift': 28800,
        'timezone': 'Asia/Shanghai',
        'server_time': 1779520027,
        'location': [31.2646, 121.5051],
        'result': {
          'alert': {},
          'realtime': {
            'temperature': 26.6,
            'skycon': 'PARTLY_CLOUDY_DAY',
            'humidity': 0.74,
            'wind': {'direction': 90, 'speed': 8},
          },
          'minutely': {},
          'hourly': {
            'temperature': [
              {'datetime': '2026-05-23T15:00+08:00', 'value': 26.68},
              {'datetime': '2026-05-23T16:00+08:00', 'value': 25.0},
            ],
            // 故意反序，验证图标按 datetime 对齐，而不是按数组下标硬配。
            'skycon': [
              {'datetime': '2026-05-23T16:00+08:00', 'value': 'CLOUDY'},
              {
                'datetime': '2026-05-23T15:00+08:00',
                'value': 'PARTLY_CLOUDY_DAY',
              },
            ],
          },
          'daily': {
            'temperature': [
              {'date': '2026-05-23T00:00+08:00', 'max': 30, 'min': 21},
            ],
            'skycon': [
              {'date': '2026-05-23T00:00+08:00', 'value': 'PARTLY_CLOUDY_DAY'},
            ],
          },
          'primary': 0,
          'forecast_keypoint': '天气稳定',
        },
      });

      final displayData = WeatherDisplayData.fromRecords(
        address: AddressRecord(
          id: 1,
          latitude: 31.2646,
          longitude: 121.5051,
          province: '上海市',
          city: '上海市',
          district: '虹口区',
          detailAddress: '上海市虹口区',
          sortOrder: 0,
          createdAt: DateTime(2026, 5, 23, 15),
          updatedAt: DateTime(2026, 5, 23, 15),
        ),
        currentRecord: WeatherRecord(
          addressId: 1,
          weatherDate: '2026-05-23',
          rawResponse: rawResponse,
          createdAt: DateTime(2026, 5, 23, 15),
          updatedAt: DateTime(2026, 5, 23, 15),
        ),
      );

      expect(displayData.hourly.first.timeText, '15:00');
      expect(displayData.hourly[1].timeText, '16:00');
      expect(displayData.hourly.first.skycon, 'PARTLY_CLOUDY_DAY');
      expect(displayData.hourly[1].skycon, 'CLOUDY');
    },
  );

  test('WeatherDisplayData keeps yesterday plus seven daily forecast rows', () {
    final rawResponse = jsonEncode({
      'status': 'ok',
      'api_version': 'v2.6',
      'api_status': 'active',
      'lang': 'zh_CN',
      'unit': 'metric',
      'tzshift': 28800,
      'timezone': 'Asia/Shanghai',
      'server_time': 1779520027,
      'location': [31.2646, 121.5051],
      'result': {
        'alert': {},
        'realtime': {
          'temperature': 26.6,
          'skycon': 'PARTLY_CLOUDY_DAY',
          'humidity': 0.74,
          'wind': {'direction': 90, 'speed': 8},
        },
        'minutely': {},
        'hourly': {},
        'daily': {
          'temperature': [
            for (var index = 0; index < 7; index += 1)
              {
                'date': '2026-05-${23 + index}T00:00+08:00',
                'max': 30 - index,
                'min': 21 - index,
              },
          ],
          'skycon': [
            for (var index = 0; index < 7; index += 1)
              {
                'date': '2026-05-${23 + index}T00:00+08:00',
                'value': 'PARTLY_CLOUDY_DAY',
              },
          ],
        },
        'primary': 0,
        'forecast_keypoint': '天气稳定',
      },
    });

    final displayData = WeatherDisplayData.fromRecords(
      address: AddressRecord(
        id: 1,
        latitude: 31.2646,
        longitude: 121.5051,
        province: '上海市',
        city: '上海市',
        district: '虹口区',
        detailAddress: '上海市虹口区',
        sortOrder: 0,
        createdAt: DateTime(2026, 5, 23, 15),
        updatedAt: DateTime(2026, 5, 23, 15),
      ),
      currentRecord: WeatherRecord(
        addressId: 1,
        weatherDate: '2026-05-23',
        rawResponse: rawResponse,
        createdAt: DateTime(2026, 5, 23, 15),
        updatedAt: DateTime(2026, 5, 23, 15),
      ),
    );

    expect(displayData.daily, hasLength(8));
    expect(displayData.daily.take(3).map((item) => item.dayText), [
      '昨天',
      '今天',
      '明天',
    ]);
  });
}
