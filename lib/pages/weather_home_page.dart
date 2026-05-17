import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/address_record.dart';
import '../models/weather_display_data.dart';
import '../services/address_database_service.dart';
import '../services/caiyun_weather_service.dart';
import '../services/location_address_service.dart';
import 'address_records_page.dart';
import 'weather_records_page.dart';

/// 天气首页。
///
/// 页面从上到下展示四个模块：当前天气、近 24 小时、近 7 天、空气质量。
/// 启动和从后台回到前台时会刷新定位与天气数据。
class WeatherHomePage extends StatefulWidget {
  const WeatherHomePage({super.key});

  @override
  State<WeatherHomePage> createState() => _WeatherHomePageState();
}

class _WeatherHomePageState extends State<WeatherHomePage>
    with WidgetsBindingObserver {
  final _locationAddressService = const LocationAddressService();
  final _caiyunWeatherService = const CaiyunWeatherService();

  WeatherDisplayData? _weatherData;
  String _statusText = '正在获取定位和天气数据...';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSavedWeather();
    _refreshWeather(triggerSource: '应用启动');
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _refreshWeather(triggerSource: '回到前台');
    }
  }

  /// 先展示本地已保存的最新天气，避免启动时页面长时间空白。
  Future<void> _loadSavedWeather() async {
    final address = await AddressDatabaseService.instance.fetchLatestAddress();
    final addressId = address?.id;
    if (address == null || addressId == null) {
      return;
    }

    final weather = await AddressDatabaseService.instance
        .fetchLatestWeatherByAddressId(addressId);
    if (weather == null) {
      return;
    }

    final yesterdayWeather = await AddressDatabaseService.instance
        .fetchWeatherByAddressIdAndDate(
          addressId: addressId,
          date: DateTime.now().subtract(const Duration(days: 1)),
        );

    if (!mounted) {
      return;
    }

    setState(() {
      _weatherData = WeatherDisplayData.fromRecords(
        address: address,
        currentRecord: weather,
        yesterdayRecord: yesterdayWeather,
      );
      _statusText = '已读取本地天气，正在刷新...';
    });
  }

  /// 刷新定位、天气和页面展示数据。
  Future<void> _refreshWeather({required String triggerSource}) async {
    if (_isLoading) {
      return;
    }

    setState(() {
      _isLoading = true;
      _statusText = '$triggerSource：正在获取当前位置...';
    });

    try {
      final address = await _locationAddressService
          .captureAndSaveCurrentAddress();
      if (!mounted) {
        return;
      }

      setState(() {
        _statusText = '$triggerSource：正在请求天气数据...';
      });

      final currentWeather = await _caiyunWeatherService.fetchAndSaveWeather(
        address,
      );
      final addressId = address.id;
      final yesterdayWeather = addressId == null
          ? null
          : await AddressDatabaseService.instance
                .fetchWeatherByAddressIdAndDate(
                  addressId: addressId,
                  date: DateTime.now().subtract(const Duration(days: 1)),
                );

      if (!mounted) {
        return;
      }

      setState(() {
        _weatherData = WeatherDisplayData.fromRecords(
          address: address,
          currentRecord: currentWeather,
          yesterdayRecord: yesterdayWeather,
        );
        _statusText = '$triggerSource：天气已更新';
      });
    } on LocationAddressException catch (error) {
      _showStatus('$triggerSource：${error.message}');
    } on CaiyunWeatherException catch (error) {
      _showStatus('$triggerSource：天气获取失败：${error.message}');
    } catch (error) {
      _showStatus('$triggerSource：刷新失败，$error');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showStatus(String message) {
    if (!mounted) {
      return;
    }
    setState(() {
      _statusText = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final weatherData = _weatherData;
    final background =
        weatherData?.background ??
        const WeatherBackgroundStyle(
          topColor: 0xFF7D96A2,
          bottomColor: 0xFF5E7480,
          showRain: false,
        );

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: '刷新天气',
            onPressed: _isLoading
                ? null
                : () => _refreshWeather(triggerSource: '手动刷新'),
            icon: const Icon(Icons.refresh),
          ),
          PopupMenuButton<_WeatherMenuAction>(
            icon: const Icon(Icons.more_vert),
            onSelected: _handleMenuAction,
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _WeatherMenuAction.addressTable,
                child: Text('地址表数据'),
              ),
              PopupMenuItem(
                value: _WeatherMenuAction.weatherTable,
                child: Text('天气数据表'),
              ),
            ],
          ),
        ],
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(background.topColor), Color(background.bottomColor)],
          ),
        ),
        child: Stack(
          children: [
            if (background.showRain) const Positioned.fill(child: _RainLayer()),
            SafeArea(
              child: RefreshIndicator(
                onRefresh: () => _refreshWeather(triggerSource: '下拉刷新'),
                child: weatherData == null
                    ? _EmptyWeatherView(statusText: _statusText)
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                        children: [
                          _CurrentWeatherModule(data: weatherData),
                          const SizedBox(height: 18),
                          _HourlyWeatherModule(items: weatherData.hourly),
                          const SizedBox(height: 18),
                          _DailyWeatherModule(items: weatherData.daily),
                          const SizedBox(height: 18),
                          _AirQualityModule(data: weatherData.airQuality),
                          const SizedBox(height: 14),
                          Text(
                            _statusText,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleMenuAction(_WeatherMenuAction action) {
    switch (action) {
      case _WeatherMenuAction.addressTable:
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const AddressRecordsPage()),
        );
      case _WeatherMenuAction.weatherTable:
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const WeatherRecordsPage()),
        );
    }
  }
}

enum _WeatherMenuAction { addressTable, weatherTable }

/// 当前天气模块。
class _CurrentWeatherModule extends StatelessWidget {
  const _CurrentWeatherModule({required this.data});

  final WeatherDisplayData data;

  @override
  Widget build(BuildContext context) {
    final current = data.current;

    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Column(
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _locationTitle(data.address),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.location_on,
                      color: Colors.white,
                      size: 30,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  '● ○ ○ ○',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
              ],
            ),
          ),
          const SizedBox(height: 260),
          Text(
            '${current.windDirection} ${current.windLevel}  |  湿度 ${current.humidityPercent}%',
            style: const TextStyle(color: Colors.white, fontSize: 22),
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                current.temperature.round().toString(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 118,
                  height: 0.92,
                  fontWeight: FontWeight.w300,
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(bottom: 58),
                child: Text(
                  '°C',
                  style: TextStyle(color: Colors.white, fontSize: 34),
                ),
              ),
              const SizedBox(width: 18),
              Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Text(
                  current.weatherText,
                  style: const TextStyle(color: Colors.white, fontSize: 32),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            '${current.temperatureMax.round()}°C / ${current.temperatureMin.round()}°C',
            style: const TextStyle(color: Colors.white, fontSize: 28),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: Text(
                  current.forecastKeypoint.isEmpty
                      ? '暂无天气预报关键点'
                      : current.forecastKeypoint,
                  style: const TextStyle(color: Colors.white, fontSize: 21),
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white70),
            ],
          ),
        ],
      ),
    );
  }

  String _locationTitle(AddressRecord address) {
    if (address.district.isNotEmpty) {
      return address.district;
    }
    if (address.city.isNotEmpty) {
      return address.city;
    }
    return address.province;
  }
}

