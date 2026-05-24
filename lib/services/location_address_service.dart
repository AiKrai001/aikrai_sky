import 'dart:async';

import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

import '../models/address_record.dart';
import 'address_database_service.dart';

/// 定位、反地理编码和地址落库的一站式服务。
///
/// 页面只调用 [captureAndSaveCurrentAddress]，不直接处理权限、经纬度、
/// 省市区拆分和 SQLite 写入，避免 UI 层变得臃肿。
class LocationAddressService {
  const LocationAddressService({this.databaseService});

  /// 定位插件已经传了 timeLimit，这里再包一层业务超时，防止部分厂商 ROM 不按预期返回。
  static const _locationTimeout = Duration(seconds: 15);

  /// Android 系统反地理编码可能依赖网络或 GMS，真机网络异常时容易长时间挂起。
  static const _reverseGeocodeTimeout = Duration(seconds: 8);

  /// 允许测试或未来依赖注入时替换数据库服务；生产环境默认使用单例。
  final AddressDatabaseService? databaseService;

  AddressDatabaseService get _database =>
      databaseService ?? AddressDatabaseService.instance;

  /// 获取当前位置，转换为省市区详细地址，并写入地址表。
  Future<AddressRecord> captureAndSaveCurrentAddress() async {
    await _ensureLocationPermission();

    final position = await _withTimeout(
      Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          // 天气应用只需要城市/区县级定位，高精度能提高反地理编码的可用性。
          accuracy: LocationAccuracy.high,
          // 防止系统定位长时间无响应导致启动页一直等待。
          timeLimit: _locationTimeout,
        ),
      ),
      timeout: _locationTimeout,
      message: '定位超时，请确认 GPS、网络定位和定位权限是否正常。',
    );

    final placemark = await _reverseGeocode(position);
    final address = buildAddressRecord(position, placemark);
    return _database.upsertAddressByDistrict(address);
  }

  /// 检查系统定位服务和运行时权限。
  ///
  /// Android 6.0+ 需要运行时申请定位权限；如果用户永久拒绝，只能引导用户
  /// 到系统设置开启权限，因此这里抛出可读错误交给 UI 展示。
  Future<void> _ensureLocationPermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw const LocationAddressException('系统定位服务未开启，请先开启定位服务。');
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      throw const LocationAddressException('未获得定位权限，无法获取当前位置。');
    }

    if (permission == LocationPermission.deniedForever) {
      throw const LocationAddressException('定位权限已被永久拒绝，请在系统设置中手动开启。');
    }
  }

  /// 将经纬度反解析为地理地址。
  Future<Placemark> _reverseGeocode(Position position) async {
    // 指定中文结果，确保省、市、区和详细地址尽量返回中文行政区名称。
    await _withTimeout(
      setLocaleIdentifier('zh_CN'),
      timeout: const Duration(seconds: 3),
      message: '地址解析初始化超时，请稍后重试。',
    );

    final placemarks = await _withTimeout(
      placemarkFromCoordinates(position.latitude, position.longitude),
      timeout: _reverseGeocodeTimeout,
      message: '地址解析超时，请检查网络或稍后重试。',
    );

    if (placemarks.isEmpty) {
      throw const LocationAddressException('当前位置没有可用的地址解析结果。');
    }

    return placemarks.first;
  }

  /// 给平台 Future 增加统一超时，并把 TimeoutException 转成页面可读的业务错误。
  Future<T> _withTimeout<T>(
    Future<T> future, {
    required Duration timeout,
    required String message,
  }) async {
    try {
      return await future.timeout(timeout);
    } on TimeoutException {
      throw LocationAddressException(message);
    }
  }

  /// 把平台返回的 [Placemark] 映射成地址表记录。
  ///
  /// 不同 Android 设备和地理编码服务返回字段可能略有差异，所以这里做多级兜底。
  /// 真机上常见情况是 [subAdministrativeArea] 返回“市”，[locality] 返回“区/县”；
  /// 如果简单把 locality 当作市，会导致地址表里的市和区写反。
  ///
  /// 该方法保持公开，方便单元测试直接覆盖不同国家/地区返回字段的组合；
  /// 页面业务仍只需要调用 [captureAndSaveCurrentAddress]。
  AddressRecord buildAddressRecord(Position position, Placemark placemark) {
    final now = DateTime.now();
    final isChina = _isChinaPlacemark(placemark);
    final province = _firstNotEmpty([
      placemark.administrativeArea,
      placemark.subAdministrativeArea,
      placemark.locality,
      placemark.country,
    ]);
    final city = _selectCity(placemark, province, isChina: isChina);
    final district = _selectDistrict(
      placemark,
      city,
      province,
      isChina: isChina,
    );
    final detailAddress = _joinAddressParts([
      placemark.country,
      province,
      city,
      district,
      placemark.thoroughfare,
      placemark.subThoroughfare,
      placemark.street,
      placemark.name,
    ]);

    return AddressRecord(
      latitude: position.latitude,
      longitude: position.longitude,
      province: province,
      city: city,
      district: district,
      detailAddress: detailAddress,
      createdAt: now,
      updatedAt: now,
    );
  }

  /// 选择市级行政区。
  ///
  /// 国内优先识别“市/州/盟/地区”等中文行政后缀；海外地址通常没有这些后缀，
  /// 因此按 locality（城市）优先，再用 subAdministrativeArea 等字段兜底。
  String _selectCity(
    Placemark placemark,
    String province, {
    required bool isChina,
  }) {
    if (!isChina) {
      return _firstDifferentNotEmpty(
            [
              placemark.locality,
              placemark.subAdministrativeArea,
              placemark.subLocality,
              placemark.administrativeArea,
            ],
            [province],
          ) ??
          province;
    }

    final candidates = [
      placemark.subAdministrativeArea,
      placemark.locality,
      placemark.administrativeArea,
    ];
    return _firstMatching(candidates, _looksLikeCity) ??
        _firstDifferentNotEmpty(candidates, [province]) ??
        province;
  }

  /// 选择区县级行政区。
  ///
  /// [locality] 在部分国产 ROM 上会返回区县名，所以这里优先识别“区/县/旗”等
  /// 区县级后缀；海外地址则优先用 subLocality，不存在时退到县/郡、市或省。
  String _selectDistrict(
    Placemark placemark,
    String city,
    String province, {
    required bool isChina,
  }) {
    if (!isChina) {
      return _firstDifferentNotEmpty(
            [
              placemark.subLocality,
              placemark.subAdministrativeArea,
              placemark.locality,
              placemark.administrativeArea,
            ],
            [city, province],
          ) ??
          _firstNotEmpty([city, province]);
    }

    final candidates = [
      placemark.locality,
      placemark.subLocality,
      placemark.subAdministrativeArea,
    ];
    return _firstMatching(
          candidates,
          (value) =>
              value != city && value != province && _looksLikeDistrict(value),
        ) ??
        _firstDifferentNotEmpty(candidates, [city, province]) ??
        city;
  }

  String? _firstMatching(
    List<String?> values,
    bool Function(String value) test,
  ) {
    for (final value in values) {
      final normalizedValue = value?.trim();
      if (normalizedValue != null &&
          normalizedValue.isNotEmpty &&
          test(normalizedValue)) {
        return normalizedValue;
      }
    }
    return null;
  }

  String? _firstDifferentNotEmpty(
    List<String?> values,
    List<String> excludedValues,
  ) {
    final normalizedExcludedValues = excludedValues
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet();

    for (final value in values) {
      final normalizedValue = value?.trim();
      if (normalizedValue != null &&
          normalizedValue.isNotEmpty &&
          !normalizedExcludedValues.contains(normalizedValue)) {
        return normalizedValue;
      }
    }
    return null;
  }

  bool _isChinaPlacemark(Placemark placemark) {
    final countryCode = placemark.isoCountryCode?.trim().toUpperCase();
    final country = placemark.country?.trim().toLowerCase();
    return countryCode == 'CN' ||
        country == '中国' ||
        country == '中华人民共和国' ||
        country == 'china';
  }

  bool _looksLikeCity(String value) {
    return value.endsWith('市') ||
        value.endsWith('州') ||
        value.endsWith('盟') ||
        value.endsWith('地区');
  }

  bool _looksLikeDistrict(String value) {
    return value.endsWith('区') ||
        value.endsWith('县') ||
        value.endsWith('旗') ||
        value.endsWith('自治县') ||
        value.endsWith('林区') ||
        value.endsWith('特区');
  }

  /// 从候选字段中取第一个非空字符串，所有候选都为空时返回空字符串。
  String _firstNotEmpty(List<String?> values) {
    for (final value in values) {
      final normalizedValue = value?.trim();
      if (normalizedValue != null && normalizedValue.isNotEmpty) {
        return normalizedValue;
      }
    }
    return '';
  }

  /// 拼接详细地址，并去掉相邻重复片段。
  ///
  /// 例如部分服务会同时在 street/name 中返回同一条道路，去重后 UI 和数据库
  /// 中保存的地址更干净。
  String _joinAddressParts(List<String?> parts) {
    final uniqueParts = <String>[];
    for (final part in parts) {
      final normalizedPart = part?.trim();
      if (normalizedPart == null || normalizedPart.isEmpty) {
        continue;
      }
      if (uniqueParts.isNotEmpty && uniqueParts.last == normalizedPart) {
        continue;
      }
      uniqueParts.add(normalizedPart);
    }
    return uniqueParts.join('');
  }
}

/// 定位地址流程的业务异常。
///
/// 使用独立异常类型可以和系统异常区分开，UI 展示时优先显示 message。
class LocationAddressException implements Exception {
  const LocationAddressException(this.message);

  final String message;

  @override
  String toString() => message;
}
