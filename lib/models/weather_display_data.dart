import 'address_record.dart';
import 'caiyun_weather_response.dart';
import 'weather_record.dart';

/// 天气首页所需的聚合展示数据。
///
/// 该对象由“地址记录 + 当天最新天气记录 + 昨日天气记录”组合而成，
/// 页面只读取这里的字段，不直接处理彩云原始 JSON 结构。
class WeatherDisplayData {
  const WeatherDisplayData({
    required this.address,
    required this.currentRecord,
    required this.current,
    required this.hourly,
    required this.daily,
    required this.airQuality,
    required this.background,
  });

  final AddressRecord address;
  final WeatherRecord currentRecord;
  final CurrentWeatherDisplay current;
  final List<HourlyWeatherDisplay> hourly;
  final List<DailyWeatherDisplay> daily;
  final AirQualityDisplay airQuality;
  final WeatherBackgroundStyle background;

  /// 从数据库记录构建天气首页展示数据。
  factory WeatherDisplayData.fromRecords({
    required AddressRecord address,
    required WeatherRecord currentRecord,
    WeatherRecord? yesterdayRecord,
  }) {
    final currentResponse = currentRecord.weather;
    final yesterdayResponse = yesterdayRecord?.weather;
    final realtime = currentResponse.result.realtime;
    final daily = currentResponse.result.daily;
    final skycon = _readString(realtime, 'skycon', fallback: 'CLOUDY');
    final current = CurrentWeatherDisplay(
      temperature: _readDouble(realtime, 'temperature'),
      skycon: skycon,
      weatherText: WeatherText.fromSkycon(skycon),
      windDirection: _windDirectionText(
        _readNestedDouble(realtime, const ['wind', 'direction']),
      ),
      windLevel: _windLevelText(
        _readNestedDouble(realtime, const ['wind', 'speed']),
      ),
      humidityPercent: (_readDouble(realtime, 'humidity') * 100).round(),
      temperatureMax: _readDailyValue(
        daily,
        listKey: 'temperature',
        valueKey: 'max',
        index: 0,
      ),
      temperatureMin: _readDailyValue(
        daily,
        listKey: 'temperature',
        valueKey: 'min',
        index: 0,
      ),
      forecastKeypoint: currentResponse.result.forecastKeypoint,
    );

    final hourly = _buildHourly(currentResponse);
    final dailyRows = _buildDailyRows(
      currentResponse: currentResponse,
      yesterdayResponse: yesterdayResponse,
    );
    final airQuality = AirQualityDisplay.fromRealtime(realtime);

    return WeatherDisplayData(
      address: address,
      currentRecord: currentRecord,
      current: current,
      hourly: hourly,
      daily: dailyRows,
      airQuality: airQuality,
      background: WeatherBackgroundStyle.fromSkycon(skycon),
    );
  }
}

/// 当前天气模块数据。
class CurrentWeatherDisplay {
  const CurrentWeatherDisplay({
    required this.temperature,
    required this.skycon,
    required this.weatherText,
    required this.windDirection,
    required this.windLevel,
    required this.humidityPercent,
    required this.temperatureMax,
    required this.temperatureMin,
    required this.forecastKeypoint,
  });

  final double temperature;
  final String skycon;
  final String weatherText;
  final String windDirection;
  final String windLevel;
  final int humidityPercent;
  final double temperatureMax;
  final double temperatureMin;
  final String forecastKeypoint;
}

/// 小时级天气折线图数据。
class HourlyWeatherDisplay {
  const HourlyWeatherDisplay({
    required this.timeText,
    required this.temperature,
    required this.skycon,
    required this.weatherText,
  });

  final String timeText;
  final double temperature;
  final String skycon;
  final String weatherText;
}

/// 天级天气列表数据。
class DailyWeatherDisplay {
  const DailyWeatherDisplay({
    required this.dayText,
    required this.skycon,
    required this.weatherText,
    required this.temperatureMax,
    required this.temperatureMin,
    required this.hasData,
  });

  final String dayText;
  final String skycon;
  final String weatherText;
  final double temperatureMax;
  final double temperatureMin;
  final bool hasData;

  factory DailyWeatherDisplay.emptyYesterday() {
    return const DailyWeatherDisplay(
      dayText: '昨天',
      skycon: 'CLOUDY',
      weatherText: '暂无保存数据',
      temperatureMax: 0,
      temperatureMin: 0,
      hasData: false,
    );
  }
}

/// 空气质量模块数据。
class AirQualityDisplay {
  const AirQualityDisplay({
    required this.aqi,
    required this.description,
    required this.pm10,
    required this.pm25,
    required this.no2,
    required this.so2,
    required this.co,
    required this.o3,
  });

