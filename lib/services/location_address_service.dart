import 'dart:async';
import 'dart:convert';

import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import '../models/address_record.dart';
import 'address_database_service.dart';

/// 定位、反地理编码和地址落库的一站式服务。
///
/// 页面只调用 [captureAndSaveCurrentAddress]，不直接处理权限、经纬度、
/// 省市区拆分和 SQLite 写入，避免 UI 层变得臃肿。
class LocationAddressService {
  const LocationAddressService({this.databaseService, http.Client? httpClient})
    : _httpClient = httpClient;

  /// 定位插件已经传了 timeLimit，这里再包一层业务超时，防止部分厂商 ROM 不按预期返回。
  static const _locationTimeout = Duration(seconds: 15);

  /// Android 系统反地理编码可能依赖网络或 GMS，真机网络异常时容易长时间挂起。
  static const _reverseGeocodeTimeout = Duration(seconds: 8);

  /// 手动搜索位置时的地理编码超时时间。
  static const _addressSearchTimeout = Duration(seconds: 10);

  /// 腾讯位置服务 WebService Key。
  ///
  /// 运行或打包时通过：
  /// `--dart-define=TENCENT_MAP_KEY=你的Key`
  /// 传入，避免把 Key 写死到代码仓库里。
  static const _tencentMapKey = String.fromEnvironment('TENCENT_MAP_KEY');

  /// 腾讯关键词输入提示接口，适合“输入后展示多个可选择地址”的场景。
  static final _tencentSuggestionUri = Uri.https(
    'apis.map.qq.com',
    '/ws/place/v1/suggestion',
  );

  /// 腾讯地址解析接口，用于 suggestion 没有返回候选时做单点兜底。
  static final _tencentGeocoderUri = Uri.https(
    'apis.map.qq.com',
    '/ws/geocoder/v1/',
  );

  /// 腾讯接口请求超时时间，避免搜索框一直转圈。
  static const _tencentSearchTimeout = Duration(seconds: 10);

  /// 允许测试或未来依赖注入时替换数据库服务；生产环境默认使用单例。
  final AddressDatabaseService? databaseService;

  /// 允许测试注入 HTTP Client；生产环境为空时临时创建并自动关闭。
  final http.Client? _httpClient;

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