/// 近 24 小时天气模块。
class _HourlyWeatherModule extends StatelessWidget {
  const _HourlyWeatherModule({required this.items});

  final List<HourlyWeatherDisplay> items;

  @override
  Widget build(BuildContext context) {
    final chartWidth = math.max(680.0, items.length * 86.0);

    return _GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Expanded(
                child: Text(
                  '24 小时',
                  style: TextStyle(color: Colors.white70, fontSize: 24),
                ),
              ),
              Icon(Icons.wb_twilight, color: Colors.white70),
              SizedBox(width: 6),
              Text(
                '逐小时预报',
                style: TextStyle(color: Colors.white70, fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: 28),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 36),
              child: Center(
                child: Text('暂无小时级天气数据', style: TextStyle(color: Colors.white)),
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: chartWidth,
                height: 230,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _HourlyTemperaturePainter(items: items),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          for (final item in items)
                            SizedBox(
                              width: 72,
                              child: Column(
                                children: [
                                  Icon(
                                    _weatherIcon(item.skycon),
                                    color: Colors.white,
                                    size: 32,
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    item.timeText,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 近 7 天天气模块。
class _DailyWeatherModule extends StatelessWidget {
  const _DailyWeatherModule({required this.items});

  final List<DailyWeatherDisplay> items;

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      child: Column(
        children: [
          for (final item in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 11),
              child: Opacity(
                opacity: item.hasData ? 1 : 0.55,
                child: Row(
                  children: [
                    SizedBox(
                      width: 72,
                      child: Text(
                        item.dayText,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 25,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        item.weatherText,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 25,
                        ),
                      ),
                    ),
                    Icon(
                      _weatherIcon(item.skycon),
                      color: Colors.white,
                      size: 34,
                    ),
                    const SizedBox(width: 22),
                    SizedBox(
                      width: 112,
                      child: Text(
                        item.hasData
                            ? '${item.temperatureMax.round()}°C / ${item.temperatureMin.round()}°C'
                            : '-- / --',
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 空气质量模块。
class _AirQualityModule extends StatelessWidget {
  const _AirQualityModule({required this.data});

  final AirQualityDisplay data;

  @override
  Widget build(BuildContext context) {
    final rows = [
      ('PM10', data.pm10),
      ('PM2.5', data.pm25),
      ('NO₂', data.no2),
      ('SO₂', data.so2),
      ('CO', data.co),
      ('O₃', data.o3),
    ];

    return _GlassPanel(
      child: Row(
        children: [
          Expanded(
            child: Column(
              children: [
                const Text(
                  '空气质量',
                  style: TextStyle(color: Colors.white, fontSize: 28),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: 190,
                  height: 190,
                  child: CustomPaint(
                    painter: _AqiGaugePainter(aqi: data.aqi),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${data.aqi}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 50,
                              fontWeight: FontWeight.w300,
                            ),
                          ),
                          const Text(
                            'AQI',
                            style: TextStyle(color: Colors.white, fontSize: 18),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            data.description,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 19,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('0', style: TextStyle(color: Colors.white70)),
                    SizedBox(width: 116),
                    Text('500', style: TextStyle(color: Colors.white70)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: Column(
              children: [
                for (final row in rows)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            row.$1,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 20,
                            ),
                          ),
                        ),
                        Text(
                          _formatAirValue(row.$2),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatAirValue(double value) {
    if (value == value.roundToDouble()) {
      return value.round().toString();
    }
    return value.toStringAsFixed(1);
  }
}

/// 玻璃拟态模块容器。
class _GlassPanel extends StatelessWidget {
  const _GlassPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: child,
    );
  }
}

/// 没有天气数据时的占位页。
class _EmptyWeatherView extends StatelessWidget {
  const _EmptyWeatherView({required this.statusText});

  final String statusText;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(28),
      children: [
        const SizedBox(height: 180),
        const Icon(Icons.cloud_sync, color: Colors.white, size: 64),
        const SizedBox(height: 20),
        Text(
          statusText,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontSize: 20),
        ),
      ],
    );
  }
}

/// 雨天背景层。
class _RainLayer extends StatelessWidget {
  const _RainLayer();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _RainPainter());
  }
}

class _RainPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.22)
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round;

    for (var index = 0; index < 46; index += 1) {
      final x = (index * 53.0) % size.width;
      final y = (index * 97.0) % size.height;
      canvas.drawLine(Offset(x, y), Offset(x + 13, y + 58), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _HourlyTemperaturePainter extends CustomPainter {
  const _HourlyTemperaturePainter({required this.items});

  final List<HourlyWeatherDisplay> items;

  @override
  void paint(Canvas canvas, Size size) {
    if (items.isEmpty) {
      return;
    }

    final temperatures = items.map((item) => item.temperature).toList();
    final minTemperature = temperatures.reduce(math.min);
    final maxTemperature = temperatures.reduce(math.max);
    final range = math.max(1.0, maxTemperature - minTemperature);
    final step = size.width / items.length;
    final points = <Offset>[];

    for (var index = 0; index < items.length; index += 1) {
      final x = step * index + step / 2;
      final normalized = (items[index].temperature - minTemperature) / range;
      final y = 88 - normalized * 42;
      points.add(Offset(x, y));
    }

    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.78)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final pointPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(path, linePaint);

    for (var index = 0; index < points.length; index += 1) {
      final point = points[index];
      canvas.drawCircle(point, 4, pointPaint);
      _paintText(
        canvas,
        '${items[index].temperature.round()}°C',
        Offset(point.dx, point.dy - 34),
        fontSize: 18,
      );
    }
  }

  void _paintText(
    Canvas canvas,
    String text,
    Offset center, {
    required double fontSize,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: Colors.white, fontSize: fontSize),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      Offset(center.dx - painter.width / 2, center.dy - painter.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _HourlyTemperaturePainter oldDelegate) {
    return oldDelegate.items != items;
  }
}

class _AqiGaugePainter extends CustomPainter {
  const _AqiGaugePainter({required this.aqi});

  final int aqi;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final gaugeRect = rect.deflate(12);
    final basePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.22)
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final activePaint = Paint()
      ..color = const Color(0xFF43F35C)
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    const startAngle = math.pi * 0.78;
    const sweepAngle = math.pi * 1.44;
    final activeSweep = sweepAngle * (aqi.clamp(0, 500) / 500);

    canvas.drawArc(gaugeRect, startAngle, sweepAngle, false, basePaint);
    canvas.drawArc(gaugeRect, startAngle, activeSweep, false, activePaint);
  }

  @override
  bool shouldRepaint(covariant _AqiGaugePainter oldDelegate) {
    return oldDelegate.aqi != aqi;
  }
}

IconData _weatherIcon(String skycon) {
  if (skycon.contains('RAIN')) {
    return Icons.grain;
  }
  if (skycon.contains('SNOW')) {
    return Icons.ac_unit;
  }
  if (skycon.contains('CLEAR')) {
    return Icons.wb_sunny;
  }
  if (skycon.contains('PARTLY')) {
    return Icons.wb_cloudy;
  }
  if (skycon.contains('HAZE') || skycon == 'FOG') {
    return Icons.blur_on;
  }
  if (skycon == 'WIND') {
    return Icons.air;
  }
  return Icons.cloud;
}
