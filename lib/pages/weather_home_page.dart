import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/address_record.dart';
import '../models/weather_display_data.dart';
import '../services/address_database_service.dart';
import '../services/caiyun_weather_service.dart';
import '../services/location_address_service.dart';
import 'address_records_page.dart';
import 'location_management_page.dart';
import 'weather_records_page.dart';

/// 天气首页。
///
/// 页面从上到下展示：当前天气、近 24 小时、近 7 天、空气质量、生活指数。
/// 启动时会先展示上一次定位城市的本地天气，再尝试重新定位；普通刷新只更新天气，
/// 不重新定位，也不会把非定位城市页面切回定位城市。
class WeatherHomePage extends StatefulWidget {
  const WeatherHomePage({super.key});

  @override
  State<WeatherHomePage> createState() => _WeatherHomePageState();
}

class _WeatherHomePageState extends State<WeatherHomePage> {
  static const _defaultBackground = WeatherBackgroundStyle(
    topColor: 0xFF4DA1D9,
    bottomColor: 0xFF226A9A,
    showRain: false,
  );

  final _locationAddressService = const LocationAddressService();
  final _caiyunWeatherService = const CaiyunWeatherService();
  final _addressPageController = PageController();
  final _backgroundStyle = ValueNotifier<WeatherBackgroundStyle>(
    _defaultBackground,
  );

  WeatherDisplayData? _weatherData;
  final Map<int, WeatherDisplayData> _weatherDataByAddressId = {};
  List<AddressRecord> _addresses = const [];
  int _selectedAddressIndex = 0;
  int? _currentLocatedAddressId;
  AddressRecord? _currentLocatedAddress;
  int _addressSwitchRequestId = 0;
  String _statusText = '正在读取本地天气...';
  bool _isLocating = false;
  bool _isRefreshingWeather = false;

  @override
  void initState() {
    super.initState();
    _initializeHome();
  }

  @override
  void dispose() {
    _addressPageController.dispose();
    _backgroundStyle.dispose();
    super.dispose();
  }

  int? get _selectedAddressId {
    if (_addresses.isNotEmpty &&
        _selectedAddressIndex >= 0 &&
        _selectedAddressIndex < _addresses.length) {
      return _addresses[_selectedAddressIndex].id;
    }
    return _weatherData?.address.id;
  }

  /// 启动首页。
  ///
  /// 先展示 app_state 中记录的上一次定位城市本地天气，随后后台重新定位。
  /// 只有启动定位成功且地区变化时，才自动切换到新的定位城市。
  Future<void> _initializeHome() async {
    _logWeatherHome('启动首页，开始读取本地缓存和定位状态');
    await _loadStartupWeatherCache();
    await _refreshLocationThenAllWeather(
      triggerSource: '应用启动',
      allowSwitchWhenDistrictChanged: true,
    );
  }

  /// 先展示上一次定位城市的本地天气，避免启动时页面长时间空白。
  Future<void> _loadStartupWeatherCache() async {
    try {
      final addresses = await AddressDatabaseService.instance
          .fetchAllAddressRecords();
      final lastLocatedAddress = await AddressDatabaseService.instance
          .fetchLastLocatedAddress();
      _logWeatherHome(
        '本地启动缓存：addressCount=${addresses.length}, '
        'lastLocatedId=${lastLocatedAddress?.id}, '
        'lastLocatedDistrict=${lastLocatedAddress?.district}',
      );
      if (addresses.isEmpty) {
        return;
      }

      final savedWeatherByAddressId = await _loadSavedWeatherDataForAddresses(
        addresses,
      );
      if (savedWeatherByAddressId.isEmpty) {
        if (mounted) {
          setState(() {
            _addresses = addresses;
            _selectedAddressIndex = _indexOfAddress(
              lastLocatedAddress?.id ?? addresses.first.id,
              addresses,
            );
            _currentLocatedAddressId = lastLocatedAddress?.id;
            _currentLocatedAddress = lastLocatedAddress;
            _statusText = '暂无本地天气，正在刷新...';
          });
          _scheduleAddressPageSync();
        }
        return;
      }

      if (!mounted) {
        return;
      }

      final startupAddressId = lastLocatedAddress?.id ?? addresses.first.id;
      final displayData =
          savedWeatherByAddressId[startupAddressId] ??
          savedWeatherByAddressId.values.first;

      setState(() {
        _addresses = addresses;
        _selectedAddressIndex = _indexOfAddress(
          displayData.address.id,
          addresses,
        );
        _weatherData = displayData;
        _weatherDataByAddressId
          ..clear()
          ..addAll(savedWeatherByAddressId);
        _currentLocatedAddressId = lastLocatedAddress?.id;
        _currentLocatedAddress = lastLocatedAddress;
        _statusText = '已读取本地天气，正在刷新...';
      });
      _backgroundStyle.value = displayData.background;
      _scheduleAddressPageSync();
    } catch (error) {
      _showStatus('读取本地天气失败，正在继续刷新：$error');
    }
  }

  /// 重新定位当前位置。
  ///
  /// 这个方法只负责定位和地址落库，不请求天气，也不主动切换当前页面。
  Future<AddressRecord?> _refreshCurrentLocation({
    required String triggerSource,
  }) async {
    if (_isLocating) {
      return null;
    }

    final selectedAddressId = _selectedAddressId;
    setState(() {
      _isLocating = true;
      _statusText = '$triggerSource：正在获取当前位置...';
    });

    try {
      final address = await _locationAddressService
          .captureAndSaveCurrentAddress();
      final addressId = address.id;
      _logWeatherHome(
        '$triggerSource：定位成功 id=$addressId, '
        'province=${address.province}, city=${address.city}, '
        'district=${address.district}, detail=${address.detailAddress}',
      );
      if (addressId != null) {
        await AddressDatabaseService.instance.saveLastLocatedAddressId(
          addressId,
        );
      }

      final addresses = await AddressDatabaseService.instance
          .fetchAllAddressRecords();
      if (!mounted) {
        return address;
      }

      setState(() {
        _addresses = addresses.isEmpty ? [address] : addresses;
        _selectedAddressIndex = _indexOfAddress(
          selectedAddressId ?? _selectedAddressId,
          _addresses,
        );
        _currentLocatedAddressId = addressId;
        _currentLocatedAddress = address;
        _statusText = '$triggerSource：定位已更新';
      });
      _scheduleAddressPageSync();
      return address;
    } on LocationAddressException catch (error) {
      _showStatus('$triggerSource：${error.message}，将继续刷新天气。');
      return null;
    } catch (error) {
      _showStatus('$triggerSource：定位失败，$error，将继续刷新天气。');
      return null;
    } finally {
      if (mounted) {
        setState(() {
          _isLocating = false;
        });
      }
    }
  }