  /// 根据用户输入的位置名称搜索候选位置。
  ///
  /// 这里只返回可选项，不直接写入数据库；用户点击某个候选项后再调用
  /// [saveAddress] 保存，避免输入后看不到可选择地区。
  Future<List<AddressRecord>> searchAddressOptions(String query) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) {
      throw const LocationAddressException('请输入需要添加的位置名称。');
    }

    LocationAddressException? tencentError;
    final tencentKey = _tencentMapKey.trim();
    if (tencentKey.isNotEmpty) {
      try {
        final tencentOptions = await _searchTencentAddressOptions(
          query: normalizedQuery,
          key: tencentKey,
        );
        if (tencentOptions.isNotEmpty) {
          return tencentOptions;
        }
      } on LocationAddressException catch (error) {
        tencentError = error;
      }
    } else {
      tencentError = const LocationAddressException(
        '腾讯位置服务 Key 未配置，请使用 --dart-define=TENCENT_MAP_KEY=你的Key 运行。',
      );
    }

    try {
      final platformOptions = await _searchPlatformAddressOptions(
        normalizedQuery,
      );
      if (platformOptions.isNotEmpty) {
        return platformOptions;
      }
    } catch (_) {
      if (tencentError == null) {
        rethrow;
      }
    }

    if (tencentError != null) {
      throw tencentError;
    }
    throw const LocationAddressException('没有搜索到匹配的位置。');
  }

  /// 保存用户从搜索结果中选择的位置。
  Future<AddressRecord> saveAddress(AddressRecord address) {
    return _database.upsertAddressByDistrict(address);
  }

  /// 使用腾讯位置服务搜索地址候选。
  ///
  /// suggestion 接口会返回多条 POI/行政区候选，刚好对应“输入后让用户选择”
  /// 的交互；如果 suggestion 没有结果，再用 geocoder 做一次单点兜底。
  Future<List<AddressRecord>> _searchTencentAddressOptions({
    required String query,
    required String key,
  }) async {
    final suggestionUri = _tencentSuggestionUri.replace(
      queryParameters: {
        'key': key,
        'keyword': query,
        'page_size': '20',
        'page_index': '1',
        'get_subpois': '1',
        'get_ad': '1',
        'output': 'json',
      },
    );
    final suggestionJson = await _getTencentJson(suggestionUri);
    final suggestionOptions = _parseTencentSuggestionOptions(suggestionJson);
    if (suggestionOptions.isNotEmpty) {
      return suggestionOptions;
    }

    final geocoderUri = _tencentGeocoderUri.replace(
      queryParameters: {
        'key': key,
        'address': query,
        'policy': '1',
        'output': 'json',
      },
    );
    final geocoderJson = await _getTencentJson(geocoderUri);
    final geocoderOption = buildTencentGeocoderAddressRecord(geocoderJson);
    return geocoderOption == null ? const [] : [geocoderOption];
  }

  Future<List<AddressRecord>> _searchPlatformAddressOptions(
    String query,
  ) async {
    await _withTimeout(
      setLocaleIdentifier('zh_CN'),
      timeout: const Duration(seconds: 3),
      message: '地址搜索初始化超时，请稍后重试。',
    );

    final locations = await _withTimeout(
      locationFromAddress(query),
      timeout: _addressSearchTimeout,
      message: '地址搜索超时，请检查网络或稍后重试。',
    );
    if (locations.isEmpty) {
      throw const LocationAddressException('没有搜索到匹配的位置。');
    }

    final options = <AddressRecord>[];
    final seenKeys = <String>{};
    for (final location in locations.take(10)) {
      final placemark = await _reverseGeocodeCoordinates(
        latitude: location.latitude,
        longitude: location.longitude,
      );
      final position = Position(
        latitude: location.latitude,
        longitude: location.longitude,
        timestamp: location.timestamp,
        accuracy: 0,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      );
      final address = _fillSearchFallback(
        buildAddressRecord(position, placemark),
        query,
      );
      final optionKey =
          '${address.district}|${address.detailAddress}|'
          '${address.latitude.toStringAsFixed(5)},'
          '${address.longitude.toStringAsFixed(5)}';
      if (seenKeys.add(optionKey)) {
        options.add(address);
      }
    }

    if (options.isEmpty) {
      return const [];
    }
    return options;
  }

  Future<Map<String, Object?>> _getTencentJson(Uri uri) async {
    final client = _httpClient ?? http.Client();
    final shouldCloseClient = _httpClient == null;
    try {
      final response = await client.get(uri).timeout(_tencentSearchTimeout);
      if (response.statusCode != 200) {
        throw LocationAddressException(
          '腾讯位置服务请求失败：HTTP ${response.statusCode}',
        );
      }

      final decodedJson = jsonDecode(response.body);
      if (decodedJson is! Map) {
        throw const LocationAddressException('腾讯位置服务返回数据不是 JSON 对象。');
      }
      final json = Map<String, Object?>.from(decodedJson);

      final status = json['status'];
      if (status != 0) {
        final message = _readString(json, 'message');
        throw LocationAddressException(
          message.isEmpty ? '腾讯位置服务返回状态异常：$status' : message,
        );
      }
      return json;
    } on TimeoutException {
      throw const LocationAddressException('腾讯位置服务搜索超时，请检查网络或稍后重试。');
    } on FormatException {
      throw const LocationAddressException('腾讯位置服务返回数据不是合法 JSON。');
    } finally {
      if (shouldCloseClient) {
        client.close();
      }
    }
  }

  List<AddressRecord> _parseTencentSuggestionOptions(
    Map<String, Object?> json,
  ) {
    final rawItems = json['data'];
    if (rawItems is! List) {
      return const [];
    }

    final options = <AddressRecord>[];
    final seenKeys = <String>{};
    for (final rawItem in rawItems) {
      if (rawItem is! Map) {
        continue;
      }

      final option = buildTencentSuggestionAddressRecord(
        Map<String, Object?>.from(rawItem),
      );
      if (option == null) {
        continue;
      }

      final optionKey =
          '${option.district}|${option.detailAddress}|'
          '${option.latitude.toStringAsFixed(5)},'
          '${option.longitude.toStringAsFixed(5)}';
      if (seenKeys.add(optionKey)) {
        options.add(option);
      }
    }

    return options;
  }

  /// 把腾讯 suggestion 的单条候选映射为地址表模型。
  ///
  /// 该方法保持公开，方便单元测试覆盖不同接口返回形态；页面仍只调用
  /// [searchAddressOptions] 获取候选。
  AddressRecord? buildTencentSuggestionAddressRecord(
    Map<String, Object?> item,
  ) {
    final latitude = _readTencentLatitude(item);
    final longitude = _readTencentLongitude(item);
    if (latitude == null || longitude == null) {
      return null;
    }

    final now = DateTime.now();
    final title = _readString(item, 'title');
    final address = _readString(item, 'address');
    final street = _readString(item, 'street');
    final province = _readString(item, 'province');
    final city = _readString(item, 'city');
    final rawDistrict = _readString(item, 'district');
    final district = _selectTencentDistrict(
      title: title,
      city: city,
      province: province,
      rawDistrict: rawDistrict,
    );
    final shortAddress = _stripLeadingAddressParts(address, [
      province,
      city,
      district,
    ]);
    final detailAddress = _joinAddressParts([
      province,
      city,
      district,
      if (!shortAddress.startsWith(street)) street,
      shortAddress,
      if (!shortAddress.contains(title) &&
          title != district &&
          title != city &&
          title != province)
        title,
    ]);

    return AddressRecord(
      latitude: latitude,
      longitude: longitude,
      province: _firstNotEmpty([province, city, district, title]),
      city: _firstNotEmpty([city, district, province, title]),
      district: _firstNotEmpty([district, city, province, title]),
      detailAddress: detailAddress.isEmpty ? title : detailAddress,
      sortOrder: -1,
      createdAt: now,
      updatedAt: now,
    );
  }

  /// 把腾讯 geocoder 的单条解析结果映射为地址表模型。
  AddressRecord? buildTencentGeocoderAddressRecord(Map<String, Object?> json) {
    final result = json['result'];
    if (result is! Map) {
      return null;
    }
    final resultMap = Map<String, Object?>.from(result);

    final location = resultMap['location'];
    if (location is! Map) {
      return null;
    }

    final locationMap = Map<String, Object?>.from(location);
    final latitude = _readDouble(locationMap, 'lat');
    final longitude = _readDouble(locationMap, 'lng');
    if (latitude == null || longitude == null) {
      return null;
    }

    final components = resultMap['address_components'];
    final addressComponents = components is Map
        ? Map<String, Object?>.from(components)
        : const <String, Object?>{};
    final province = _readString(addressComponents, 'province');
    final city = _readString(addressComponents, 'city');
    final district = _readString(addressComponents, 'district');
    final street = _readString(addressComponents, 'street');
    final streetNumber = _readString(addressComponents, 'street_number');
    final address = _readString(resultMap, 'address');
    final shortAddress = _stripLeadingAddressParts(address, [
      province,
      city,
      district,
      street,
    ]);
    final detailAddress = _joinAddressParts([
      province,
      city,
      district,
      street,
      if (!shortAddress.startsWith(streetNumber)) streetNumber,
      shortAddress,
    ]);
    final now = DateTime.now();

    return AddressRecord(
      latitude: latitude,
      longitude: longitude,
      province: _firstNotEmpty([province, city, district, address]),
      city: _firstNotEmpty([city, district, province, address]),
      district: _firstNotEmpty([district, city, province, address]),
      detailAddress: detailAddress.isEmpty ? address : detailAddress,
      sortOrder: -1,
      createdAt: now,
      updatedAt: now,
    );
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

    return _reverseGeocodeCoordinates(
      latitude: position.latitude,
      longitude: position.longitude,
    );
  }

  Future<Placemark> _reverseGeocodeCoordinates({
    required double latitude,
    required double longitude,
  }) async {
    final placemarks = await _withTimeout(
      placemarkFromCoordinates(latitude, longitude),
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
      sortOrder: -1,
      createdAt: now,
      updatedAt: now,
    );
  }

  AddressRecord _fillSearchFallback(AddressRecord address, String query) {
    final title = _firstNotEmpty([
      address.district,
      address.city,
      address.province,
      query,
    ]);
    return address.copyWith(
      province: address.province.isEmpty ? title : address.province,
      city: address.city.isEmpty ? title : address.city,
      district: address.district.isEmpty ? title : address.district,
      detailAddress: address.detailAddress.isEmpty
          ? query
          : address.detailAddress,
    );
  }

  String _selectTencentDistrict({
    required String title,
    required String city,
    required String province,
    required String rawDistrict,
  }) {
    if (rawDistrict.isNotEmpty) {
      return rawDistrict;
    }
    if (_looksLikeDistrict(title) || _looksLikeCity(title)) {
      return title;
    }
    return _firstNotEmpty([city, province, title]);
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

  /// 腾讯接口的 address 字段经常已经包含“省市区”，这里先剥掉前缀，
  /// 避免候选列表出现“省市区省市区重复...”。
  String _stripLeadingAddressParts(String address, List<String> prefixes) {
    var result = address.trim();
    for (final prefix in prefixes) {
      final normalizedPrefix = prefix.trim();
      if (normalizedPrefix.isEmpty) {
        continue;
      }
      while (result.startsWith(normalizedPrefix)) {
        result = result.substring(normalizedPrefix.length).trim();
      }
    }
    return result;
  }

  double? _readTencentLatitude(Map<String, Object?> item) {
    final location = item['location'];
    if (location is Map) {
      final latitude = _readDouble(Map<String, Object?>.from(location), 'lat');
      if (latitude != null) {
        return latitude;
      }
    }
    return _readDouble(item, 'lat');
  }

  double? _readTencentLongitude(Map<String, Object?> item) {
    final location = item['location'];
    if (location is Map) {
      final longitude = _readDouble(Map<String, Object?>.from(location), 'lng');
      if (longitude != null) {
        return longitude;
      }
    }
    return _readDouble(item, 'lng');
  }

  double? _readDouble(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value.trim());
    }
    return null;
  }

  String _readString(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value == null) {
      return '';
    }
    return value.toString().trim();
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
