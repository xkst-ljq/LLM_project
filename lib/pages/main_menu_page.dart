import 'package:flutter/material.dart';

import '../services/background_service.dart';
import '../widgets/page_guide_overlay.dart';
import 'api_config_page.dart';
import 'background_library_page.dart';
import 'character_library_page.dart';
import 'chat_page.dart';
import 'settings_menu_page.dart';
import 'tutorial_home_page.dart';
import 'world_book_library_page.dart';
import 'backup_restore_page.dart';
import 'prompt_settings_page.dart';
import 'user_settings_page.dart';

enum _MainGuidePhase { none, home, settings }

class MainMenuPage extends StatefulWidget {
  const MainMenuPage({super.key});

  @override
  State<MainMenuPage> createState() => _MainMenuPageState();
}

class _MainMenuPageState extends State<MainMenuPage>
    with SingleTickerProviderStateMixin {
  static const double _panelWidthFraction = 0.5;

  late AnimationController _animationController;
  double _dragStartOffset = 0.0;
  double _panelStartValue = 0.0;
  bool _hasAskedGuideThisSession = false;
  _MainGuidePhase _guidePhase = _MainGuidePhase.none;

  final _homeListKey = GlobalKey();
  final _chatTileKey = GlobalKey();
  final _characterTileKey = GlobalKey();
  final _worldBookTileKey = GlobalKey();
  final _backgroundTileKey = GlobalKey();

  final _settingsPanelKey = GlobalKey();
  final _apiConfigTileKey = GlobalKey();
  final _userSettingsTileKey = GlobalKey();
  final _promptSettingsTileKey = GlobalKey();
  final _backupTileKey = GlobalKey();
  final _tutorialTileKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    BackgroundService.ensurePresetsExist();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _animationController.addListener(() {
      if (mounted) setState(() {});
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showNewUserGuideDialogForTesting();
    });
  }

  Future<void> _showNewUserGuideDialogForTesting() async {
    if (!mounted || _hasAskedGuideThisSession) return;
    _hasAskedGuideThisSession = true;

    final startGuide = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('欢迎使用 LLM Project'),
          content: const Text(
            '是否开启新用户快速导览？\n\n'
            '导览会在页面上标出可交互区域。你可以点击高亮区域查看说明，也可以进入对应页面继续了解。\n\n'
            '当前测试阶段：每次启动都会显示这个弹窗，方便反复调试。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('跳过'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('开始导览'),
            ),
          ],
        );
      },
    );

    if (!mounted) return;
    if (startGuide == true) {
      _startNewUserGuide();
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  double get panelWidth =>
      MediaQuery.of(context).size.width * _panelWidthFraction;

  void _openPanel() =>
      _animationController.animateTo(1.0, curve: Curves.easeOut);
  void _closePanel() =>
      _animationController.animateTo(0.0, curve: Curves.easeOut);

  void _startNewUserGuide() {
    _closePanel();
    setState(() {
      _guidePhase = _MainGuidePhase.home;
    });
  }

  void _startSettingsGuide() {
    _openPanel();
    Future.delayed(const Duration(milliseconds: 320), () {
      if (!mounted) return;
      setState(() {
        _guidePhase = _MainGuidePhase.settings;
      });
    });
  }

  void _finishGuide() {
    setState(() {
      _guidePhase = _MainGuidePhase.none;
    });
  }

  Rect? _rectForKey(GlobalKey key) {
    final context = key.currentContext;
    if (context == null) return null;

    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return null;

    final offset = renderObject.localToGlobal(Offset.zero);
    return offset & renderObject.size;
  }

  Rect? _touchRectForKey(GlobalKey key) {
    final rect = _rectForKey(key);
    if (rect == null) return null;

    final touchSize = rect.height.clamp(48.0, 64.0).toDouble();
    final top = rect.top + (rect.height - touchSize) / 2;
    return Rect.fromLTWH(rect.left + 12, top, touchSize, touchSize);
  }

  Rect _settingsSwipeRect(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Rect.fromLTWH(size.width - 64, size.height * 0.36, 56, 112);
  }

  List<PageGuideTarget> _homeGuideTargets(BuildContext context) {
    final targets = <PageGuideTarget>[];

    void addTarget({
      required GlobalKey key,
      required int order,
      required String id,
      required String title,
      required String description,
      String? actionLabel,
      VoidCallback? onAction,
    }) {
      final rect = _touchRectForKey(key);
      if (rect == null) return;
      targets.add(
        PageGuideTarget(
          id: id,
          order: order,
          rect: rect,
          title: title,
          description: description,
          actionLabel: actionLabel,
          onAction: onAction,
        ),
      );
    }

    addTarget(
      key: _chatTileKey,
      order: 1,
      id: 'home_chat',
      title: '聊天',
      description: '这里可以进入聊天页。配置好 API 并选择角色后，就可以从这里开始对话。',
      actionLabel: '进入聊天页',
      onAction: () {
        _finishGuide();
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ChatPage()),
        );
      },
    );
    addTarget(
      key: _characterTileKey,
      order: 2,
      id: 'home_character_library',
      title: '角色库',
      description: '这里用于创建、编辑、导入和管理角色。如果想和自定义角色聊天，可以先从这里新建角色。',
      actionLabel: '进入角色库',
      onAction: () {
        _finishGuide();
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CharacterLibraryPage()),
        );
      },
    );
    addTarget(
      key: _worldBookTileKey,
      order: 3,
      id: 'home_world_book',
      title: '世界书库',
      description: '世界书用于保存背景设定、地点、组织、术语等资料。刚开始使用时可以先不用管，熟悉聊天后再学习。',
    );
    addTarget(
      key: _backgroundTileKey,
      order: 4,
      id: 'home_background',
      title: '背景图库',
      description: '背景图库用于管理聊天背景和页面背景。它属于外观相关功能，不影响基础聊天流程。',
    );

    targets.add(
      PageGuideTarget(
        id: 'home_settings_swipe',
        order: 5,
        rect: _settingsSwipeRect(context),
        title: '侧滑打开设置页',
        description: '在主页向左滑动，可以打开右侧设置页。API 配置、用户设定、Prompt 策略、备份和教程入口都在设置页中。',
        actionLabel: '演示打开设置页',
        onAction: _startSettingsGuide,
      ),
    );

    return targets;
  }

  List<PageGuideTarget> _settingsGuideTargets(BuildContext context) {
    final targets = <PageGuideTarget>[];

    void addTarget({
      required GlobalKey key,
      required int order,
      required String id,
      required String title,
      required String description,
      String? actionLabel,
      VoidCallback? onAction,
    }) {
      final rect = _touchRectForKey(key);
      if (rect == null) return;
      targets.add(
        PageGuideTarget(
          id: id,
          order: order,
          rect: rect,
          title: title,
          description: description,
          actionLabel: actionLabel,
          onAction: onAction,
        ),
      );
    }

    addTarget(
      key: _apiConfigTileKey,
      order: 1,
      id: 'settings_api_config',
      title: 'API 配置',
      description: '这里用于填写 API Key、服务地址和模型。没有 API 配置时，聊天通常无法正常回复。',
      actionLabel: '进入 API 配置',
      onAction: () {
        _finishGuide();
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ApiConfigPage()),
        );
      },
    );
    addTarget(
      key: _userSettingsTileKey,
      order: 2,
      id: 'settings_user',
      title: '用户设定',
      description: '这里用于设置“你是谁”。角色会参考这些信息与你互动。新手可以先跳过，等开始聊天后再完善。',
      actionLabel: '进入用户设定',
      onAction: () {
        _finishGuide();
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const UserSettingsPage()),
        );
      },
    );
    addTarget(
      key: _promptSettingsTileKey,
      order: 3,
      id: 'settings_prompt',
      title: 'Prompt 策略',
      description: '这里是全局默认 Prompt 策略。它属于进阶功能，熟悉基础聊天后再调整会更稳。',
      actionLabel: '进入 Prompt 策略',
      onAction: () {
        _finishGuide();
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PromptSettingsPage()),
        );
      },
    );
    addTarget(
      key: _backupTileKey,
      order: 4,
      id: 'settings_backup',
      title: '备份与恢复',
      description: '这里用于备份和恢复应用数据。大量编辑角色或升级应用前，建议先备份。',
      actionLabel: '进入备份与恢复',
      onAction: () {
        _finishGuide();
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const BackupRestorePage()),
        );
      },
    );
    addTarget(
      key: _tutorialTileKey,
      order: 5,
      id: 'settings_tutorial',
      title: '教程与导览',
      description: '以后如果忘记某个操作，可以从这里重新打开页面导览和推荐路线。',
      actionLabel: '进入教程中心',
      onAction: () {
        _finishGuide();
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => TutorialHomePage(
              onStartNewUserGuide: _startNewUserGuide,
              onStartSettingsGuide: _startSettingsGuide,
            ),
          ),
        );
      },
    );

    return targets;
  }

  void _onHorizontalDragStart(DragStartDetails details) {
    _dragStartOffset = details.globalPosition.dx;
    _panelStartValue = _animationController.value;
    _animationController.stop();
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    final dx = details.globalPosition.dx - _dragStartOffset;
    final totalMove = panelWidth;
    final newValue = (_panelStartValue - dx / totalMove)
        .clamp(0.0, 1.0)
        .toDouble();
    _animationController.value = newValue;
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    if (details.primaryVelocity != null && details.primaryVelocity! < -300) {
      _openPanel();
    } else if (details.primaryVelocity != null &&
        details.primaryVelocity! > 300) {
      _closePanel();
    } else if (_animationController.value > 0.3) {
      _openPanel();
    } else {
      _closePanel();
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final panelW = panelWidth;
    final leftOffset = -panelW * _animationController.value;

    return Scaffold(
      body: GestureDetector(
        onHorizontalDragStart: _guidePhase == _MainGuidePhase.none
            ? _onHorizontalDragStart
            : null,
        onHorizontalDragUpdate: _guidePhase == _MainGuidePhase.none
            ? _onHorizontalDragUpdate
            : null,
        onHorizontalDragEnd: _guidePhase == _MainGuidePhase.none
            ? _onHorizontalDragEnd
            : null,
        child: Stack(
          children: [
            Positioned(
              left: leftOffset,
              top: 0,
              bottom: 0,
              width: screenWidth + panelW,
              child: Row(
                children: [
                  SizedBox(
                    width: screenWidth,
                    child: Column(
                      children: [
                        AppBar(
                          title: const Text('主页'),
                          automaticallyImplyLeading: false,
                        ),
                        Expanded(
                          child: ListView(
                            key: _homeListKey,
                            children: [
                              Container(
                                key: _chatTileKey,
                                child: ListTile(
                                  leading: const Icon(Icons.chat),
                                  title: const Text('聊天'),
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => const ChatPage(),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              Container(
                                key: _characterTileKey,
                                child: ListTile(
                                  leading: const Icon(Icons.people),
                                  title: const Text('角色库'),
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const CharacterLibraryPage(),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              Container(
                                key: _worldBookTileKey,
                                child: ListTile(
                                  leading: const Icon(Icons.book),
                                  title: const Text('世界书库'),
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const WorldBookLibraryPage(),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              Container(
                                key: _backgroundTileKey,
                                child: ListTile(
                                  leading: const Icon(Icons.image),
                                  title: const Text('背景图库'),
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const BackgroundLibraryPage(),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    key: _settingsPanelKey,
                    width: panelW,
                    child: Container(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      child: SettingsMenuPage(
                        onStartNewUserGuide: _startNewUserGuide,
                        onStartSettingsGuide: _startSettingsGuide,
                        apiConfigTileKey: _apiConfigTileKey,
                        userSettingsTileKey: _userSettingsTileKey,
                        promptSettingsTileKey: _promptSettingsTileKey,
                        backupTileKey: _backupTileKey,
                        tutorialTileKey: _tutorialTileKey,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_guidePhase == _MainGuidePhase.home)
              PageGuideOverlay(
                title: '主页导览',
                hint: '点击高亮区域查看说明。推荐先了解“聊天”“角色库”，再通过右侧边缘的侧滑导览打开设置页。',
                targets: _homeGuideTargets(context),
                onExit: _finishGuide,
              ),
            if (_guidePhase == _MainGuidePhase.settings)
              PageGuideOverlay(
                title: '设置页导览',
                hint: '点击高亮区域查看说明。第一次使用时，建议先了解 API 配置和教程与导览入口。',
                targets: _settingsGuideTargets(context),
                onExit: _finishGuide,
              ),
          ],
        ),
      ),
    );
  }
}