  /// 先尝试定位，再刷新所有位置天气。
  ///
  /// 定位失败不会中断天气刷新。只有启动场景允许在地区变化后自动切到新定位城市。
  Future<void> _refreshLocationThenAllWeather({
    required String triggerSource,
    required bool allowSwitchWhenDistrictChanged,
  }) async {
    final oldLocatedAddress =
        _currentLocatedAddress ??
        await AddressDatabaseService.instance.fetchLastLocatedAddress();
    _logWeatherHome(
      '$triggerSource：开始定位后刷新，oldDistrict=${oldLocatedAddress?.district}, '
      'allowSwitch=$allowSwitchWhenDistrictChanged',
    );
    final newLocatedAddress = await _refreshCurrentLocation(
      triggerSource: triggerSource,
    );

    final shouldSwitch =
        mounted &&
        allowSwitchWhenDistrictChanged &&
        newLocatedAddress?.id != null &&
        !_isSameDistrict(oldLocatedAddress, newLocatedAddress!);
    _logWeatherHome(
      '$triggerSource：定位后刷新，newDistrict=${newLocatedAddress?.district}, '
      'shouldSwitch=$shouldSwitch',
    );
    if (shouldSwitch) {
      _selectAddressById(newLocatedAddress.id);
    }

    await _refreshAllWeather(triggerSource: triggerSource);
  }

  /// 处理顶部位置横向滑动。
  ///
  /// 这里不重新定位，只根据用户选中的地址表记录加载对应天气；如果本地没有保存过
  /// 天气数据，再用该地址经纬度请求一次彩云接口。
  Future<void> _handleAddressPageChanged(int index) async {
    if (index < 0 || index >= _addresses.length) {
      return;
    }

    final address = _addresses[index];
    final addressId = address.id;
    if (addressId == null) {
      _showStatus('切换失败：地址记录缺少 id');
      return;
    }

    if (index == _selectedAddressIndex &&
        _weatherDataByAddressId.containsKey(addressId)) {
      return;
    }

    final requestId = _addressSwitchRequestId + 1;
    _addressSwitchRequestId = requestId;
    final addressTitle = _locationTitle(address);

    final cachedData = _weatherDataByAddressId[addressId];
    if (cachedData != null) {
      // 目标页已有完整数据时，只更新业务状态和背景层，不重建整个 PageView。
      _selectedAddressIndex = index;
      _weatherData = cachedData;
      _statusText = '已切换到$addressTitle';
      _backgroundStyle.value = cachedData.background;
      return;
    }

    setState(() {
      _selectedAddressIndex = index;
      _statusText = '正在切换到$addressTitle...';
    });

    try {
      // 让 PageView 先完成落页绘制，再读取和解析天气数据，减少切页瞬间掉帧。
      await Future<void>.delayed(const Duration(milliseconds: 80));
      if (!mounted || requestId != _addressSwitchRequestId) {
        return;
      }

      final displayData = await _loadWeatherForAddress(address);

      if (!mounted || requestId != _addressSwitchRequestId) {
        return;
      }

      _backgroundStyle.value = displayData.background;
      setState(() {
        _weatherData = displayData;
        _weatherDataByAddressId[addressId] = displayData;
        _statusText = '已切换到$addressTitle';
      });
    } on CaiyunWeatherException catch (error) {
      if (requestId == _addressSwitchRequestId) {
        _showStatus('切换到$addressTitle失败：${error.message}');
      }
    } catch (error) {
      if (requestId == _addressSwitchRequestId) {
        _showStatus('切换到$addressTitle失败：$error');
      }
    }
  }