  final int aqi;
  final String description;
  final double pm10;
  final double pm25;
  final double no2;
  final double so2;
  final double co;
  final double o3;

  factory AirQualityDisplay.fromRealtime(Map<String, Object?> realtime) {
    final airQuality = _readMap(realtime, 'air_quality');
    return AirQualityDisplay(
      aqi: _readNestedDouble(airQuality, const ['aqi', 'chn']).round(),
      description: _readNestedString(airQuality, const [
        'description',
        'chn',
      ], fallback: '未知'),
      pm10: _readDouble(airQuality, 'pm10'),
      pm25: _readDouble(airQuality, 'pm25'),
      no2: _readDouble(airQuality, 'no2'),
      so2: _readDouble(airQuality, 'so2'),
      co: _readDouble(airQuality, 'co'),
      o3: _readDouble(airQuality, 'o3'),
    );
  }
}

/// 天气背景样式。
class WeatherBackgroundStyle {
  const WeatherBackgroundStyle({
    required this.topColor,
    required this.bottomColor,
    required this.showRain,
  });

  final int topColor;
  final int bottomColor;
  final bool showRain;

  factory WeatherBackgroundStyle.fromSkycon(String skycon) {
    if (skycon.contains('RAIN')) {
      return const WeatherBackgroundStyle(
        topColor: 0xFF8BA0AA,
        bottomColor: 0xFF607987,
        showRain: true,
      );
    }
    if (skycon.contains('SNOW')) {
      return const WeatherBackgroundStyle(
        topColor: 0xFFAAB7C2,
        bottomColor: 0xFF7C8EA0,
        showRain: false,
      );
    }
    if (skycon.contains('CLEAR')) {
      return const WeatherBackgroundStyle(
        topColor: 0xFF4DA1D9,
        bottomColor: 0xFF226A9A,
        showRain: false,
      );
    }
    return const WeatherBackgroundStyle(
      topColor: 0xFF7D96A2,
      bottomColor: 0xFF5E7480,
      showRain: false,
    );
  }
}

/// 彩云天气现象码转中文。
class WeatherText {
  static String fromSkycon(String skycon) {
    return switch (skycon) {
      'CLEAR_DAY' => '晴',
      'CLEAR_NIGHT' => '晴',
      'PARTLY_CLOUDY_DAY' => '多云',
      'PARTLY_CLOUDY_NIGHT' => '多云',
      'CLOUDY' => '阴',
      'LIGHT_HAZE' => '轻度雾霾',
      'MODERATE_HAZE' => '中度雾霾',
      'HEAVY_HAZE' => '重度雾霾',
      'LIGHT_RAIN' => '小雨',
      'MODERATE_RAIN' => '中雨',
      'HEAVY_RAIN' => '大雨',
      'STORM_RAIN' => '暴雨',
      'FOG' => '雾',
      'LIGHT_SNOW' => '小雪',
      'MODERATE_SNOW' => '中雪',
      'HEAVY_SNOW' => '大雪',
      'STORM_SNOW' => '暴雪',
      'DUST' => '浮尘',
      'SAND' => '沙尘',
      'WIND' => '大风',
      _ => '未知',
    };
  }
}

List<HourlyWeatherDisplay> _buildHourly(CaiyunWeatherResponse response) {
  final hourly = response.result.hourly;
  final temperatureRows = _readList(hourly, 'temperature');
  final skyconRows = _readList(hourly, 'skycon');
  final count = temperatureRows.length < 24 ? temperatureRows.length : 24;

  return [
    for (var index = 0; index < count; index += 1)
      HourlyWeatherDisplay(
        timeText: _formatHour(_readString(temperatureRows[index], 'datetime')),
        temperature: _readDouble(temperatureRows[index], 'value'),
        skycon: _readString(
          index < skyconRows.length ? skyconRows[index] : const {},
          'value',
          fallback: 'CLOUDY',
        ),
        weatherText: WeatherText.fromSkycon(
          _readString(
            index < skyconRows.length ? skyconRows[index] : const {},
            'value',
            fallback: 'CLOUDY',
          ),
        ),
      ),
  ];
}

