import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:llm_project/services/background_service.dart';
import 'package:provider/provider.dart';
import 'core/module_interface.dart';
import 'modules/chat_module.dart';
import 'pages/main_menu_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 隐藏顶部系统状态栏，保留底部导航栏
  await SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.manual,
    overlays: [SystemUiOverlay.bottom],
  );

  // 设置系统栏透明，避免顶部出现黑条
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,

      // 根据你的背景颜色决定 light/dark
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarIconBrightness: Brightness.light,

      // Android 10+ 避免系统强行加半透明遮罩
      systemStatusBarContrastEnforced: false,
      systemNavigationBarContrastEnforced: false,
    ),
  );

  final moduleManager = ModuleManager();
  final chatModule = ChatModule();
  moduleManager.register(chatModule);
  moduleManager.initAll();

  // 确保预设背景存在
  BackgroundService.ensurePresetsExist();

  runApp(
    Provider<ChatModule>.value(
      value: chatModule,
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'llm_project',
      debugShowCheckedModeBanner: false,
      home: MainMenuPage(),
    );
  }
}