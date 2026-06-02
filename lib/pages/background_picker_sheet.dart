import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import '../models/background_card.dart';
import '../services/background_service.dart';
import '../models/character_card.dart';
import '../services/database_service.dart';

class BackgroundPickerSheet extends StatefulWidget {
  final CharacterCard? character;
  const BackgroundPickerSheet({super.key, this.character});

  @override
  State<BackgroundPickerSheet> createState() => _BackgroundPickerSheetState();
}

class _BackgroundPickerSheetState extends State<BackgroundPickerSheet>
    with SingleTickerProviderStateMixin {
  List<BackgroundCard> _backgrounds = [];
  int _currentIndex = 0;
  final PageController _pageController = PageController(viewportFraction: 0.8);

  late AnimationController _bgAnimController;
  late Animation<double> _bgOpacity;
  late Animation<double> _cardScale;

  @override
  void initState() {
    super.initState();
    _bgAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _bgOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _bgAnimController, curve: Curves.easeOut),
    );
    _cardScale = Tween<double>(begin: 0.9, end: 1.0).animate(
      CurvedAnimation(parent: _bgAnimController, curve: Curves.easeOutBack),
    );
    _loadBackgrounds();
    _bgAnimController.forward();
  }

  Future<void> _loadBackgrounds() async {
    final all = await BackgroundService.getAll();
    final current = await BackgroundService.getCurrent();
    final startIndex = all.indexWhere((b) => b.id == current?.id);
    setState(() {
      _backgrounds = all;
      _currentIndex = startIndex >= 0 ? startIndex : 0;
    });
    if (_backgrounds.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pageController.hasClients) {
          _pageController.jumpToPage(_currentIndex);
        }
      });
    }
  }

  void _applyBackground(BackgroundCard bg) async {
    if (widget.character != null) {
      widget.character!.backgroundId = bg.id;
      await DatabaseService.updateCharacter({
        'id': widget.character!.id,
        'background_id': bg.id,
      });
    } else {
      await BackgroundService.setCurrent(bg.id);
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _bgAnimController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_backgrounds.isEmpty) {
      return const Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(child: Text('没有可用背景')),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GestureDetector(
        onTap: () => Navigator.pop(context),
        child: AnimatedBuilder(
          animation: _bgAnimController,
          builder: (context, child) {
            return Stack(
              children: [
                // 毛玻璃背景
                Positioned.fill(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(
                        sigmaX: 10 * _bgOpacity.value,
                        sigmaY: 10 * _bgOpacity.value),
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.4 * _bgOpacity.value),
                    ),
                  ),
                ),
                // 卡片选择区域
                Center(
                  child: Transform.scale(
                    scale: _cardScale.value,
                    child: SizedBox(
                      height: MediaQuery.of(context).size.height * 0.7,
                      child: PageView.builder(
                        controller: _pageController,
                        itemCount: _backgrounds.length,
                        onPageChanged: (index) {
                          setState(() => _currentIndex = index);
                        },
                        itemBuilder: (context, index) {
                          final bg = _backgrounds[index];
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: GestureDetector(
                              onTap: () => _applyBackground(bg),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(20),
                                child: _buildPreview(bg),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
                // 顶部背景名称
                Positioned(
                  top: MediaQuery.of(context).padding.top + 16,
                  left: 60,
                  right: 60,
                  child: Center(
                    child: Opacity(
                      opacity: _bgOpacity.value,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.white.withAlpha(80),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              _currentIndex < _backgrounds.length
                                  ? _backgrounds[_currentIndex].name
                                  : '',
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildPreview(BackgroundCard bg) {
    switch (bg.type) {
      case 'color':
        try {
          final data = jsonDecode(bg.colorValue.isEmpty ? '{}' : bg.colorValue);
          final active = data['active'] as String?;
          if (active == 'color' && data.containsKey('color')) {
            final hex = data['color'] as String;
            return Container(
              color: Color(int.parse(hex.replaceFirst('#', 'FF'), radix: 16)),
            );
          }
        } catch (_) {}
        return Container(color: Colors.grey[300]);
      case 'gradient':
        try {
          final data = jsonDecode(bg.colorValue.isEmpty ? '{}' : bg.colorValue);
          final gradientList = data['gradient'] as List?;
          if (gradientList != null && gradientList.isNotEmpty) {
            final colors = <Color>[];
            final stops = <double>[];
            for (final item in gradientList) {
              final hex = item['color'] as String?;
              if (hex != null) {
                colors.add(
                    Color(int.parse(hex.replaceFirst('#', 'FF'), radix: 16)));
                stops.add((item['position'] as num?)?.toDouble() ?? 0.0);
              }
            }
            if (colors.isNotEmpty) {
              final first = gradientList.first as Map<String, dynamic>;
              final sx = (first['startX'] as num?)?.toDouble() ?? 0.5;
              final sy = (first['startY'] as num?)?.toDouble() ?? 0.0;
              final ex = (first['endX'] as num?)?.toDouble() ?? 0.5;
              final ey = (first['endY'] as num?)?.toDouble() ?? 1.0;
              return Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment(sx * 2 - 1, sy * 2 - 1),
                    end: Alignment(ex * 2 - 1, ey * 2 - 1),
                    colors: colors,
                    stops: stops,
                  ),
                ),
              );
            }
          }
        } catch (_) {}
        return Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFE3F2FD), Color(0xFFF3E5F5)],
            ),
          ),
        );
      case 'image':
        if (bg.originalImagePath.isNotEmpty) {
          final file = File(bg.originalImagePath);
          if (file.existsSync()) {
            return Image.file(file, fit: BoxFit.cover);
          }
        }
        return Container(color: Colors.grey[300]);
      default:
        return Container(color: Colors.grey[300]);
    }
  }
}