List<DailyWeatherDisplay> _buildDailyRows({
  required CaiyunWeatherResponse currentResponse,
  CaiyunWeatherResponse? yesterdayResponse,
}) {
  final rows = <DailyWeatherDisplay>[];
  rows.add(_buildYesterdayRow(yesterdayResponse));

  final daily = currentResponse.result.daily;
  final temperatureRows = _readList(daily, 'temperature');
  final skyconRows = _readList(daily, 'skycon');
  final count = temperatureRows.length < 6 ? temperatureRows.length : 6;

  for (var index = 0; index < count; index += 1) {
    rows.add(
      _buildDailyRow(
        dayText: index == 0
            ? '今天'
            : _weekdayText(DateTime.now().add(Duration(days: index))),
        temperatureRow: temperatureRows[index],
        skyconRow: index < skyconRows.length ? skyconRows[index] : const {},
      ),
    );
  }

  return rows;
}

DailyWeatherDisplay _buildYesterdayRow(CaiyunWeatherResponse? response) {
  if (response == null) {
    return DailyWeatherDisplay.emptyYesterday();
  }

  final daily = response.result.daily;
  final temperatureRows = _readList(daily, 'temperature');
  final skyconRows = _readList(daily, 'skycon');
  if (temperatureRows.isEmpty) {
    return DailyWeatherDisplay.emptyYesterday();
  }

  return _buildDailyRow(
    dayText: '昨天',
    temperatureRow: temperatureRows.first,
    skyconRow: skyconRows.isEmpty ? const {} : skyconRows.first,
  );
}

DailyWeatherDisplay _buildDailyRow({
  required String dayText,
  required Map<String, Object?> temperatureRow,
  required Map<String, Object?> skyconRow,
}) {
  final skycon = _readString(skyconRow, 'value', fallback: 'CLOUDY');
  return DailyWeatherDisplay(
    dayText: dayText,
    skycon: skycon,
    weatherText: WeatherText.fromSkycon(skycon),
    temperatureMax: _readDouble(temperatureRow, 'max'),
    temperatureMin: _readDouble(temperatureRow, 'min'),
    hasData: true,
  );
}

double _readDailyValue(
  Map<String, Object?> daily, {
  required String listKey,
  required String valueKey,
  required int index,
}) {
  final rows = _readList(daily, listKey);
  if (index >= rows.length) {
    return 0;
  }
  return _readDouble(rows[index], valueKey);
}

String _formatHour(String rawDateTime) {
  final parsed = DateTime.tryParse(rawDateTime);
  if (parsed == null) {
    return '--:--';
  }
  return '${parsed.hour.toString().padLeft(2, '0')}:00';
}

String _weekdayText(DateTime dateTime) {
  return switch (dateTime.weekday) {
    DateTime.monday => '周一',
    DateTime.tuesday => '周二',
    DateTime.wednesday => '周三',
    DateTime.thursday => '周四',
    DateTime.friday => '周五',
    DateTime.saturday => '周六',
    DateTime.sunday => '周日',
    _ => '',
  };
}

String _windDirectionText(double direction) {
  if (direction >= 337.5 || direction < 22.5) {
    return '北风';
  }
  if (direction < 67.5) {
    return '东北风';
  }
  if (direction < 112.5) {
    return '东风';
  }
  if (direction < 157.5) {
    return '东南风';
  }
  if (direction < 202.5) {
    return '南风';
  }
  if (direction < 247.5) {
    return '西南风';
  }
  if (direction < 292.5) {
    return '西风';
  }
  return '西北风';
}

String _windLevelText(double speed) {
  if (speed < 12) {
    return '微风';
  }
  if (speed < 20) {
    return '3级';
  }
  if (speed < 29) {
    return '4级';
  }
  if (speed < 39) {
    return '5级';
  }
  if (speed < 50) {
    return '6级';
  }
  return '强风';
}

String _readNestedString(
  Map<String, Object?> json,
  List<String> keys, {
  String fallback = '',
}) {
  Object? value = json;
  for (final key in keys) {
    if (value is! Map<String, Object?>) {
      return fallback;
    }
    value = value[key];
  }
  return value is String ? value : fallback;
}

double _readNestedDouble(Map<String, Object?> json, List<String> keys) {
  Object? value = json;
  for (final key in keys) {
    if (value is! Map<String, Object?>) {
      return 0;
    }
    value = value[key];
  }
  return value is num ? value.toDouble() : 0;
}

String _readString(
  Map<String, Object?> json,
  String key, {
  String fallback = '',
}) {
  final value = json[key];
  return value is String ? value : fallback;
}

double _readDouble(Map<String, Object?> json, String key) {
  final value = json[key];
  return value is num ? value.toDouble() : 0;
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

List<Map<String, Object?>> _readList(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! List<Object?>) {
    return const [];
  }
  return [
    for (final item in value)
      if (item is Map<String, Object?>)
        item
      else if (item is Map)
        item.map((key, value) => MapEntry(key.toString(), value)),
  ];
}
