import 'package:flutter/material.dart';

import 'models/address_record.dart';
import 'models/weather_record.dart';
import 'pages/address_records_page.dart';
import 'pages/weather_records_page.dart';
import 'services/address_database_service.dart';
import 'services/caiyun_weather_service.dart';
import 'services/location_address_service.dart';

void main() {
  runApp(const AikraiSkyApp());
}

/// 天气 App 根组件。
///
/// 当前第一步先聚焦“定位并保存地址”，后续天气页面可以继续在这个 App 壳上扩展。
class AikraiSkyApp extends StatelessWidget {
  const AikraiSkyApp({super.key, this.home});

  /// 默认进入定位初始化页；测试时可以传入轻量页面，避免触发真实定位权限请求。
  final Widget? home;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Aikrai Sky',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: home ?? const LocationBootstrapPage(),
    );
  }
}

/// 应用启动和前台恢复时的定位页面。
///
/// 通过 [WidgetsBindingObserver] 监听生命周期：首次打开 App 时在 [initState]
/// 触发定位；从后台切回前台时在 [didChangeAppLifecycleState] 中再次触发定位。
class LocationBootstrapPage extends StatefulWidget {
  const LocationBootstrapPage({super.key});

  @override
  State<LocationBootstrapPage> createState() => _LocationBootstrapPageState();
}

class _LocationBootstrapPageState extends State<LocationBootstrapPage>
    with WidgetsBindingObserver {
  final _locationAddressService = const LocationAddressService();
  final _caiyunWeatherService = const CaiyunWeatherService();

  AddressRecord? _latestAddress;
  WeatherRecord? _latestWeather;
  String _statusText = '准备获取当前位置...';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // 首次进入页面时，先读取本地最新地址用于展示，再启动新一轮定位落库。
    _loadLatestAddress();
    _captureAndSaveAddress(triggerSource: '应用启动');
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    // resumed 表示 App 已回到前台。此时重新定位，确保天气查询使用最新位置。
    if (state == AppLifecycleState.resumed) {
      _captureAndSaveAddress(triggerSource: '回到前台');
    }
  }

  /// 加载本地最新地址记录，避免页面初始状态完全空白。
  Future<void> _loadLatestAddress() async {
    final latestAddress = await AddressDatabaseService.instance
        .fetchLatestAddress();

    if (!mounted || latestAddress == null) {
      return;
    }

    setState(() {
      _latestAddress = latestAddress;
      _statusText = '已读取本地最新地址，正在刷新当前位置...';
    });

    final addressId = latestAddress.id;
    if (addressId == null) {
      return;
    }

    final latestWeather = await AddressDatabaseService.instance
        .fetchLatestWeatherByAddressId(addressId);

    if (!mounted || latestWeather == null) {
      return;
    }

    setState(() {
      _latestWeather = latestWeather;
    });
  }

  /// 执行“定位 -> 地址入库 -> 天气请求 -> 天气入库”的完整流程。
  Future<void> _captureAndSaveAddress({required String triggerSource}) async {
    if (_isLoading) {
      return;
    }

    setState(() {
      _isLoading = true;
      _statusText = '$triggerSource：正在获取定位信息...';
    });

    try {
      final savedAddress = await _locationAddressService
          .captureAndSaveCurrentAddress();

      if (!mounted) {
        return;
      }

      setState(() {
        _latestAddress = savedAddress;
        _latestWeather = null;
        _statusText = '$triggerSource：定位地址已保存，正在请求天气数据...';
      });

      final savedWeather = await _caiyunWeatherService.fetchAndSaveWeather(
        savedAddress,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _latestWeather = savedWeather;
        _statusText = '$triggerSource：天气数据已保存到本地天气数据表。';
      });
    } on LocationAddressException catch (error) {
      _showErrorStatus('$triggerSource：${error.message}');
    } on CaiyunWeatherException catch (error) {
      _showErrorStatus('$triggerSource：地址已保存，天气获取失败：${error.message}');
    } catch (error) {
      // 兜底处理平台定位、地理编码、网络请求或 SQLite 可能抛出的未知异常。
      _showErrorStatus('$triggerSource：定位或天气保存失败，$error');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// 统一更新错误状态，避免多个 catch 分支重复写 setState。
  void _showErrorStatus(String message) {
    if (!mounted) {
      return;
    }

    setState(() {
      _statusText = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final latestAddress = _latestAddress;

    return Scaffold(
      appBar: AppBar(title: const Text('Aikrai Sky')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (_isLoading)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Icon(
                      latestAddress == null
                          ? Icons.location_searching
                          : Icons.location_on,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _statusText,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const _DataTableLinks(),
              const SizedBox(height: 24),
              Text('最新地址记录', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              if (latestAddress == null)
                const Text('暂无地址记录。请确认已开启定位服务并授予定位权限。')
              else
                _AddressRecordView(address: latestAddress),
              const SizedBox(height: 24),
              Text('最新天气数据', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              if (_latestWeather == null)
                const Text('暂无天气数据。定位成功后会自动请求彩云天气并保存。')
              else
                _WeatherRecordView(weather: _latestWeather!),
            ],
          ),
        ),
      ),
    );
  }
}

/// 数据查看页面入口。
///
/// 定位和天气保存逻辑会持续写入本地 SQLite；这两个入口用于直接查看表数据，
/// 方便调试分页、按日查询和原始响应内容。
class _DataTableLinks extends StatelessWidget {
  const _DataTableLinks();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        OutlinedButton.icon(
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const AddressRecordsPage(),
              ),
            );
          },
          icon: const Icon(Icons.place),
          label: const Text('查看地址表'),
        ),
        OutlinedButton.icon(
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const WeatherRecordsPage(),
              ),
            );
          },
          icon: const Icon(Icons.storage),
          label: const Text('查看天气数据表'),
        ),
      ],
    );
  }
}

/// 天气数据保存状态展示组件。
///
/// 当前只展示数据库记录元信息，不直接展开原始 JSON，避免页面过长；后续天气首页
/// 可以从 [WeatherRecord.rawResponse] 中解析 realtime、daily 等节点展示。
class _WeatherRecordView extends StatelessWidget {
  const _WeatherRecordView({required this.weather});

  final WeatherRecord weather;

  @override
  Widget build(BuildContext context) {
    final rows = [
      ('地址Id', '${weather.addressId}'),
      ('天气日期', weather.weatherDate),
      ('原始数据长度', '${weather.rawResponse.length} 字符'),
      ('创建时间', weather.createdAt.toLocal().toString()),
      ('更新时间', weather.updatedAt.toLocal().toString()),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text('${row.$1}：${row.$2}'),
          ),
      ],
    );
  }
}

/// 地址记录展示组件。
///
/// UI 只负责展示字段，不做定位和数据库操作，便于后续替换为天气首页。
class _AddressRecordView extends StatelessWidget {
  const _AddressRecordView({required this.address});

  final AddressRecord address;

  @override
  Widget build(BuildContext context) {
    final rows = [
      ('经纬度', '${address.latitude}, ${address.longitude}'),
      ('省', address.province),
      ('市', address.city),
      ('区', address.district),
      ('详细地址', address.detailAddress),
      ('创建时间', address.createdAt.toLocal().toString()),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text('${row.$1}：${row.$2}'),
          ),
      ],
    );
  }
}
