import 'package:flutter/material.dart';
import '../services/background_service.dart';
import 'background_library_page.dart';
import 'chat_page.dart';
import 'settings_menu_page.dart';
import 'character_library_page.dart';
import 'world_book_library_page.dart';



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

  void _onHorizontalDragStart(DragStartDetails details) {
    _dragStartOffset = details.globalPosition.dx;
    _panelStartValue = _animationController.value;
    _animationController.stop();
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    final dx = details.globalPosition.dx - _dragStartOffset;
    final totalMove = panelWidth;
    double newValue =
    (_panelStartValue - dx / totalMove).clamp(0.0, 1.0);
    _animationController.value = newValue;
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    if (details.primaryVelocity != null && details.primaryVelocity! < -300) {
      _openPanel();
    } else if (details.primaryVelocity != null && details.primaryVelocity! > 300) {
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
        onHorizontalDragStart: _onHorizontalDragStart,
        onHorizontalDragUpdate: _onHorizontalDragUpdate,
        onHorizontalDragEnd: _onHorizontalDragEnd,
        child: Stack(
          children: [
            // 使用 Positioned 让 Row 可以超出屏幕右边界
            Positioned(
              left: leftOffset,
              top: 0,
              bottom: 0,
              width: screenWidth + panelW,
              child: Row(
                children: [
                  // 主菜单，严格占满屏幕宽度
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
                            children: [
                              ListTile(
                                leading: const Icon(Icons.chat),
                                title: const Text('聊天'),
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (_) => const ChatPage()),
                                  );
                                },
                              ),
                              ListTile(
                                leading: const Icon(Icons.people),
                                title: const Text('角色库'),
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => const CharacterLibraryPage()),
                                  );
                                },
                              ),
                              ListTile(
                                leading: const Icon(Icons.book),
                                title: const Text('世界书库'),
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => const WorldBookLibraryPage()),
                                  );
                                },
                              ),
                              ListTile(
                                leading: const Icon(Icons.image),
                                title: const Text('背景图库'),
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => const BackgroundLibraryPage()),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 设置面板，宽度为 panelW
                  SizedBox(
                    width: panelW,
                    child: Container(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      child: const SettingsMenuPage(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}