  /// 刷新所有已保存位置的天气。
  ///
  /// 当前页面城市优先请求并立即更新 UI；其他城市随后并发刷新。整个流程不定位、
  /// 不修改 app_state，也不强制切换 PageView。
  Future<void> _refreshAllWeather({required String triggerSource}) async {
    if (_isRefreshingWeather) {
      return;
    }

    final selectedAddressId = _selectedAddressId;
    final addresses = await AddressDatabaseService.instance
        .fetchAllAddressRecords();
    if (!mounted) {
      return;
    }
    if (addresses.isEmpty) {
      setState(() {
        _addresses = const [];
        _weatherData = null;
        _weatherDataByAddressId.clear();
        _statusText = '$triggerSource：暂无位置，请先添加位置。';
      });
      return;
    }

    final selectedIndex = _indexOfAddress(
      selectedAddressId ?? _currentLocatedAddressId ?? addresses.first.id,
      addresses,
    );
    final selectedAddress = addresses[selectedIndex];
    _logWeatherHome(
      '$triggerSource：开始刷新所有位置天气，addressCount=${addresses.length}, '
      'selectedId=${selectedAddress.id}, selected=${_locationTitle(selectedAddress)}',
    );
    setState(() {
      _addresses = addresses;
      _selectedAddressIndex = selectedIndex;
      _isRefreshingWeather = true;
      _statusText = '$triggerSource：正在更新天气...';
    });
    _scheduleAddressPageSync();

    final failures = <String>[];
    try {
      final selectedResult = await _refreshWeatherForAddress(selectedAddress);
      if (mounted && selectedResult.data != null) {
        final displayData = selectedResult.data!;
        _logWeatherHome(
          '$triggerSource：当前城市天气刷新成功，'
          'addressId=${displayData.address.id}, '
          'title=${_locationTitle(displayData.address)}',
        );
        _backgroundStyle.value = displayData.background;
        setState(() {
          _weatherData = displayData;
          if (displayData.address.id != null) {
            _weatherDataByAddressId[displayData.address.id!] = displayData;
          }
          _statusText = '$triggerSource：当前城市天气已更新';
        });
      } else if (selectedResult.error != null) {
        _logWeatherHome(
          '$triggerSource：当前城市天气刷新失败，'
          'addressId=${selectedAddress.id}, error=${selectedResult.error}',
        );
        failures.add(_locationTitle(selectedAddress));
      }

      final otherAddresses = addresses
          .where((address) => address.id != selectedAddress.id)
          .toList();
      final otherResults = await _refreshWeatherForAddresses(otherAddresses);
      if (!mounted) {
        return;
      }

      final updatedWeather = <int, WeatherDisplayData>{};
      for (final result in otherResults) {
        final addressId = result.address.id;
        if (result.data != null && addressId != null) {
          _logWeatherHome(
            '$triggerSource：后台城市天气刷新成功，'
            'addressId=$addressId, title=${_locationTitle(result.address)}',
          );
          updatedWeather[addressId] = result.data!;
        } else if (result.error != null) {
          _logWeatherHome(
            '$triggerSource：后台城市天气刷新失败，'
            'addressId=$addressId, title=${_locationTitle(result.address)}, '
            'error=${result.error}',
          );
          failures.add(_locationTitle(result.address));
        }
      }

      setState(() {
        _weatherDataByAddressId.addAll(updatedWeather);
        if (failures.isEmpty) {
          _statusText = '$triggerSource：所有位置天气已更新';
        } else if (failures.length == addresses.length) {
          _statusText = '$triggerSource：天气更新失败，请检查网络。';
        } else {
          _statusText = '$triggerSource：部分位置更新失败：${failures.join('、')}';
        }
      });
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshingWeather = false;
        });
      }
    }
  }

  Future<_AddressWeatherRefreshResult> _refreshWeatherForAddress(
    AddressRecord address,
  ) async {
    try {
      final data = await _fetchWeatherDisplayData(address, forceNetwork: true);
      return _AddressWeatherRefreshResult(address: address, data: data);
    } catch (error) {
      return _AddressWeatherRefreshResult(address: address, error: error);
    }
  }

  Future<List<_AddressWeatherRefreshResult>> _refreshWeatherForAddresses(
    List<AddressRecord> addresses,
  ) async {
    if (addresses.isEmpty) {
      return const [];
    }

    const maxConcurrency = 3;
    final results = <_AddressWeatherRefreshResult>[];
    var nextIndex = 0;

    Future<void> worker() async {
      while (nextIndex < addresses.length) {
        final currentIndex = nextIndex;
        nextIndex += 1;
        final result = await _refreshWeatherForAddress(addresses[currentIndex]);
        results.add(result);
      }
    }

    final workerCount = math.min(maxConcurrency, addresses.length);
    await Future.wait([
      for (var index = 0; index < workerCount; index += 1) worker(),
    ]);
    return results;
  }

  Future<WeatherDisplayData> _loadWeatherForAddress(
    AddressRecord address,
  ) async {
    return _fetchWeatherDisplayData(address, forceNetwork: false);
  }

  Future<WeatherDisplayData> _fetchWeatherDisplayData(
    AddressRecord address, {
    required bool forceNetwork,
  }) async {
    final addressId = address.id;
    if (addressId == null) {
      throw const CaiyunWeatherException('地址记录缺少 id，无法关联保存天气数据。');
    }

    final savedWeather = await AddressDatabaseService.instance
        .fetchLatestWeatherByAddressId(addressId);
    final currentWeather = forceNetwork
        ? await _caiyunWeatherService.fetchAndSaveWeather(address)
        : savedWeather ??
              await _caiyunWeatherService.fetchAndSaveWeather(address);
    final yesterdayWeather = await AddressDatabaseService.instance
        .fetchWeatherByAddressIdAndDate(
          addressId: addressId,
          date: DateTime.now().subtract(const Duration(days: 1)),
        );

    return WeatherDisplayData.fromRecords(
      address: address,
      currentRecord: currentWeather,
      yesterdayRecord: yesterdayWeather,
    );
  }

  void _selectAddressById(int? addressId) {
    if (addressId == null || _addresses.isEmpty) {
      return;
    }

    final index = _indexOfAddress(addressId, _addresses);
    final displayData = _weatherDataByAddressId[addressId];
    setState(() {
      _selectedAddressIndex = index;
      if (displayData != null) {
        _weatherData = displayData;
      }
    });
    if (displayData != null) {
      _backgroundStyle.value = displayData.background;
    }
    _scheduleAddressPageSync();
  }

  bool _isSameDistrict(AddressRecord? oldAddress, AddressRecord newAddress) {
    final oldDistrict = oldAddress?.district.trim();
    final newDistrict = newAddress.district.trim();
    if (oldDistrict == null || oldDistrict.isEmpty || newDistrict.isEmpty) {
      return false;
    }
    return oldDistrict == newDistrict;
  }

  /// 预读地址表中已有的本地天气缓存。
  ///
  /// 横向切页时如果目标页已经有展示数据，PageView 只需要切换现有 Widget，
  /// 不会先显示占位页再触发异步加载，滑动会更连贯。
  Future<Map<int, WeatherDisplayData>> _loadSavedWeatherDataForAddresses(
    List<AddressRecord> addresses,
  ) async {
    final result = <int, WeatherDisplayData>{};
    for (final address in addresses) {
      final addressId = address.id;
      if (addressId == null) {
        continue;
      }

      final weather = await AddressDatabaseService.instance
          .fetchLatestWeatherByAddressId(addressId);
      if (weather == null) {
        continue;
      }

      final yesterdayWeather = await AddressDatabaseService.instance
          .fetchWeatherByAddressIdAndDate(
            addressId: addressId,
            date: DateTime.now().subtract(const Duration(days: 1)),
          );
      result[addressId] = WeatherDisplayData.fromRecords(
        address: address,
        currentRecord: weather,
        yesterdayRecord: yesterdayWeather,
      );
    }
    return result;
  }

  Future<void> _reloadAddressPagesFromStorage() async {
    final addresses = await AddressDatabaseService.instance
        .fetchAllAddressRecords();
    final savedWeatherByAddressId = await _loadSavedWeatherDataForAddresses(
      addresses,
    );
    if (!mounted) {
      return;
    }

    final selectedAddressId = _selectedAddressId ?? _weatherData?.address.id;
    final selectedIndex = _indexOfAddress(selectedAddressId, addresses);
    final selectedAddress = addresses.isEmpty ? null : addresses[selectedIndex];
    final selectedWeatherData = selectedAddress?.id == null
        ? null
        : savedWeatherByAddressId[selectedAddress!.id];
    final fallbackWeatherData = savedWeatherByAddressId.isEmpty
        ? null
        : savedWeatherByAddressId.values.first;

    setState(() {
      _addresses = addresses;
      _selectedAddressIndex = selectedIndex;
      _weatherDataByAddressId
        ..clear()
        ..addAll(savedWeatherByAddressId);
      _weatherData = selectedWeatherData ?? fallbackWeatherData;
      _statusText = addresses.isEmpty ? '暂无位置，请添加位置。' : '位置已更新';
    });
    _backgroundStyle.value =
        (selectedWeatherData ?? fallbackWeatherData)?.background ??
        _defaultBackground;
    _scheduleAddressPageSync();
  }

  int _indexOfAddress(int? addressId, List<AddressRecord> addresses) {
    if (addressId == null) {
      return 0;
    }
    final index = addresses.indexWhere((address) => address.id == addressId);
    return index < 0 ? 0 : index;
  }

  void _scheduleAddressPageSync() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_addressPageController.hasClients ||
          _addresses.isEmpty) {
        return;
      }
      final pageIndex = _selectedAddressIndex
          .clamp(0, _addresses.length - 1)
          .toInt();
      _addressPageController.jumpToPage(pageIndex);
    });
  }

  void _showStatus(String message) {
    if (!mounted) {
      return;
    }
    _logWeatherHome('状态更新：$message');
    setState(() {
      _statusText = message;
    });
  }

  void _logWeatherHome(String message) {
    debugPrint('[AiKraiSky][WeatherHome] $message');
  }

  @override
  Widget build(BuildContext context) {
    final weatherData = _weatherData;
    final pageAddresses = _addresses.isEmpty && weatherData != null
        ? [weatherData.address]
        : _addresses;
    final safeSelectedIndex = pageAddresses.isEmpty
        ? 0
        : _selectedAddressIndex.clamp(0, pageAddresses.length - 1).toInt();
    final pageContent = SafeArea(
      bottom: false,
      child: pageAddresses.isEmpty
          ? Stack(
              children: [
                RefreshIndicator(
                  color: Colors.white,
                  backgroundColor: Colors.black26,
                  onRefresh: () => _refreshLocationThenAllWeather(
                    triggerSource: '下拉重新定位',
                    allowSwitchWhenDistrictChanged: true,
                  ),
                  child: _EmptyWeatherView(statusText: _statusText),
                ),
                Positioned(
                  left: 18,
                  top: 10,
                  child: IconButton(
                    tooltip: '管理位置',
                    iconSize: 30,
                    color: Colors.white,
                    icon: const Icon(Icons.add),
                    onPressed: _openLocationManagementPage,
                  ),
                ),
              ],
            )
          : PageView.builder(
              controller: _addressPageController,
              allowImplicitScrolling: true,
              physics: const PageScrollPhysics(parent: ClampingScrollPhysics()),
              itemCount: pageAddresses.length,
              onPageChanged: _handleAddressPageChanged,
              itemBuilder: (context, index) {
                final address = pageAddresses[index];
                final addressId = address.id;
                final pageWeatherData = addressId == null
                    ? null
                    : _weatherDataByAddressId[addressId];
                return _WeatherAddressPage(
                  address: address,
                  data: pageWeatherData,
                  addresses: pageAddresses,
                  selectedAddressIndex: index,
                  currentLocatedAddressId: _currentLocatedAddressId,
                  currentLocatedAddress: _currentLocatedAddress,
                  statusText: index == safeSelectedIndex
                      ? _statusText
                      : '正在读取天气数据...',
                  isLoading:
                      (_isLocating || _isRefreshingWeather) &&
                      index == safeSelectedIndex,
                  onRefresh: () => _refreshAllWeather(triggerSource: '下拉刷新'),
                  onLargeRefresh: () => _handleLargePullRefresh(address),
                  onManageLocations: _openLocationManagementPage,
                  onMenuAction: _handleMenuAction,
                );
              },
            ),
    );

    return Scaffold(
      body: ValueListenableBuilder<WeatherBackgroundStyle>(
        valueListenable: _backgroundStyle,
        child: pageContent,
        builder: (context, background, child) {
          return AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(background.topColor),
                  Color(background.bottomColor),
                ],
              ),
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: _WeatherSceneBackground(background: background),
                ),
                ?child,
              ],
            ),
          );
        },
      ),
    );
  }

  void _handleMenuAction(_WeatherMenuAction action) {
    switch (action) {
      case _WeatherMenuAction.refresh:
        _refreshAllWeather(triggerSource: '手动刷新');
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

  Future<void> _handleLargePullRefresh(AddressRecord address) {
    _logWeatherHome(
      '大幅下拉触发：addressId=${address.id}, title=${_locationTitle(address)}, '
      'currentLocatedId=$_currentLocatedAddressId',
    );
    if (_isCurrentLocatedAddress(
      address: address,
      currentLocatedAddressId: _currentLocatedAddressId,
      currentLocatedAddress: _currentLocatedAddress,
    )) {
      return _refreshLocationThenAllWeather(
        triggerSource: '下拉重新定位',
        allowSwitchWhenDistrictChanged: false,
      );
    }
    return _refreshAllWeather(triggerSource: '下拉刷新');
  }

  Future<void> _openLocationManagementPage() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => LocationManagementPage(
          currentLocatedAddressId: _currentLocatedAddressId,
          currentLocatedAddress: _currentLocatedAddress,
        ),
      ),
    );
    if (changed == true) {
      await _reloadAddressPagesFromStorage();
    }
  }
}

