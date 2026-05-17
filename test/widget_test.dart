import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aikrai_sky/main.dart';

void main() {
  testWidgets('Aikrai Sky app shell renders injected home', (
    WidgetTester tester,
  ) async {
    // 使用注入的轻量首页验证 App 壳，避免单元测试环境触发真实定位权限弹窗。
    await tester.pumpWidget(
      const AikraiSkyApp(
        home: Scaffold(body: Center(child: Text('测试首页'))),
      ),
    );

    expect(find.text('测试首页'), findsOneWidget);

    final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(materialApp.title, 'Aikrai Sky');
  });
}
