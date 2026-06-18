import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'ui/app_title_bar.dart';
import 'ui/home_page.dart';

/// LLM Project 角色卡转换工具（PC 端）入口。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 桌面端：隐藏系统标题栏，改用应用内自绘标题栏。
  if (!Platform.isAndroid && !Platform.isIOS) {
    await windowManager.ensureInitialized();
    const opts = WindowOptions(
      size: Size(980, 640),
      minimumSize: Size(800, 520),
      center: true,
      titleBarStyle: TitleBarStyle.hidden, // 去掉系统标题栏
    );
    windowManager.waitUntilReadyToShow(opts, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  runApp(const ConverterApp());
}

class ConverterApp extends StatelessWidget {
  const ConverterApp({super.key});

  @override
  Widget build(BuildContext context) {
    final isDesktop = !Platform.isAndroid && !Platform.isIOS;
    return MaterialApp(
      title: 'LLM 角色卡转换工具',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.deepPurple),
      // 桌面端：标题栏浮在最上层（含弹窗遮罩之上），始终可见。
      builder: isDesktop
          ? (context, child) => Stack(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 40),
            child: child ?? const SizedBox(),
          ),
          const Align(
            alignment: Alignment.topCenter,
            child: AppTitleBar(),
          ),
        ],
      )
          : null,
      home: const HomePage(),
    );
  }
}
