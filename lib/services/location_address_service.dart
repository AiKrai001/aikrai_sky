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

  /// 允许测试或未来依赖注入时替换数据库服务；生产环境默认使用单例。
  final AddressDatabaseService? databaseService;

  AddressDatabaseService get _database =>
      databaseService ?? AddressDatabaseService.instance;

  /// 获取当前位置，转换为省市区详细地址，并写入地址表。
  Future<AddressRecord> captureAndSaveCurrentAddress() async {
    await _ensureLocationPermission();

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        // 天气应用只需要城市/区县级定位，高精度能提高反地理编码的可用性。
        accuracy: LocationAccuracy.high,
        // 防止系统定位长时间无响应导致启动页一直等待。
        timeLimit: Duration(seconds: 15),
      ),
    );

    final placemark = await _reverseGeocode(position);
    final address = _buildAddressRecord(position, placemark);
    return _database.insertAddress(address);
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
    await setLocaleIdentifier('zh_CN');

    final placemarks = await placemarkFromCoordinates(
      position.latitude,
      position.longitude,
    );

    if (placemarks.isEmpty) {
      throw const LocationAddressException('当前位置没有可用的地址解析结果。');
    }

    return placemarks.first;
  }

  /// 把平台返回的 Placemark 映射为项目地址表字段。
  ///
  /// 不同 Android 设备和地理编码服务返回字段可能略有差异，所以这里做多级兜底：
  /// 省优先取 [administrativeArea]，市优先取 [locality]，区优先取 [subLocality]。
  AddressRecord _buildAddressRecord(Position position, Placemark placemark) {
    final province = _firstNotEmpty([
      placemark.administrativeArea,
      placemark.locality,
    ]);
    final city = _firstNotEmpty([
      placemark.locality,
      placemark.subAdministrativeArea,
      placemark.administrativeArea,
    ]);
    final district = _firstNotEmpty([
      placemark.subLocality,
      placemark.subAdministrativeArea,
      placemark.locality,
    ]);
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
      createdAt: DateTime.now(),
    );
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
