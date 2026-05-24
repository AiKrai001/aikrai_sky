# AiKraiSky

AiKraiSky 是一个基于 Flutter 的 Android 天气应用。应用会获取当前位置或手动添加的位置，调用腾讯位置服务完成地址解析，调用彩云天气综合接口获取天气数据，并将地址与天气原始响应保存到本地 SQLite，供首页和数据查看页复用。

## 功能概览

- 天气首页：当前天气、近 24 小时曲线、近 7 天天气、空气质量、生活指数。
- 多位置管理：首页可左右滑动切换位置；城市管理页支持添加、拖动排序、左滑删除。
- 定位刷新：仅在应用启动、下拉刷新、点击刷新时重新定位并更新天气；从后台回到前台不自动刷新。
- 数据落库：地址表按区去重更新；天气表按地址和日期保存，每天同一地址只保留最新原始响应。
- 数据查看：地址表和天气表支持分页查看、按日查询，天气原始响应可完整滚动查看。
- 打包配置：Android 安装名为 `AiKraiSky`，release 当前使用 debug 签名，构建前会自动生成 launcher icon。

## 技术栈

- Flutter SDK：使用项目匹配的 Flutter 版本
- Dart SDK：项目约束 `^3.11.5`
- Android Gradle Plugin：`8.11.1`
- Kotlin Android Plugin：`2.2.20`
- 本地数据库：`sqflite`
- 定位与地址：`geolocator`、`geocoding`、腾讯位置服务 WebService
- 网络请求：`http`

## 项目结构

```text
lib/
  main.dart                              # 应用入口
  models/
    address_record.dart                  # 地址表模型
    caiyun_weather_response.dart         # 彩云天气响应模型
    weather_display_data.dart            # 首页展示数据模型
    weather_record.dart                  # 天气表模型
  pages/
    weather_home_page.dart               # 天气首页
    location_management_page.dart        # 城市管理页
    add_location_page.dart               # 添加城市页
    address_records_page.dart            # 地址数据查看页
    weather_records_page.dart            # 天气数据查看页
  services/
    address_database_service.dart        # SQLite 表结构和读写逻辑
    caiyun_weather_service.dart          # 彩云天气接口调用和保存
    location_address_service.dart        # 定位、反地理编码、地址搜索
android/
  app/build.gradle.kts                   # Android 构建、签名、图标生成配置
  app/src/main/AndroidManifest.xml       # 应用名、权限、入口 Activity
test/
  location_address_service_test.dart
  weather_model_test.dart
  widget_test.dart
```

## 外部服务配置

运行和打包时需要传入两个 `dart-define`：

| 变量 | 用途 |
| --- | --- |
| `TENCENT_MAP_KEY` | 腾讯位置服务 Key，用于地点搜索、经纬度解析和地址候选 |
| `CAIYUN_TOKEN` | 彩云天气 Token，用于请求 v2.6 综合天气接口 |

示例：

```powershell
--dart-define=TENCENT_MAP_KEY=<your-tencent-map-key> `
--dart-define=CAIYUN_TOKEN=<your-caiyun-token>
```

不要把生产 Key 或 Token 写入 Git。当前代码会从 `String.fromEnvironment(...)` 读取这些值。

## 安装依赖

```powershell
cd <project-root>

flutter pub get
```

如果需要自定义 Pub Cache，可在系统环境变量中设置：

```powershell
PUB_CACHE=<your-pub-cache-path>
```

设置后重新打开终端再执行 `flutter pub get`。

## 运行调试

```powershell
cd <project-root>

flutter run `
  --dart-define=TENCENT_MAP_KEY=<your-tencent-map-key> `
  --dart-define=CAIYUN_TOKEN=<your-caiyun-token>
```

首次运行需要授予定位权限。应用启动时会定位并拉取天气；后续从后台切回前台不会自动重新定位。

## 打包 APK

当前 `release` 构建使用 debug 签名，适合内部测试安装：

[android/app/build.gradle.kts](android/app/build.gradle.kts)

```kotlin
signingConfig = signingConfigs.getByName("debug")
```

打包命令：

```powershell
cd <project-root>

flutter build apk --release `
  --dart-define=TENCENT_MAP_KEY=<your-tencent-map-key> `
  --dart-define=CAIYUN_TOKEN=<your-caiyun-token>
```

产物路径：

```text
build\app\outputs\flutter-apk\app-release.apk
```

## 指定 JDK

如果需要指定 JDK 21，推荐让 Flutter 使用固定 JDK：

```powershell
flutter config --jdk-dir "<your-jdk-21-path>"
```

也可以只对当前项目配置 `android/gradle.properties`：

```properties
org.gradle.java.home=<your-jdk-21-path>
```

使用 `/` 路径分隔符，避免 Windows 反斜杠转义问题。

## Launcher Icon

Android 安装后的应用名配置为 `AiKraiSky`：

[android/app/src/main/AndroidManifest.xml](android/app/src/main/AndroidManifest.xml)

图标由 Gradle 构建前任务自动生成，图片来源在：

[android/app/build.gradle.kts](android/app/build.gradle.kts)

具体图片地址由 `sourceIconUrl` 配置项控制。

构建时会生成以下资源：

```text
mipmap-mdpi/ic_launcher.png
mipmap-hdpi/ic_launcher.png
mipmap-xhdpi/ic_launcher.png
mipmap-xxhdpi/ic_launcher.png
mipmap-xxxhdpi/ic_launcher.png
```

如果图标链接不可访问，Gradle 会在生成图标阶段失败。更换图标时只需修改 `sourceIconUrl`。

## 本地数据说明

应用使用 SQLite 保存两类数据：

### 地址表 `address_records`

字段包括：

- 经纬度
- 省、市、区
- 详细地址
- 排序值
- 创建时间
- 更新时间

定位保存规则：按 `区` 区分位置；如果该区已存在，则更新该区的经纬度和地址信息；如果不存在，则新增地址。

### 天气表 `weather_data`

字段包括：

- 地址 ID
- 天气日期 `weather_date`
- 请求原始响应 JSON
- 创建时间
- 更新时间

保存规则：同一地址同一天只保留一条天气记录。重复请求会更新原始响应和更新时间。

## 测试与检查

```powershell
flutter test

flutter analyze
```

如果只想查看依赖是否有可升级版本：

```powershell
flutter pub outdated
```

## 常见问题

### 构建时卡在 `Running Gradle task 'assembleRelease'...`

先确认网络可以访问 launcher icon 的远程图片地址；如果图片下载失败，构建会在图标生成阶段报错。

也可以先确认 Flutter 工具链是否正常：

```powershell
flutter doctor -v
```

### Android 提示 Java 8 编译参数过时

类似下面的警告通常来自依赖或 Android 构建链，不影响 APK 生成：

```text
源值 8 已过时，将在未来发行版中删除
目标值 8 已过时，将在未来发行版中删除
```

### 真机没有定位结果

检查以下事项：

- Android 系统定位已开启。
- 应用已授予定位权限。
- `TENCENT_MAP_KEY` 已正确传入。
- 设备网络可以访问腾讯位置服务和彩云天气接口。