enum _WeatherMenuAction { refresh, addressTable, weatherTable }

class _AddressWeatherRefreshResult {
  const _AddressWeatherRefreshResult({
    required this.address,
    this.data,
    this.error,
  });

  final AddressRecord address;
  final WeatherDisplayData? data;
  final Object? error;
}

class _WeatherAddressPage extends StatefulWidget {
  const _WeatherAddressPage({
    required this.address,
    required this.data,
    required this.addresses,
    required this.selectedAddressIndex,
    required this.currentLocatedAddressId,
    required this.currentLocatedAddress,
    required this.statusText,
    required this.isLoading,
    required this.onRefresh,
    required this.onLargeRefresh,
    required this.onManageLocations,
    required this.onMenuAction,
  });

  final AddressRecord address;
  final WeatherDisplayData? data;
  final List<AddressRecord> addresses;
  final int selectedAddressIndex;
  final int? currentLocatedAddressId;
  final AddressRecord? currentLocatedAddress;
  final String statusText;
  final bool isLoading;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onLargeRefresh;
  final VoidCallback onManageLocations;
  final ValueChanged<_WeatherMenuAction> onMenuAction;

  @override
  State<_WeatherAddressPage> createState() => _WeatherAddressPageState();
}

class _WeatherAddressPageState extends State<_WeatherAddressPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final weatherData = widget.data;
    return RepaintBoundary(
      child: _TwoStageRefreshIndicator(
        onRefresh: widget.onRefresh,
        onLargeRefresh: widget.onLargeRefresh,
        child: weatherData == null
            ? ListView(
                key: PageStorageKey('weather-placeholder-${widget.address.id}'),
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
                children: [
                  _AddressWeatherPlaceholder(
                    address: widget.address,
                    addresses: widget.addresses,
                    selectedAddressIndex: widget.selectedAddressIndex,
                    currentLocatedAddressId: widget.currentLocatedAddressId,
                    currentLocatedAddress: widget.currentLocatedAddress,
                    statusText: widget.statusText,
                    isLoading: widget.isLoading,
                    onManageLocations: widget.onManageLocations,
                    onMenuAction: widget.onMenuAction,
                  ),
                ],
              )
            : ListView(
                key: PageStorageKey('weather-page-${widget.address.id}'),
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
                children: [
                  _CurrentWeatherHero(
                    data: weatherData,
                    addresses: widget.addresses,
                    selectedAddressIndex: widget.selectedAddressIndex,
                    currentLocatedAddressId: widget.currentLocatedAddressId,
                    currentLocatedAddress: widget.currentLocatedAddress,
                    isLoading: widget.isLoading,
                    onManageLocations: widget.onManageLocations,
                    onMenuAction: widget.onMenuAction,
                  ),
                  const SizedBox(height: 16),
                  _HourlyWeatherModule(
                    items: weatherData.hourly,
                    sunTimes: weatherData.sunTimes,
                  ),
                  const SizedBox(height: 16),
                  _DailyWeatherModule(items: weatherData.daily),
                  const SizedBox(height: 16),
                  _AirQualityModule(data: weatherData.airQuality),
                  const SizedBox(height: 16),
                  _LifeIndexModule(items: weatherData.lifeIndices),
                ],
              ),
      ),
    );
  }
}

