import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_project/pages/home_experience_page.dart';
import 'package:llm_project/shared/theme/app_theme.dart';
import 'package:llm_project/shared/theme/app_theme_manager.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeAccessibilityFeatures implements AccessibilityFeatures {
  bool _disableAnimations = false;

  set disableAnimations(bool value) => _disableAnimations = value;

  @override
  bool get disableAnimations => _disableAnimations;

  @override
  dynamic noSuchMethod(Invocation invocation) => false;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget buildHome() {
    return ChangeNotifierProvider<AppThemeManager>(
      create: (_) => AppThemeManager(),
      child: MaterialApp(
        theme: AppTheme.day,
        home: const Scaffold(body: HomeExperiencePage()),
      ),
    );
  }

  testWidgets('home page mounts without MediaQuery-in-initState crash',
      (tester) async {
    await tester.pumpWidget(buildHome());
    // 页面有循环动画（品牌灯、Avatar 舞台），不能 pumpAndSettle，固定泵几次。
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(HomeExperiencePage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home page respects reduced motion at mount', (tester) async {
    final features = _FakeAccessibilityFeatures()..disableAnimations = true;
    tester.platformDispatcher.accessibilityFeaturesTestValue = features;
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpWidget(buildHome());
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
  });
}
