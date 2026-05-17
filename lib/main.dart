import 'package:flutter/material.dart';

import 'pages/weather_home_page.dart';

void main() {
  runApp(const AikraiSkyApp());
}

/// 天气 App 根组件。
///
/// 默认进入天气首页；测试时可以注入轻量页面，避免触发真实定位和网络请求。
class AikraiSkyApp extends StatelessWidget {
  const AikraiSkyApp({super.key, this.home});

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
      home: home ?? const WeatherHomePage(),
    );
  }
}