/// 两段式下拉刷新。
///
/// 下拉超过屏幕高度 15% 后释放刷新天气；超过 28% 后释放进入大幅刷新，
/// 是否重新定位交给页面按“当前页是否定位城市”判断。
class _TwoStageRefreshIndicator extends StatefulWidget {
  const _TwoStageRefreshIndicator({
    required this.child,
    required this.onRefresh,
    required this.onLargeRefresh,
  });

  static const _smallRefreshRatio = 0.15;
  static const _largeRefreshRatio = 0.28;

  final Widget child;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onLargeRefresh;

  @override
  State<_TwoStageRefreshIndicator> createState() =>
      _TwoStageRefreshIndicatorState();
}

class _TwoStageRefreshIndicatorState extends State<_TwoStageRefreshIndicator> {
  double _currentPullExtent = 0;
  double? _pointerStartY;
  bool _isAtTop = true;
  bool _isPointerDown = false;
  bool _isHandlingRefresh = false;
  String _refreshingText = '正在刷新天气';

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification.depth != 0 || notification.metrics.axis != Axis.vertical) {
      return false;
    }

    if (notification is ScrollStartNotification) {
      _isAtTop = notification.metrics.extentBefore == 0;
    } else if (notification is ScrollUpdateNotification &&
        notification.metrics.extentBefore == 0) {
      _isAtTop = true;
    } else if (notification is OverscrollNotification &&
        notification.metrics.extentBefore == 0) {
      _isAtTop = true;
    } else if (notification is ScrollEndNotification) {
      _isAtTop = notification.metrics.extentBefore == 0;
    }

    return false;
  }

  double _smallRefreshOffset(BuildContext context) {
    return MediaQuery.sizeOf(context).height *
        _TwoStageRefreshIndicator._smallRefreshRatio;
  }

  double _largeRefreshOffset(BuildContext context) {
    return MediaQuery.sizeOf(context).height *
        _TwoStageRefreshIndicator._largeRefreshRatio;
  }

  void _resetPullState({bool keepPointer = false}) {
    _currentPullExtent = 0;
    _pointerStartY = null;
    if (!keepPointer) {
      _isPointerDown = false;
    }
  }

  Future<void> _handleRelease(double releasePullExtent) async {
    if (_isHandlingRefresh) {
      return;
    }

    final smallOffset = _smallRefreshOffset(context);
    final largeOffset = _largeRefreshOffset(context);
    final isLargeRefresh = releasePullExtent >= largeOffset;
    final isSmallRefresh = releasePullExtent >= smallOffset;
    debugPrint(
      '[AiKraiSky][Refresh] 释放下拉刷新：'
      'releasePull=${releasePullExtent.toStringAsFixed(1)}, '
      'small=${smallOffset.toStringAsFixed(1)}, '
      'large=${largeOffset.toStringAsFixed(1)}, '
      'stage=${isLargeRefresh
          ? 'large'
          : isSmallRefresh
          ? 'small'
          : 'none'}',
    );

    if (!isLargeRefresh && !isSmallRefresh) {
      return;
    }

    if (mounted) {
      setState(() {
        _isHandlingRefresh = true;
        _refreshingText = isLargeRefresh ? '正在重新定位并刷新' : '正在刷新天气';
      });
    } else {
      _isHandlingRefresh = true;
      _refreshingText = isLargeRefresh ? '正在重新定位并刷新' : '正在刷新天气';
    }
    try {
      if (isLargeRefresh) {
        await widget.onLargeRefresh();
      } else {
        await widget.onRefresh();
      }
    } finally {
      if (mounted) {
        setState(() {
          _isHandlingRefresh = false;
        });
      } else {
        _isHandlingRefresh = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final smallOffset = _smallRefreshOffset(context);
    final largeOffset = _largeRefreshOffset(context);
    final showGuide =
        _isPointerDown &&
        _isAtTop &&
        _currentPullExtent > 8 &&
        !_isHandlingRefresh;
    final actionText = _currentPullExtent >= largeOffset
        ? '释放后重新定位并刷新'
        : _currentPullExtent >= smallOffset
        ? '释放后刷新天气'
        : '继续下拉刷新天气';

    return Listener(
      onPointerDown: (event) {
        setState(() {
          _resetPullState(keepPointer: true);
          _isPointerDown = true;
          _pointerStartY = _isAtTop ? event.position.dy : null;
        });
      },
      onPointerMove: (event) {
        if (_isAtTop) {
          final pointerStartY = _pointerStartY ?? event.position.dy;
          _pointerStartY = pointerStartY;
          final pullExtent = math.max(0.0, event.position.dy - pointerStartY);
          setState(() {
            _currentPullExtent = pullExtent;
          });
        }
      },
      onPointerUp: (_) {
        final releasePullExtent = _currentPullExtent;
        debugPrint(
          '[AiKraiSky][Refresh] 手势结束：'
          'releasePull=${releasePullExtent.toStringAsFixed(1)}, '
          'small=${smallOffset.toStringAsFixed(1)}, '
          'large=${largeOffset.toStringAsFixed(1)}',
        );
        setState(() {
          _resetPullState();
        });
        _handleRelease(releasePullExtent);
      },
      onPointerCancel: (_) {
        setState(_resetPullState);
      },
      child: Stack(
        children: [
          NotificationListener<ScrollNotification>(
            onNotification: _handleScrollNotification,
            child: widget.child,
          ),
          IgnorePointer(
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 120),
              opacity: showGuide ? 1 : 0,
              child: _PullGuideOverlay(
                smallOffset: smallOffset,
                largeOffset: largeOffset,
                actionText: actionText,
                pullExtent: _currentPullExtent,
              ),
            ),
          ),
          IgnorePointer(
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 120),
              opacity: _isHandlingRefresh ? 1 : 0,
              child: _PullRefreshingOverlay(text: _refreshingText),
            ),
          ),
        ],
      ),
    );
  }
}

