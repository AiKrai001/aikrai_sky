/// 本地地址表的一条记录。
///
/// 这个模型只承载“定位结果落库”这一步需要的字段：
/// 经纬度、省、市、区、详细地址、排序、创建时间和更新时间。后续天气接口需要查询当前位置时，
/// 可以直接读取最新一条地址记录，避免重复定义地址数据结构。
class AddressRecord {
  const AddressRecord({
    this.id,
    required this.latitude,
    required this.longitude,
    required this.province,
    required this.city,
    required this.district,
    required this.detailAddress,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
  });

  /// SQLite 自增主键；新记录入库前为空，入库后由数据库生成。
  final int? id;

  /// 纬度，范围通常为 -90 到 90。
  final double latitude;

  /// 经度，范围通常为 -180 到 180。
  final double longitude;

  /// 省级行政区，例如“广东省”“北京市”。
  final String province;

  /// 市级行政区，例如“深圳市”；直辖市场景下可能与 province 相同。
  final String city;

  /// 区/县级行政区，例如“南山区”。
  final String district;

  /// 平台反地理编码返回的可读地址，尽量拼接到街道/门牌级别。
  final String detailAddress;

  /// 位置管理页中的排序值，数值越小越靠前。
  final int sortOrder;

  /// 记录创建时间，使用本机当前时间。
  final DateTime createdAt;

  /// 记录更新时间；同一区再次定位时会刷新该字段。
  final DateTime updatedAt;

  /// 数据库表名集中放在模型中，避免服务层和查询层硬编码多份字符串。
  static const tableName = 'addresses';

  /// 数据库列名使用 snake_case，便于和 SQLite 习惯保持一致。
  static const columnId = 'id';
  static const columnLatitude = 'latitude';
  static const columnLongitude = 'longitude';
  static const columnProvince = 'province';
  static const columnCity = 'city';
  static const columnDistrict = 'district';
  static const columnDetailAddress = 'detail_address';
  static const columnSortOrder = 'sort_order';
  static const columnCreatedAt = 'created_at';
  static const columnUpdatedAt = 'updated_at';

  /// 将 Dart 对象转换为 SQLite 可写入的 Map。
  ///
  /// [id] 为空时不写入主键，让 SQLite 自动生成；时间字段使用 ISO8601
  /// 字符串保存，便于排序、调试以及未来跨端同步。
  Map<String, Object?> toMap() {
    return {
      if (id != null) columnId: id,
      columnLatitude: latitude,
      columnLongitude: longitude,
      columnProvince: province,
      columnCity: city,
      columnDistrict: district,
      columnDetailAddress: detailAddress,
      columnSortOrder: sortOrder,
      columnCreatedAt: createdAt.toIso8601String(),
      columnUpdatedAt: updatedAt.toIso8601String(),
    };
  }

  /// 从 SQLite 查询结果恢复为 Dart 对象。
  factory AddressRecord.fromMap(Map<String, Object?> map) {
    return AddressRecord(
      id: map[columnId] as int?,
      latitude: (map[columnLatitude] as num).toDouble(),
      longitude: (map[columnLongitude] as num).toDouble(),
      province: map[columnProvince] as String,
      city: map[columnCity] as String,
      district: map[columnDistrict] as String,
      detailAddress: map[columnDetailAddress] as String,
      sortOrder: (map[columnSortOrder] as num?)?.toInt() ?? 0,
      createdAt: DateTime.parse(map[columnCreatedAt] as String),
      updatedAt: DateTime.parse(
        (map[columnUpdatedAt] ?? map[columnCreatedAt]) as String,
      ),
    );
  }

  /// 生成字段可替换的副本。
  ///
  /// 插入数据库后可用它回填自增 id；同一区再次定位时也可保留原 id，
  /// 同时更新经纬度、省市区和详细地址。
  AddressRecord copyWith({
    int? id,
    double? latitude,
    double? longitude,
    String? province,
    String? city,
    String? district,
    String? detailAddress,
    int? sortOrder,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return AddressRecord(
      id: id ?? this.id,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      province: province ?? this.province,
      city: city ?? this.city,
      district: district ?? this.district,
      detailAddress: detailAddress ?? this.detailAddress,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
