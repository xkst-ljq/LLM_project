import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:llm_project/services/background_service.dart';
import 'package:llm_project/services/character_draft_service.dart';
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

  // 预热背景缓存。
  //
  // 必须 await：这一步会顺带完成 openDatabase(建表/migration) 和
  // SharedPreferences.getInstance() 两件冷启动大头。做完之后聊天页
  // 首帧就能同步拿到背景，不会先空一拍再补上。
  // ensurePresetsExist 已包含在 warmUp 内部，不需要再单独调。
  await BackgroundService.warmUp();

  // 回收过期的编辑草稿（24h）。
  //
  // 不 await：它只是清理垃圾，没人等它的结果，
  // 让启动画面为此多停一会儿不值得。
  // 已删除的角色卡、再没打开过的卡，其草稿只能靠这里回收——
  // CharacterDraftService.load 只清理「正在打开的那一张」。
  unawaited(CharacterDraftService.purgeExpired());

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