class _PullRefreshingOverlay extends StatelessWidget {
  const _PullRefreshingOverlay({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: Stack(
        children: [
          Positioned(
            top: 18,
            left: 0,
            right: 0,
            child: Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.24),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.20),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white.withValues(alpha: 0.92),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        text,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PullGuideOverlay extends StatelessWidget {
  const _PullGuideOverlay({
    required this.smallOffset,
    required this.largeOffset,
    required this.actionText,
    required this.pullExtent,
  });

  final double smallOffset;
  final double largeOffset;
  final String actionText;
  final double pullExtent;

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: Stack(
        children: [
          // 暂时只显示文字提示，线条保留代码便于后续需要时恢复。
          // _PullGuideLine(
          //   top: smallOffset,
          //   text: '12% 释放刷新天气',
          //   isActive: pullExtent >= smallOffset,
          // ),
          // _PullGuideLine(
          //   top: largeOffset,
          //   text: '20% 释放重新定位',
          //   isActive: pullExtent >= largeOffset,
          // ),
          Positioned(
            top: math.max(
              18,
              math.min(
                pullExtent - 36,
                math.max(smallOffset, largeOffset) + 26,
              ),
            ),
            left: 0,
            right: 0,
            child: Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.20),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: Text(
                    actionText,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ignore: unused_element
class _PullGuideLine extends StatelessWidget {
  const _PullGuideLine({
    required this.top,
    required this.text,
    required this.isActive,
  });

  final double top;
  final String text;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final color = Colors.white.withValues(alpha: isActive ? 0.72 : 0.28);
    return Positioned(
      top: top,
      left: 18,
      right: 18,
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                color: color,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 8,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: isActive ? 0.22 : 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              child: Text(
                text,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddressWeatherPlaceholder extends StatelessWidget {
  const _AddressWeatherPlaceholder({
    required this.address,
    required this.addresses,
    required this.selectedAddressIndex,
    required this.currentLocatedAddressId,
    required this.currentLocatedAddress,
    required this.statusText,
    required this.isLoading,
    required this.onManageLocations,
    required this.onMenuAction,
  });

  final AddressRecord address;
  final List<AddressRecord> addresses;
  final int selectedAddressIndex;
  final int? currentLocatedAddressId;
  final AddressRecord? currentLocatedAddress;
  final String statusText;
  final bool isLoading;
  final VoidCallback onManageLocations;
  final ValueChanged<_WeatherMenuAction> onMenuAction;

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    final heroHeight = screenHeight < 760 ? 390.0 : 470.0;

    return SizedBox(
      height: heroHeight,
      child: Column(
        children: [
          _WeatherTopBar(
            address: address,
            addresses: addresses,
            selectedAddressIndex: selectedAddressIndex,
            currentLocatedAddressId: currentLocatedAddressId,
            currentLocatedAddress: currentLocatedAddress,
            isLoading: isLoading,
            onManageLocations: onManageLocations,
            onMenuAction: onMenuAction,
          ),
          Expanded(
            child: Center(
              child: Text(
                statusText,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 当前天气主视觉模块。
class _CurrentWeatherHero extends StatelessWidget {
  const _CurrentWeatherHero({
    required this.data,
    required this.addresses,
    required this.selectedAddressIndex,
    required this.currentLocatedAddressId,
    required this.currentLocatedAddress,
    required this.isLoading,
    required this.onManageLocations,
    required this.onMenuAction,
  });

  final WeatherDisplayData data;
  final List<AddressRecord> addresses;
  final int selectedAddressIndex;
  final int? currentLocatedAddressId;
  final AddressRecord? currentLocatedAddress;
  final bool isLoading;
  final VoidCallback onManageLocations;
  final ValueChanged<_WeatherMenuAction> onMenuAction;

  @override
  Widget build(BuildContext context) {
    final current = data.current;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final heroHeight = screenHeight < 760 ? 390.0 : 470.0;

    return SizedBox(
      height: heroHeight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _WeatherTopBar(
            address: data.address,
            addresses: addresses,
            selectedAddressIndex: selectedAddressIndex,
            currentLocatedAddressId: currentLocatedAddressId,
            currentLocatedAddress: currentLocatedAddress,
            isLoading: isLoading,
            onManageLocations: onManageLocations,
            onMenuAction: onMenuAction,
          ),
          const Spacer(),
          Wrap(
            spacing: 10,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _CurrentMetricText(
                '${current.windDirection} ${current.windLevel}',
              ),
              _CurrentMetricText(
                '风速 ${current.windSpeed.toStringAsFixed(1)} km/h',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                current.temperature.toStringAsFixed(1),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 74,
                  height: 0.9,
                  fontWeight: FontWeight.w300,
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(bottom: 36),
                child: Text(
                  '°C',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 23,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 18),
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Text(
                  current.weatherText,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '${current.temperatureMax.toStringAsFixed(1)}°C / ${current.temperatureMin.toStringAsFixed(1)}°C',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _CurrentMetricText(
                '湿度 ${current.humidityPercent.toStringAsFixed(1)}%',
              ),
              _CurrentMetricText(
                '体感 ${current.apparentTemperature.toStringAsFixed(1)}°C',
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text(
                  current.forecastKeypoint.isEmpty
                      ? '暂无天气预报关键点'
                      : current.forecastKeypoint,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.eco, color: Color(0xFF62F044), size: 22),
                  const SizedBox(width: 4),
                  Text(
                    '${data.airQuality.description} ${data.airQuality.aqi}',
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CurrentMetricText extends StatelessWidget {
  const _CurrentMetricText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 15,
        fontWeight: FontWeight.w400,
      ),
    );
  }
}

/// 顶部城市与操作栏。
class _WeatherTopBar extends StatelessWidget {
  const _WeatherTopBar({
    required this.address,
    required this.addresses,
    required this.selectedAddressIndex,
    required this.currentLocatedAddressId,
    required this.currentLocatedAddress,
    required this.isLoading,
    required this.onManageLocations,
    required this.onMenuAction,
  });

  final AddressRecord address;
  final List<AddressRecord> addresses;
  final int selectedAddressIndex;
  final int? currentLocatedAddressId;
  final AddressRecord? currentLocatedAddress;
  final bool isLoading;
  final VoidCallback onManageLocations;
  final ValueChanged<_WeatherMenuAction> onMenuAction;

  @override
  Widget build(BuildContext context) {
    final safeSelectedIndex = addresses.isEmpty
        ? 0
        : selectedAddressIndex.clamp(0, addresses.length - 1).toInt();

    return SizedBox(
      height: 88,
      child: Stack(
        children: [
          Align(
            alignment: Alignment.topLeft,
            child: IconButton(
              tooltip: '管理位置',
              onPressed: onManageLocations,
              iconSize: 30,
              color: Colors.white,
              icon: const Icon(Icons.add),
            ),
          ),
          Align(
            alignment: Alignment.topRight,
            child: PopupMenuButton<_WeatherMenuAction>(
              icon: const Icon(Icons.more_vert, color: Colors.white, size: 28),
              color: Colors.white,
              onSelected: onMenuAction,
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: _WeatherMenuAction.refresh,
                  child: Text('刷新天气'),
                ),
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
          ),
          Align(
            alignment: Alignment.topCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                SizedBox(
                  width: 240,
                  height: 36,
                  child: _LocationTitlePage(
                    address: address,
                    isCurrentLocation: _isCurrentLocatedAddress(
                      address: address,
                      currentLocatedAddressId: currentLocatedAddressId,
                      currentLocatedAddress: currentLocatedAddress,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _LocationPageIndicator(
                  count: addresses.length,
                  selectedIndex: safeSelectedIndex,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LocationTitlePage extends StatelessWidget {
  const _LocationTitlePage({
    required this.address,
    required this.isCurrentLocation,
  });

  final AddressRecord address;
  final bool isCurrentLocation;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(width: 24),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 176),
            child: Text(
              _locationTitle(address),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          SizedBox(
            width: 24,
            child: isCurrentLocation
                ? const Icon(Icons.location_on, color: Colors.white, size: 21)
                : null,
          ),
        ],
      ),
    );
  }
}

class _LocationPageIndicator extends StatelessWidget {
  const _LocationPageIndicator({
    required this.count,
    required this.selectedIndex,
  });

  final int count;
  final int selectedIndex;

  @override
  Widget build(BuildContext context) {
    if (count <= 1) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      height: 10,
      child: Center(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var index = 0; index < count; index += 1) ...[
                if (index > 0) const SizedBox(width: 8),
                _LocationDot(isSelected: index == selectedIndex),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _LocationDot extends StatelessWidget {
  const _LocationDot({required this.isSelected});

  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: 6,
      height: 6,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isSelected ? Colors.white : Colors.transparent,
        border: Border.all(
          color: Colors.white.withValues(alpha: isSelected ? 1 : 0.85),
          width: 1.1,
        ),
      ),
    );
  }
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

bool _isCurrentLocatedAddress({
  required AddressRecord address,
  required int? currentLocatedAddressId,
  required AddressRecord? currentLocatedAddress,
}) {
  final addressId = address.id;
  if (addressId != null &&
      currentLocatedAddressId != null &&
      addressId == currentLocatedAddressId) {
    return true;
  }

  final currentDistrict = currentLocatedAddress?.district.trim();
  if (currentDistrict == null || currentDistrict.isEmpty) {
    return false;
  }

  // 地址保存规则按“区”更新/新增，所以 UI 也用同一区作为当前位置兜底判断。
  return address.district.trim() == currentDistrict;
}

/// 近 24 小时天气模块。
const _hourlyItemWidth = 48.0;
const _hourlyItemSpacing = 66.0;
const _hourlyGraphTop = 30.0;
const _hourlyGraphBottomPadding = 72.0;

double _hourlyItemLeft(int index) => index * _hourlyItemSpacing;

double _hourlyItemCenterX(int index) {
  return _hourlyItemLeft(index) + _hourlyItemWidth / 2;
}

class _HourlyWeatherModule extends StatelessWidget {
  const _HourlyWeatherModule({required this.items, required this.sunTimes});

  final List<HourlyWeatherDisplay> items;
  final SunTimesDisplay sunTimes;

  @override
  Widget build(BuildContext context) {
    final chartWidth = math.max(
      500.0,
      items.isEmpty
          ? 500.0
          : _hourlyItemLeft(items.length - 1) + _hourlyItemWidth,
    );

    return _GlassPanel(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '24 小时',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              _SunTimeChip(
                icon: Icons.wb_twilight,
                time: sunTimes.sunrise,
                color: const Color(0xFFFFD88D),
              ),
              const SizedBox(width: 10),
              _SunTimeChip(
                icon: Icons.nights_stay,
                time: sunTimes.sunset,
                color: const Color(0xFFC9D8FF),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (items.isEmpty)
            const SizedBox(
              height: 132,
              child: Center(
                child: Text('暂无小时级天气数据', style: TextStyle(color: Colors.white)),
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: chartWidth,
                height: 148,
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
                      bottom: 8,
                      child: SizedBox(
                        height: 54,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            for (
                              var index = 0;
                              index < items.length;
                              index += 1
                            )
                              Positioned(
                                left: _hourlyItemLeft(index),
                                width: _hourlyItemWidth,
                                child: Column(
                                  children: [
                                    _WeatherGlyph(
                                      skycon: items[index].skycon,
                                      size: 24,
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      items[index].timeText,
                                      maxLines: 1,
                                      softWrap: false,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
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
              ),
            ),
        ],
      ),
    );
  }
}

class _SunTimeChip extends StatelessWidget {
  const _SunTimeChip({
    required this.icon,
    required this.time,
    required this.color,
  });

  final IconData icon;
  final String time;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color.withValues(alpha: 0.9), size: 15),
        const SizedBox(width: 3),
        Text(
          time,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white70, fontSize: 11),
        ),
      ],
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
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        children: [
          for (var index = 0; index < items.length; index += 1)
            _DailyForecastRow(
              item: items[index],
              isMuted: index == 0 && !items[index].hasData,
            ),
        ],
      ),
    );
  }
}

class _DailyForecastRow extends StatelessWidget {
  const _DailyForecastRow({required this.item, required this.isMuted});

  final DailyWeatherDisplay item;
  final bool isMuted;

  @override
  Widget build(BuildContext context) {
    final opacity = isMuted ? 0.42 : 1.0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Opacity(
        opacity: opacity,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 320;
            final dayWidth = isNarrow ? 48.0 : 54.0;
            final weatherWidth = isNarrow ? 62.0 : 78.0;
            final iconSize = 24.0;
            final tempWidth = isNarrow ? 88.0 : 98.0;
            final fixedWidth = dayWidth + weatherWidth + iconSize + tempWidth;
            final availableGapWidth = math.max(
              0.0,
              constraints.maxWidth - fixedWidth,
            );
            final gapUnit = availableGapWidth / 3.5;
            final dayWeatherGap = gapUnit * 1.5;
            final weatherIconGap = gapUnit;
            final iconTempGap = gapUnit;
            final temperatureText = item.hasData
                ? '${item.temperatureMax.round()}°C / ${item.temperatureMin.round()}°C'
                : '-- / --';

            return Row(
              children: [
                SizedBox(
                  width: dayWidth,
                  child: Text(
                    item.dayText,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                SizedBox(width: dayWeatherGap),
                SizedBox(
                  width: weatherWidth,
                  child: Text(
                    item.weatherText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                SizedBox(width: weatherIconGap),
                _WeatherGlyph(skycon: item.skycon, size: iconSize),
                SizedBox(width: iconTempGap),
                SizedBox(
                  width: tempWidth,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        temperatureText,
                        maxLines: 1,
                        softWrap: false,
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
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
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final gaugeSize = constraints.maxWidth < 340 ? 104.0 : 112.0;
          const gap = 18.0;
          const metricSpacing = 12.0;
          final metricsWidth = constraints.maxWidth - gaugeSize - gap;
          final metricColumns = metricsWidth >= 168 ? 2 : 1;
          final metricWidth =
              (metricsWidth - metricSpacing * (metricColumns - 1)) /
              metricColumns;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '空气质量',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: gaugeSize,
                    height: gaugeSize,
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
                                fontSize: 30,
                                height: 1,
                                fontWeight: FontWeight.w300,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'AQI',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              data.description,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: gap),
                  Expanded(
                    child: Wrap(
                      spacing: metricSpacing,
                      runSpacing: 8,
                      children: [
                        for (final row in rows)
                          SizedBox(
                            width: metricWidth,
                            child: _AirMetricItem(
                              label: row.$1,
                              value: _formatAirValue(row.$2),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          );
        },
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

class _AirMetricItem extends StatelessWidget {
  const _AirMetricItem({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

/// 生活指数模块。
class _LifeIndexModule extends StatelessWidget {
  const _LifeIndexModule({required this.items});

  final List<LifeIndexDisplay> items;

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 正常手机宽度使用 4 列 2 行，避免生活指数模块被纵向拉长。
          final columnCount = constraints.maxWidth >= 320 ? 4 : 2;
          final spacing = columnCount == 4 ? 10.0 : 12.0;
          final itemWidth =
              (constraints.maxWidth - spacing * (columnCount - 1)) /
              columnCount;
          return Wrap(
            runSpacing: columnCount == 4 ? 14 : 16,
            spacing: spacing,
            children: [
              for (final item in items)
                SizedBox(
                  width: itemWidth,
                  child: _LifeIndexItem(item: item),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _LifeIndexItem extends StatelessWidget {
  const _LifeIndexItem({required this.item});

  final LifeIndexDisplay item;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(
          _lifeIndexIcon(item.iconName),
          color: Color(item.colorValue),
          size: 24,
        ),
        const SizedBox(height: 6),
        Text(
          item.value,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          item.title,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70, fontSize: 11),
        ),
      ],
    );
  }
}

/// 玻璃拟态模块容器。
class _GlassPanel extends StatelessWidget {
  const _GlassPanel({
    required this.child,
    this.padding = const EdgeInsets.all(22),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
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
      physics: const AlwaysScrollableScrollPhysics(),
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

/// 天气背景层，负责绘制柔和云层和天气粒子。
class _WeatherSceneBackground extends StatelessWidget {
  const _WeatherSceneBackground({required this.background});

  final WeatherBackgroundStyle background;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _WeatherScenePainter(background: background));
  }
}

class _WeatherScenePainter extends CustomPainter {
  const _WeatherScenePainter({required this.background});

  final WeatherBackgroundStyle background;

  @override
  void paint(Canvas canvas, Size size) {
    _paintClouds(canvas, size);
    if (background.showRain) {
      _paintRain(canvas, size);
    }
  }

  void _paintClouds(Canvas canvas, Size size) {
    final cloudPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.13)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 22);
    final shadowPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.07)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 34);

    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width * 0.64, size.height * 0.18),
        width: size.width * 0.72,
        height: 160,
      ),
      shadowPaint,
    );
    canvas.drawCircle(Offset(size.width * 0.47, 120), 70, cloudPaint);
    canvas.drawCircle(Offset(size.width * 0.61, 108), 84, cloudPaint);
    canvas.drawCircle(Offset(size.width * 0.78, 130), 62, cloudPaint);

    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width * 0.18, size.height * 0.35),
        width: size.width * 0.45,
        height: 130,
      ),
      shadowPaint,
    );
  }

  void _paintRain(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.25)
      ..strokeWidth = 1.25
      ..strokeCap = StrokeCap.round;
    final strongPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.36)
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    for (var index = 0; index < 58; index += 1) {
      final x = (index * 47.0 + 20) % size.width;
      final y = (index * 89.0 + 30) % size.height;
      final length = index % 4 == 0 ? 78.0 : 52.0;
      final currentPaint = index % 4 == 0 ? strongPaint : paint;
      canvas.drawLine(Offset(x, y), Offset(x + 12, y + length), currentPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _WeatherScenePainter oldDelegate) {
    return oldDelegate.background != background;
  }
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
    final points = <Offset>[];

    for (var index = 0; index < items.length; index += 1) {
      final x = _hourlyItemCenterX(index);
      final graphBottom = size.height - _hourlyGraphBottomPadding;
      final graphHeight = math.max(30.0, graphBottom - _hourlyGraphTop);
      final normalized = (items[index].temperature - minTemperature) / range;
      final y = graphBottom - normalized * graphHeight;
      points.add(Offset(x, y));
    }

    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.72)
      ..strokeWidth = 1.35
      ..style = PaintingStyle.stroke;
    final pointPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final path = _buildSmoothPath(points);
    canvas.drawPath(path, linePaint);

    for (var index = 0; index < points.length; index += 1) {
      final point = points[index];
      canvas.drawCircle(point, 2.25, pointPaint);
      _paintText(
        canvas,
        '${items[index].temperature.round()}°C',
        Offset(point.dx, point.dy - 17),
        fontSize: 12,
      );
    }
  }

  /// 使用 Catmull-Rom 转三次贝塞尔曲线，让小时温度走势更柔顺。
  Path _buildSmoothPath(List<Offset> points) {
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    if (points.length == 1) {
      return path;
    }

    for (var index = 0; index < points.length - 1; index += 1) {
      final p0 = index == 0 ? points[index] : points[index - 1];
      final p1 = points[index];
      final p2 = points[index + 1];
      final p3 = index + 2 < points.length ? points[index + 2] : p2;

      final controlPoint1 = Offset(
        p1.dx + (p2.dx - p0.dx) / 6,
        p1.dy + (p2.dy - p0.dy) / 6,
      );
      final controlPoint2 = Offset(
        p2.dx - (p3.dx - p1.dx) / 6,
        p2.dy - (p3.dy - p1.dy) / 6,
      );
      path.cubicTo(
        controlPoint1.dx,
        controlPoint1.dy,
        controlPoint2.dx,
        controlPoint2.dy,
        p2.dx,
        p2.dy,
      );
    }
    return path;
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
    final strokeWidth = math.max(8.0, size.shortestSide * 0.07);
    final gaugeRect = rect.deflate(strokeWidth / 2 + 2);
    final basePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.22)
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final activePaint = Paint()
      ..color = const Color(0xFF43F35C)
      ..strokeWidth = strokeWidth
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

/// 天气现象图标。
class _WeatherGlyph extends StatelessWidget {
  const _WeatherGlyph({required this.skycon, required this.size});

  final String skycon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final isRain = skycon.contains('RAIN');
    final icon = _weatherIcon(skycon);
    final iconColor = skycon.contains('CLEAR')
        ? const Color(0xFFFFA13A)
        : Colors.white;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(icon, color: iconColor, size: size * 0.86),
          if (isRain)
            Positioned(
              bottom: 0,
              child: CustomPaint(
                size: Size(size * 0.52, size * 0.25),
                painter: _RainDropPainter(),
              ),
            ),
        ],
      ),
    );
  }
}

class _RainDropPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF66E6F2)
      ..strokeWidth = 2.3
      ..strokeCap = StrokeCap.round;
    for (var index = 0; index < 3; index += 1) {
      final x = size.width * (0.2 + index * 0.3);
      canvas.drawLine(
        Offset(x, size.height * 0.15),
        Offset(x - 3, size.height * 0.85),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

IconData _weatherIcon(String skycon) {
  if (skycon.contains('RAIN')) {
    return Icons.cloud;
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

IconData _lifeIndexIcon(String iconName) {
  return switch (iconName) {
    'dressing' => Icons.checkroom,
    'car' => Icons.directions_car,
    'sport' => Icons.sports_basketball,
    'uv' => Icons.wb_sunny,
    'cold' => Icons.medication,
    'comfort' => Icons.sentiment_satisfied,
    'travel' => Icons.luggage,
    'fishing' => Icons.phishing,
    _ => Icons.info,
  };
}
