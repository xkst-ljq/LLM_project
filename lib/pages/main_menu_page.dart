import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:flutter/rendering.dart';
import '../services/background_service.dart';
import '../widgets/page_guide_overlay.dart';
import '../widgets/simple_page_guide_scope.dart';
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
  final _chatTextKey = GlobalKey();
  final _characterTextKey = GlobalKey();
  final _worldBookTextKey = GlobalKey();
  final _backgroundTextKey = GlobalKey();

  final _settingsPanelKey = GlobalKey();
  final _apiConfigTileKey = GlobalKey();
  final _userSettingsTileKey = GlobalKey();
  final _promptSettingsTileKey = GlobalKey();
  final _backupTileKey = GlobalKey();
  final _tutorialTileKey = GlobalKey();
  final _apiConfigTextKey = GlobalKey();
  final _userSettingsTextKey = GlobalKey();
  final _promptSettingsTextKey = GlobalKey();
  final _backupTextKey = GlobalKey();
  final _tutorialTextKey = GlobalKey();

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

  void _returnToHomeGuide() {
    _closePanel();
    Future.delayed(const Duration(milliseconds: 320), () {
      if (!mounted) return;
      setState(() {
        _guidePhase = _MainGuidePhase.home;
      });
    });
  }

  void _finishGuide() {
    setState(() {
      _guidePhase = _MainGuidePhase.none;
    });
  }

  void _pushGuidedPage({
    required Widget page,
    required String pageName,
    required String pageDescription,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SimplePageGuideScope(
          startGuide: true,
          pageName: pageName,
          pageDescription: pageDescription,
          onExitGuide: _finishGuide,
          child: page,
        ),
      ),
    );
  }

  Rect? _rectForKey(GlobalKey key) {
    final context = key.currentContext;
    if (context == null) return null;

    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return null;

    final offset = renderObject.localToGlobal(Offset.zero);
    return offset & renderObject.size;
  }

  Rect? _textHighlightRectForKey(GlobalKey key) {
    final context = key.currentContext;
    if (context == null) return null;

    final renderObject = context.findRenderObject();

    const height = 30.0;
    const horizontalPadding = 16.0;

    // 优先读取 Text 实际绘制出来的文字范围，而不是 Text 组件被父级撑开的布局宽度。
    if (renderObject is RenderParagraph && renderObject.hasSize) {
      final plainText = renderObject.text.toPlainText();

      if (plainText.isNotEmpty) {
        final boxes = renderObject.getBoxesForSelection(
          TextSelection(
            baseOffset: 0,
            extentOffset: plainText.length,
          ),
        );

        if (boxes.isNotEmpty) {
          var left = boxes.first.left;
          var top = boxes.first.top;
          var right = boxes.first.right;
          var bottom = boxes.first.bottom;

          for (final box in boxes.skip(1)) {
            left = math.min(left, box.left);
            top = math.min(top, box.top);
            right = math.max(right, box.right);
            bottom = math.max(bottom, box.bottom);
          }

          final globalTopLeft = renderObject.localToGlobal(Offset(left, top));
          final globalBottomRight =
          renderObject.localToGlobal(Offset(right, bottom));

          final textRect = Rect.fromLTRB(
            globalTopLeft.dx,
            globalTopLeft.dy,
            globalBottomRight.dx,
            globalBottomRight.dy,
          );

          return Rect.fromLTWH(
            textRect.left - horizontalPadding,
            textRect.center.dy - height / 2,
            textRect.width + horizontalPadding * 2,
            height,
          );
        }
      }
    }

    // 兜底：如果不是 Text 渲染对象，则使用组件区域，但限制最大宽度，避免变成长条。
    final rect = _rectForKey(key);
    if (rect == null) return null;

    final top = rect.top + (rect.height - height) / 2;

    return Rect.fromLTWH(
      rect.left - horizontalPadding,
      top,
      math.min(rect.width + horizontalPadding * 2, 180),
      height,
    );
  }


  Rect _settingsSwipeRect(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Rect.fromLTWH(
      size.width * 0.28,
      size.height * 0.54,
      size.width * 0.44,
      30,
    );
  }

  Rect _homeSwipeRect(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Rect.fromLTWH(
      size.width * 0.28,
      size.height * 0.54,
      size.width * 0.44,
      30,
    );
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
      final rect = _textHighlightRectForKey(key);
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
      key: _chatTextKey,
      order: 1,
      id: 'home_chat',
      title: '聊天',
      description: '这里可以进入聊天页。配置好 API 并选择角色后，就可以从这里开始对话。',
      actionLabel: '进入聊天页',
      onAction: () {
        _pushGuidedPage(
          page: const ChatPage(),
          pageName: '聊天页',
          pageDescription: '这里用于和当前角色对话。后续会继续补充输入框、发送按钮、角色切换等详细导览。',
        );
      },
    );
    addTarget(
      key: _characterTextKey,
      order: 2,
      id: 'home_character_library',
      title: '角色库',
      description: '这里用于创建、编辑、导入和管理角色。如果想和自定义角色聊天，可以先从这里新建角色。',
      actionLabel: '进入角色库',
      onAction: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CharacterLibraryPage(
              startGuide: true,
              onExitGuide: _finishGuide,
            ),
          ),
        );
      },
    );
    addTarget(
      key: _worldBookTextKey,
      order: 3,
      id: 'home_world_book',
      title: '世界书库',
      description: '世界书用于保存背景设定、地点、组织、术语等资料。刚开始使用时可以先不用管，熟悉聊天后再学习。',
      actionLabel: '进入世界书库',
      onAction: () {
        _pushGuidedPage(
          page: const WorldBookLibraryPage(),
          pageName: '世界书库',
          pageDescription: '这里用于管理世界书。世界书可以保存背景设定、地点、组织、术语等资料。',
        );
      },
    );
    addTarget(
      key: _backgroundTextKey,
      order: 4,
      id: 'home_background',
      title: '背景图库',
      description: '背景图库用于管理聊天背景和页面背景。它属于外观相关功能，不影响基础聊天流程。',
      actionLabel: '进入背景图库',
      onAction: () {
        _pushGuidedPage(
          page: const BackgroundLibraryPage(),
          pageName: '背景图库',
          pageDescription: '这里用于管理背景图片和背景卡。后续会继续补充导入、编辑和选择背景的导览。',
        );
      },
    );

    targets.add(
      PageGuideTarget(
        id: 'home_settings_swipe',
        order: 5,
        rect: _settingsSwipeRect(context),
        title: '侧滑打开设置页',
        description: '请按住这个细长高光框向左滑动，来打开右侧设置页。API 配置、用户设定、Prompt 策略、备份和教程入口都在设置页中。',
        onSwipeLeft: _startSettingsGuide,
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
      final rect = _textHighlightRectForKey(key);
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
      key: _apiConfigTextKey,
      order: 1,
      id: 'settings_api_config',
      title: 'API 配置',
      description: '这里用于填写 API Key、服务地址和模型。没有 API 配置时，聊天通常无法正常回复。',
      actionLabel: '进入 API 配置',
      onAction: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ApiConfigPage(
              startGuide: true,
              onExitGuide: _finishGuide,
            ),
          ),
        );
      },
    );
    addTarget(
      key: _userSettingsTextKey,
      order: 2,
      id: 'settings_user',
      title: '用户设定',
      description: '这里用于设置“你是谁”。角色会参考这些信息与你互动。新手可以先跳过，等开始聊天后再完善。',
      actionLabel: '进入用户设定',
      onAction: () {
        _pushGuidedPage(
          page: const UserSettingsPage(),
          pageName: '用户设定页',
          pageDescription: '这里用于设置你的昵称、头像等基础信息。角色会参考这些信息与你互动。',
        );
      },
    );
    addTarget(
      key: _promptSettingsTextKey,
      order: 3,
      id: 'settings_prompt',
      title: 'Prompt 策略',
      description: '这里是全局默认 Prompt 策略。它属于进阶功能，熟悉基础聊天后再调整会更稳。',
      actionLabel: '进入 Prompt 策略',
      onAction: () {
        _pushGuidedPage(
          page: const PromptSettingsPage(),
          pageName: 'Prompt 策略页',
          pageDescription: '这里用于调整全局默认 Prompt 策略。它属于进阶功能，熟悉基础聊天后再调整会更稳。',
        );
      },
    );
    addTarget(
      key: _backupTextKey,
      order: 4,
      id: 'settings_backup',
      title: '备份与恢复',
      description: '这里用于备份和恢复应用数据。大量编辑角色或升级应用前，建议先备份。',
      actionLabel: '进入备份与恢复',
      onAction: () {
        _pushGuidedPage(
          page: const BackupRestorePage(),
          pageName: '备份与恢复页',
          pageDescription: '这里用于导出完整备份或导入备份。大量编辑角色或升级应用前，建议先备份。',
        );
      },
    );
    addTarget(
      key: _tutorialTextKey,
      order: 5,
      id: 'settings_tutorial',
      title: '教程与导览',
      description: '以后如果忘记某个操作，可以从这里重新打开页面导览和推荐路线。',
      actionLabel: '进入教程中心',
      onAction: () {
        _pushGuidedPage(
          page: TutorialHomePage(
            onStartNewUserGuide: _startNewUserGuide,
            onStartSettingsGuide: _startSettingsGuide,
          ),
          pageName: '教程与导览页',
          pageDescription: '这里可以重新开始新用户快速导览，也可以查看各页面导览入口。',
        );
      },
    );

    targets.add(
      PageGuideTarget(
        id: 'settings_back_home_swipe',
        order: 6,
        rect: _homeSwipeRect(context),
        title: '滑动返回主菜单',
        description: '在设置页按住这个细长高光框向右滑动，可以回到主菜单。',
        onSwipeRight: _returnToHomeGuide,
      ),
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

    return PopScope(
      canPop: _guidePhase == _MainGuidePhase.none,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_guidePhase != _MainGuidePhase.none) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('教程模式中，请点击顶部“退出”结束教程。')),
          );
        }
      },
      child: Scaffold(
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
                                  title: Text('聊天', key: _chatTextKey),
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
                                  title: Text('角色库', key: _characterTextKey),
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
                                  title: Text('世界书库', key: _worldBookTextKey),
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
                                  title: Text('背景图库', key: _backgroundTextKey),
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
                        apiConfigTextKey: _apiConfigTextKey,
                        userSettingsTextKey: _userSettingsTextKey,
                        promptSettingsTextKey: _promptSettingsTextKey,
                        backupTextKey: _backupTextKey,
                        tutorialTextKey: _tutorialTextKey,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_guidePhase == _MainGuidePhase.home)
              PageGuideOverlay(
                title: '主页导览',
                hint: '点击文字高光框会进入对应页面；点击编号可展开说明。第 5 项请在细长高光框内向左滑动打开设置页。',
                targets: _homeGuideTargets(context),
                onExit: _finishGuide,
              ),
            if (_guidePhase == _MainGuidePhase.settings)
              PageGuideOverlay(
                title: '设置页导览',
                hint: '点击文字高光框会进入对应页面；点击编号可展开说明。第 6 项请在细长高光框内向右滑动返回主菜单。',
                targets: _settingsGuideTargets(context),
                onExit: _finishGuide,
              ),
          ],
        ),
      ),
    ),
    );
  }
}
