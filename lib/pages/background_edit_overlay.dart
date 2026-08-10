import 'package:flutter/material.dart';
import '../models/background_card.dart';
import '../shared/theme/app_theme_tokens.dart';
import '../widgets/sub_page_backdrop.dart';

class BackgroundEditOverlay extends StatelessWidget {
  final BackgroundCard background;

  const BackgroundEditOverlay({super.key, required this.background});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GestureDetector(
        onTap: () => Navigator.pop(context),
        behavior: HitTestBehavior.opaque,
        child: Container(
          color: Colors.black54, // 半透明灰色
          child: Center(
            child: GestureDetector(
              onTap: () {}, // 阻止点击穿透
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: SubPageBackdrop(
                  child: Container(
                width: MediaQuery.of(context).size.width * 0.9,
                height: MediaQuery.of(context).size.height * 0.65,
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: background.isPreset
                    ? _buildPresetEditor(context)
                    : _buildCustomEditor(context),
              ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPresetEditor(BuildContext context) {
    final muted = AppThemeTokens.of(context).textMuted;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_awesome, size: 48, color: muted),
          const SizedBox(height: 16),
          const Text(
            '默认背景编辑',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            '纯色 / 渐变 / 上传\n（功能待实现）',
            textAlign: TextAlign.center,
            style: TextStyle(color: muted),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomEditor(BuildContext context) {
    final muted = AppThemeTokens.of(context).textMuted;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.image, size: 48, color: muted),
          const SizedBox(height: 16),
          const Text(
            '自定义背景编辑',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            '名称 / 场景设定 / 预览\n（功能待实现）',
            textAlign: TextAlign.center,
            style: TextStyle(color: muted),
          ),
        ],
      ),
    );
  }
}