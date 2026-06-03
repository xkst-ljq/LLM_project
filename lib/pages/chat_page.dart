// ignore_for_file: use_build_context_synchronously
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';
import '../models/character_entry.dart';
import '../models/world_book_entry.dart';
import '../modules/chat_module.dart';
import '../models/character_card.dart';
import '../services/database_service.dart';
import '../services/api_config_service.dart';
import '../models/user_profile.dart';
import '../services/user_service.dart';
import 'background_picker_sheet.dart';
import 'role_user_settings_page.dart';
import '../services/background_service.dart';
import '../models/background_card.dart';
import 'package:markdown/markdown.dart' as md hide Text;
import 'package:flutter_markdown/flutter_markdown.dart';
import '../utils/protagonist_setting_utils.dart';

class ChatPage extends StatefulWidget {
  final CharacterCard? character;

  const ChatPage({super.key, this.character});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with TickerProviderStateMixin {
  final TextEditingController _msgController = TextEditingController();
  final List<Map<String, dynamic>> _messages = [];
  final double _panelWidthFraction = 0.5; // 设置面板占屏幕宽度比例
  late AnimationController _animController; // 平移控制
  double _dragStartOffset = 0.0;
  double _panelStartValue = 0.0;
  String? _dynamicUserDetail;
  List<WorldBookEntry>? _cachedWorldBookEntries;
  String? _cachedWorldBookId;
  late AnimationController _fanSnapController;
  double _fanSnapStart = 0.0;
  double _fanSnapTarget = 0.0;

  bool _isLastMessage(int index) {
    return index == _messages.length - 1 && !_isLoading;
  }

  List<CharacterCard> _selectableCharacters = [];

  Future<void> _loadSelectableCharacters() async {
    final all = await DatabaseService.getAllCharacters();
    setState(() {
      _selectableCharacters = all
          .map(
            (c) => CharacterCard(
              id: c['id'] as String,
              name: c['name'] as String,
              avatar: c['avatar'] as String? ?? '',
              cardImagePath: c['card_image_path'] as String? ?? '',
              description: c['description'] as String? ?? '',
              systemPrompt: c['system_prompt'] as String? ?? '',
              userName: c['user_name'] as String? ?? '',
              userAvatar: c['user_avatar'] as String? ?? '',
              userDetailSetting: c['user_detail_setting'] as String? ?? '',
            ),
          )
          .where((c) => c.id != _currentCharacter?.id)
          .toList();
    });
  }

  void _onGlobalUserChanged() {
    if (!mounted) return;
    _loadUser();
  }

  Widget _buildBackground(BackgroundCard bg) {
    switch (bg.type) {
      case 'color':
        return _buildColorBackground(bg.colorValue);
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
                  Color(int.parse(hex.replaceFirst('#', 'FF'), radix: 16)),
                );
                stops.add((item['position'] as num?)?.toDouble() ?? 0.0);
              }
            }
            if (colors.isNotEmpty) {
              // 使用第一个停止点的方向作为整体渐变方向
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
        // 解析失败或没有数据时，返回默认渐变
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

  Widget _buildColorBackground(String colorValue) {
    try {
      final data = jsonDecode(colorValue.isEmpty ? '{}' : colorValue);
      final active = data['active'] as String?;
      if (active == 'color' && data.containsKey('color')) {
        final hex = data['color'] as String;
        final color = Color(int.parse(hex.replaceFirst('#', 'FF'), radix: 16));
        return Container(color: color);
      }
    } catch (_) {}
    // 解析失败返回默认渐变
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFE3F2FD), Color(0xFFF3E5F5)],
        ),
      ),
    );
  }

  // 椭圆轮盘
  double _fanOffset = 0.0; // 弧长偏移量
  double _cardDs = 80.0; // 卡片弧长间距（缓存）
  double _halfArcLen = 200.0; // 上半弧长的一半（缓存）
  int _cardCount = 0;

  // 惯性滑动
  Ticker? _inertiaTicker;
  double _inertiaVelocity = 0.0;

  // 详情弹窗
  bool _showCardDetail = false;
  CharacterCard? _detailCard;
  late AnimationController _detailAnimController;
  late Animation<double> _detailScaleAnim;
  late Animation<double> _detailFadeAnim;

  List<WorldBookEntry> _getActiveWorldBookEntries(int scanDepth) {
    // 缓存：避免每次请求都解析 JSON
    if (_cachedWorldBookId == _currentCharacter?.worldBookId &&
        _cachedWorldBookEntries != null) {
      return _filterActiveEntries(_cachedWorldBookEntries!, scanDepth);
    }
    return [];
  }

  void _cacheWorldBookEntries(List<WorldBookEntry> entries) {
    _cachedWorldBookEntries = entries;
    _cachedWorldBookId = _currentCharacter?.worldBookId;
  }

  List<WorldBookEntry> _filterActiveEntries(
    List<WorldBookEntry> allEntries,
    int scanDepth,
  ) {
    final activeIds = <String>{};

    // 永久激活
    for (final e in allEntries) {
      if (e.alwaysActive) activeIds.add(e.id);
    }

    // 关键词匹配
    final recentText = _messages.reversed
        .take(scanDepth)
        .map((m) => m['content'] as String)
        .join(' ');

    for (final e in allEntries) {
      if (e.keyword.isNotEmpty && recentText.contains(e.keyword)) {
        activeIds.add(e.id);
      }
    }

    // 递归扩展
    bool changed = true;
    int rounds = 3;
    while (changed && rounds > 0) {
      changed = false;
      rounds--;
      final activatedContent = allEntries
          .where((e) => activeIds.contains(e.id) && e.recursive)
          .map((e) => e.content)
          .join(' ');
      for (final e in allEntries) {
        if (!activeIds.contains(e.id) &&
            e.keyword.isNotEmpty &&
            activatedContent.contains(e.keyword)) {
          activeIds.add(e.id);
          changed = true;
        }
      }
    }

    return allEntries.where((e) => activeIds.contains(e.id)).toList();
  }

  Map<String, String> _parseCharacterInfo(CharacterCard card) {
    String background = card.description.isNotEmpty ? card.description : '';
    String scenario = '';

    final prompt = card.systemPrompt;
    if (prompt.isNotEmpty) {
      // 尝试从 systemPrompt 提取当前情景
      for (final kw in ['当前情景', '当前场景', '情景：', '场景：', '开场']) {
        final idx = prompt.indexOf(kw);
        if (idx != -1) {
          final start = idx + kw.length;
          final raw = prompt
              .substring(start, (start + 150).clamp(0, prompt.length))
              .trim();
          final cut = raw.indexOf('\n\n');
          scenario = cut != -1 ? raw.substring(0, cut).trim() : raw;
          break;
        }
      }
      // 若 description 为空，用 prompt 首段作为背景介绍
      if (background.isEmpty) {
        final first = prompt.split('\n\n').first.trim();
        background = first.length > 120 ? '${first.substring(0, 120)}…' : first;
      }
    }

    return {
      'name': card.name,
      'background': background.isEmpty ? '暂无介绍' : background,
      'scenario': scenario,
    };
  }

  String _detailFieldLabel(
      String entryId,
      String fieldKey, {
        String? parentKey,
      }) {
    const map = {
      'name_entry': {
        'last_name': '姓',
        'first_name': '名',
        'other': '其他',
      },
      'body': {
        'race': '种族',
        'gender': '性别',
        'age': '年龄',
        'height': '身高',
        'weight': '体重',
        'measurements': '三围',
        'other': '其他数据',
      },
      'psychology': {
        'personality': '性格',
        'thoughts': '思想',
        'interests': '兴趣/爱好/癖好',
      },
      'background': {
        'origin': '出身背景',
        'experiences': '经历事件',
        'current': '当前背景',
      },
      'system_details': {
        'world_setting': '世界设定',
        'worldview': '世界观设定',
        'system_mechanism': '系统机制设定',
      },
      'protagonist': {
        'name': '主角名称',
        'detail': '主角详细设定',
      },
      'plot': {
        'cause': '起因',
        'events': '中途特定触发事件',
        'goal': '目标',
        'possible_endings': '可能结局设定',
      },
    };

    // 系统卡 protagonist.detail 下的字段
    if (entryId == 'protagonist' && parentKey == 'detail') {
      const detailMap = {
        'race': '种族',
        'gender': '性别',
        'age': '年龄',
        'body': '身体',
        'background': '背景',
      };
      return detailMap[fieldKey] ?? fieldKey;
    }

    return map[entryId]?[fieldKey] ?? fieldKey;
  }

  String _indentDetailLines(String text) {
    return text
        .split('\n')
        .map((line) => line.trim().isEmpty ? line : '  $line')
        .join('\n');
  }

  String _formatEntryValueForDetail(
      String entryId,
      dynamic value, {
        String? parentKey,
      }) {
    if (value == null) return '';

    if (value is Map) {
      final lines = <String>[];

      for (final rawKey in value.keys) {
        final key = rawKey.toString();
        final childValue = value[rawKey];

        final label = _detailFieldLabel(
          entryId,
          key,
          parentKey: parentKey,
        );

        final formatted = _formatEntryValueForDetail(
          entryId,
          childValue,
          parentKey: key,
        ).trim();

        if (formatted.isEmpty) continue;

        if (childValue is Map) {
          lines.add('$label：\n${_indentDetailLines(formatted)}');
        } else {
          lines.add('$label：$formatted');
        }
      }

      return lines.join('\n');
    }

    if (value is List) {
      return value
          .map((e) => _formatEntryValueForDetail(entryId, e).trim())
          .where((e) => e.isNotEmpty)
          .join('、');
    }

    return value.toString().trim();
  }

  String _formatEntryForDetailPanel(CharacterEntry entry) {
    final raw = entry.content.trim();
    if (raw.isEmpty) return '';

    if (raw.startsWith('{')) {
      try {
        final decoded = jsonDecode(raw);
        final formatted = _formatEntryValueForDetail(entry.id, decoded).trim();
        if (formatted.isNotEmpty) return formatted;
      } catch (_) {
        return raw;
      }
    }

    return raw;
  }

  String _buildCharacterDetailText(CharacterCard card) {
    try {
      final rawList = jsonDecode(
        card.entriesJson.isEmpty ? '[]' : card.entriesJson,
      ) as List;

      final entries = rawList
          .map(
            (e) => CharacterEntry.fromJson(
          Map<String, dynamic>.from(e as Map),
        ),
      )
          .toList();

      final detailIds = card.cardType == 'system'
          ? {
        'system_details',
        'protagonist',
        'plot',
      }
          : {
        'body',
        'psychology',
        'background',
      };

      final detailEntries = entries.where((entry) {
        if (entry.content.trim().isEmpty) return false;

        // 详情展示页用于查看角色卡信息，不一定只显示启用条目。
        // 如果你只想显示启用条目，可以取消下一行注释：
        // if (!entry.enabled) return false;

        return detailIds.contains(entry.id) || entry.isCustom;
      }).toList();

      if (detailEntries.isEmpty) {
        return '暂无详细设定';
      }

      final sections = <String>[];

      for (final entry in detailEntries) {
        final content = _formatEntryForDetailPanel(entry).trim();
        if (content.isEmpty) continue;

        sections.add('【${entry.title}】\n$content');
      }

      if (sections.isEmpty) return '暂无详细设定';

      return sections.join('\n\n');
    } catch (_) {
      return '暂无详细设定';
    }
  }

  Widget _buildDetailSettingPanel(CharacterCard card) {
    final detailText = _buildCharacterDetailText(card);
    final screenHeight = MediaQuery.of(context).size.height;

    // 固定高度，但根据屏幕大小略微自适应
    final panelHeight = (screenHeight * 0.13).clamp(96.0, 135.0).toDouble();

    final hasImage =
        card.cardImagePath.isNotEmpty && File(card.cardImagePath).existsSync();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          height: panelHeight,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 背景：优先使用角色卡封面高斯模糊
              if (hasImage)
                ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Transform.scale(
                    scale: 1.06,
                    child: Image.file(
                      File(card.cardImagePath),
                      fit: BoxFit.cover,
                    ),
                  ),
                )
              else
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withValues(alpha: 0.22),
                        Colors.white.withValues(alpha: 0.10),
                      ],
                    ),
                  ),
                ),

              // 遮罩：保证文字可读性
              Container(
                color: hasImage
                    ? Colors.black.withValues(alpha: 0.52)
                    : Colors.black.withValues(alpha: 0.18),
              ),

              // 边框
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.22),
                  ),
                ),
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 标题栏
                    Row(
                      children: [
                        Icon(
                          Icons.article_outlined,
                          size: 16,
                          color: Colors.white.withValues(alpha: 0.92),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '详细设定',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.94),
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 6),

                    // 内容区：固定框内滚动
                    Expanded(
                      child: Scrollbar(
                        thumbVisibility: false,
                        child: SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          child: Text(
                            detailText,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.92),
                              fontSize: 12,
                              height: 1.45,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 惯性结束后吸附到最近卡片
  void _snapFanOffset() {
    final maxOffset = (_cardCount - 1) / 2.0 * _cardDs;
    final snapped = (_fanOffset / _cardDs).round() * _cardDs;
    setState(() {
      _fanOffset = snapped.clamp(-maxOffset, maxOffset);
    });
  }

  /// 启动惯性（拖拽结束时调用）
  void _startInertia(double velocityPxSec) {
    _inertiaTicker?.stop();
    _inertiaTicker?.dispose();
    _inertiaTicker = null;

    // 拖拽方向与 fanOffset 方向相反（向右拖 → fanOffset 减少）
    _inertiaVelocity = velocityPxSec;

    if (_inertiaVelocity.abs() < 60) {
      _snapFanOffset();
      return;
    }

    DateTime? lastTime;
    _inertiaTicker = createTicker((_) {
      if (!mounted) return;
      final now = DateTime.now();
      final dtSec = lastTime == null
          ? 0.016
          : now.difference(lastTime!).inMicroseconds / 1e6;
      lastTime = now;

      final maxOffset = (_cardCount - 1) / 2.0 * _cardDs;
      setState(() {
        _fanOffset += _inertiaVelocity * dtSec;
        _inertiaVelocity *= pow(0.92, dtSec * 60).toDouble(); // 摩擦减速

        if (_fanOffset.abs() >= maxOffset) {
          _fanOffset = _fanOffset.clamp(-maxOffset, maxOffset);
          _inertiaVelocity = 0;
        }
        // 速度低于阈值 → 吸附停止
        if (_inertiaVelocity.abs() < 80) {
          _snapFanOffset();
          _inertiaTicker?.stop();
          _inertiaTicker?.dispose();
          _inertiaTicker = null;
        }
      });
    });
    _inertiaTicker!.start();
  }

  Widget _buildFanCards() {
    final cards = _selectableCharacters;
    if (cards.isEmpty) {
      return const Center(
        child: Text('没有可切换的角色', style: TextStyle(color: Colors.white70)),
      );
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    // ── 水平弧形参数（新版排序方式） ──
    final cx = screenWidth / 2;
    final baseY = screenHeight - 240.0; // 轮盘基准线，保持在屏幕偏下
    const cardW = 140.0;
    const cardH = 210.0;
    const cornerR = 12.0;
    const ds = 80.0; // 卡片间距（沿用旧变量 _cardDs）
    _cardDs = ds;

    _cardCount = cards.length;
    // 把“半弧长”语义替换为屏幕中心线，这样旧的 _snapFanOffset / 惯性 / 居中判断全部兼容
    _halfArcLen = screenWidth / 2;

    // 轻微弧形：中间向上凸，两边自然下沉（最大 40 像素）
    double getArcY(double x) {
      final dx = (x - cx).abs() / (screenWidth * 0.6);
      return dx * dx * 40.0;
    }

    final centerIdx = (cards.length - 1) / 2.0;

    // 边界限制（语义与旧版保持一致）
    final maxFanOffset = _halfArcLen + centerIdx * ds;
    _fanOffset = _fanOffset.clamp(-maxFanOffset, maxFanOffset);

    final List<_FanCard> fanCards = [];
    for (int i = 0; i < cards.length; i++) {
      final x = cx + (centerIdx - i) * ds + _fanOffset;
      final y = baseY + getArcY(x);

      // 超出可视区过远的卡片不渲染（可选优化）
      if (x < -cardW || x > screenWidth + cardW) continue;

      final fc = _FanCard(character: cards[i], t: 0.0);
      fc._x = x;
      fc._y = y;
      // 不再旋转，保持水平
      fc._arcS = x; // 用 x 坐标替代旧版弧长，用于居中判断
      fc._index = i;
      fanCards.add(fc);
    }

    // 按 y 降序：y 大（靠下）的先画，中间（靠上）的后画 → 中间卡片在最上层
    fanCards.sort((a, b) => b._y.compareTo(a._y));

    return SizedBox.expand(
      child: Stack(
        clipBehavior: Clip.none,
        children: fanCards.map((card) {
          final isCentered = (card._arcS - _halfArcLen).abs() < ds * 0.5;

          return Positioned(
            left: card._x - cardW / 2,
            top: card._y,
            // 新版 y 已经是顶部坐标，不再减 cardH
            width: cardW,
            height: cardH,
            child: GestureDetector(
              onTap: () {
                if (isCentered) {
                  setState(() {
                    _detailCard = card.character;
                    _showCardDetail = true;
                  });
                  _detailAnimController.forward(from: 0);
                } else {
                  // 停止惯性，避免冲突
                  _inertiaTicker?.stop();
                  _inertiaTicker?.dispose();
                  _inertiaTicker = null;

                  final targetOffset = (card._index - centerIdx) * _cardDs;
                  final maxOff = _halfArcLen + centerIdx * _cardDs;
                  final clampedTarget = targetOffset.clamp(-maxOff, maxOff);

                  _fanSnapStart = _fanOffset;
                  _fanSnapTarget = clampedTarget;
                  _fanSnapController.forward(from: 0);
                }
              },
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(cornerR),
                  boxShadow: [
                    BoxShadow(
                      color: isCentered
                          ? Colors.white.withValues(alpha: 0.2)
                          : Colors.black38,
                      blurRadius: isCentered ? 20 : 8,
                      spreadRadius: isCentered ? 3 : 0,
                      offset: const Offset(0, 3),
                    ),
                  ],
                  image: card.character.cardImagePath.isNotEmpty
                      ? DecorationImage(
                          image: FileImage(File(card.character.cardImagePath)),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: card.character.cardImagePath.isEmpty
                    ? Container(
                        decoration: BoxDecoration(
                          color: Colors.grey[400],
                          borderRadius: BorderRadius.circular(cornerR),
                        ),
                        child: Center(
                          child: Text(
                            card.character.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : null,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildCardDetailOverlay(CharacterCard card) {
    final info = _parseCharacterInfo(card);
    const cardW = 215.0;
    const cardH = 320.0;

    return Positioned.fill(
      child: AnimatedBuilder(
        animation: _detailAnimController,
        builder: (ctx, child) {
          final fadeVal = _detailFadeAnim.value;
          final scaleVal = _detailScaleAnim.value;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              _detailAnimController.reverse().then((_) {
                if (mounted) setState(() => _showCardDetail = false);
              });
            },
            child: Stack(
              children: [
                // 磨砂玻璃背景（可透见轮盘）
                Positioned.fill(
                  child: Opacity(
                    opacity: fadeVal,
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                ),
                // 内容（缩放动画）
                Opacity(
                  opacity: fadeVal,
                  child: Transform.scale(
                    scale: 0.6 + 0.4 * scaleVal,
                    child: GestureDetector(
                      onTap: () {}, // 阻止冒泡关闭
                      child: Column(
                        children: [
                          // 顶部简介面板
                          SafeArea(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: BackdropFilter(
                                  filter: ImageFilter.blur(
                                    sigmaX: 10,
                                    sigmaY: 10,
                                  ),
                                  child: Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: 0.13,
                                      ),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: Colors.white.withValues(
                                          alpha: 0.2,
                                        ),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          info['name']!,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        if (info['background']!.isNotEmpty) ...[
                                          const SizedBox(height: 6),
                                          Text(
                                            '背景介绍',
                                            style: TextStyle(
                                              color: Colors.white.withValues(
                                                alpha: 0.55,
                                              ),
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            info['background']!,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 13,
                                              height: 1.45,
                                            ),
                                            maxLines: 3,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                        if (info['scenario']!.isNotEmpty) ...[
                                          const SizedBox(height: 8),
                                          Text(
                                            '当前情景',
                                            style: TextStyle(
                                              color: Colors.white.withValues(
                                                alpha: 0.55,
                                              ),
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            info['scenario']!,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 13,
                                              height: 1.45,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          _buildDetailSettingPanel(card),
                          // 放大卡片 + 播放按钮
                          Expanded(
                            child: Center(
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  Container(
                                    width: cardW,
                                    height: cardH,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(16),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(
                                            alpha: 0.45,
                                          ),
                                          blurRadius: 30,
                                          offset: const Offset(0, 10),
                                        ),
                                      ],
                                      image: card.cardImagePath.isNotEmpty
                                          ? DecorationImage(
                                              image: FileImage(
                                                File(card.cardImagePath),
                                              ),
                                              fit: BoxFit.cover,
                                            )
                                          : null,
                                    ),
                                    child: card.cardImagePath.isEmpty
                                        ? Container(
                                            decoration: BoxDecoration(
                                              color: Colors.grey[400],
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                            ),
                                            child: Center(
                                              child: Text(
                                                card.name,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 20,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          )
                                        : null,
                                  ),
                                  // 播放按钮（右下角）
                                  Positioned(
                                    right: -12,
                                    bottom: -12,
                                    child: GestureDetector(
                                      onTap: () {
                                        _switchCharacter(card);
                                        _detailAnimController.reverse().then((
                                          _,
                                        ) {
                                          if (mounted) {
                                            setState(() {
                                              _showCardDetail = false;
                                              _showFanPanel = false;
                                            });
                                          }
                                        });
                                      },
                                      child: Container(
                                        width: 54,
                                        height: 54,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: Colors.white,
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withValues(
                                                alpha: 0.25,
                                              ),
                                              blurRadius: 12,
                                              offset: const Offset(0, 4),
                                            ),
                                          ],
                                        ),
                                        child: const Icon(
                                          Icons.play_arrow_rounded,
                                          color: Colors.black87,
                                          size: 34,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 32),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  double get panelWidth =>
      MediaQuery.of(context).size.width * _panelWidthFraction;
  bool _isLoading = false;
  bool _showFanPanel = false;
  late AnimationController _inputAnimController;
  late Animation<double> _inputExpandAnimation;
  late CharacterCard? _currentCharacter;
  final ScrollController _scrollController = ScrollController();
  bool _inputExpanded = false;
  int _editingIndex = -1;
  String _editingOriginalContent = '';

  int _estimateTokens() {
    int totalChars = 0;
    for (final msg in _messages) {
      totalChars += (msg['content'] as String?)?.length ?? 0;
    }
    // 粗略估算：每 2 个字符 ≈ 1 token
    return (totalChars / 2).ceil();
  }

  UserProfile _currentUser = UserProfile();

  Future<void> _loadUser() async {
    final globalUser = await UserService.getUser();
    if (_currentCharacter != null) {
      // 重新从数据库读取角色数据，确保获取最新设定
      final allChars = await DatabaseService.getAllCharacters();
      final updatedCharData = allChars.firstWhere(
        (c) => c['id'] == _currentCharacter!.id,
        orElse: () => <String, dynamic>{},
      );
      if (updatedCharData.isNotEmpty) {
        _currentCharacter = CharacterCard(
          id: updatedCharData['id'] as String,
          name: updatedCharData['name'] as String,
          avatar: updatedCharData['avatar'] as String? ?? '',
          cardImagePath: updatedCharData['card_image_path'] as String? ?? '',
          description: updatedCharData['description'] as String? ?? '',
          systemPrompt: updatedCharData['system_prompt'] as String? ?? '',
          userName: updatedCharData['user_name'] as String? ?? '',
          userAvatar: updatedCharData['user_avatar'] as String? ?? '',
          backgroundId: updatedCharData['background_id'] as String? ?? '',
          worldBookId: updatedCharData['world_book_id'] as String? ?? '',
          userDetailSetting:
              updatedCharData['user_detail_setting'] as String? ?? '',
          cardType: updatedCharData['card_type'] as String? ?? 'character',
          entriesJson: updatedCharData['entries_json'] as String? ?? '[]',
          openingGreetings:
              updatedCharData['opening_greetings'] as String? ?? '[]',
        );
      }

      final localName = _currentCharacter!.userName;
      final localAvatar = _currentCharacter!.userAvatar;
      final localDetail = _currentCharacter!.userDetailSetting;

      final protagonistName =
      ProtagonistSettingUtils.getProtagonistName(_currentCharacter!);

      final protagonistDetail =
      ProtagonistSettingUtils.formatProtagonistDetail(_currentCharacter!);

      final effectiveName = localName.isNotEmpty
          ? localName
          : protagonistName.isNotEmpty
          ? protagonistName
          : globalUser.name;

      final effectiveAvatar = localAvatar.isNotEmpty
          ? localAvatar
          : globalUser.avatarPath;

      final effectiveDetail = localDetail.isNotEmpty
          ? localDetail
          : protagonistDetail.isNotEmpty
          ? protagonistDetail
          : '';

      _currentUser = UserProfile(
        name: effectiveName,
        avatarPath: effectiveAvatar,
      );

      _dynamicUserDetail = effectiveDetail.isNotEmpty ? effectiveDetail : null;

      setState(() {});
      return;
    }
    _currentUser = globalUser;
    _dynamicUserDetail = null;
    setState(() {});
  }

  bool _isLatestAiMessage(int index) {
    if (index < 0 || index >= _messages.length) return false;
    final msg = _messages[index];
    if (msg['role'] != 'assistant') return false;
    // 从后往前找第一个 assistant
    for (int i = _messages.length - 1; i >= 0; i--) {
      if (_messages[i]['role'] == 'assistant') {
        return i == index;
      }
    }
    return false;
  }

  bool _isLatestUserMessage(int index) {
    if (index < 0 || index >= _messages.length) return false;
    final msg = _messages[index];
    if (msg['role'] != 'user') return false;
    for (int i = _messages.length - 1; i >= 0; i--) {
      if (_messages[i]['role'] == 'user') {
        return i == index;
      }
    }
    return false;
  }

  @override
  void initState() {
    super.initState();

    UserService.versionNotifier.addListener(_onGlobalUserChanged);

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _animController.addListener(() {
      if (mounted) setState(() {});
    });
    _inputAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _inputExpandAnimation = CurvedAnimation(
      parent: _inputAnimController,
      curve: Curves.easeInOut,
    );
    _inputAnimController.addListener(() {
      if (mounted) setState(() {});
    });
    _detailAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _detailScaleAnim = CurvedAnimation(
      parent: _detailAnimController,
      curve: Curves.easeOutBack,
    );
    _detailFadeAnim = CurvedAnimation(
      parent: _detailAnimController,
      curve: Curves.easeOut,
    );
    _fanSnapController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _fanSnapController.addListener(() {
      if (!mounted) return;
      setState(() {
        _fanOffset =
            _fanSnapStart +
            (_fanSnapTarget - _fanSnapStart) * _fanSnapController.value;
      });
    });

    _currentCharacter = widget.character;

    // ✅ 修复：使用 Future.microtask 确保异步初始化完成
    if (_currentCharacter == null) {
      Future.microtask(() async {
        String? lastId;
        try {
          lastId = await DatabaseService.getLastActiveCharacterId();
        } catch (_) {}
        final all = await DatabaseService.getAllCharacters();
        Map<String, dynamic>? charData;
        if (lastId != null) {
          charData = all.cast<Map<String, dynamic>?>().firstWhere(
            (c) => c?['id'] == lastId,
            orElse: () => null,
          );
        }
        charData ??= all.isNotEmpty ? all.first : null;
        if (charData != null) {
          final newChar = CharacterCard(
            id: charData['id'] as String,
            name: charData['name'] as String,
            avatar: charData['avatar'] as String? ?? '',
            cardImagePath: charData['card_image_path'] as String? ?? '',
            description: charData['description'] as String? ?? '',
            systemPrompt: charData['system_prompt'] as String? ?? '',
            userName: charData['user_name'] as String? ?? '',
            userAvatar: charData['user_avatar'] as String? ?? '',
            userDetailSetting: charData['user_detail_setting'] as String? ?? '',
            cardType: charData['card_type'] as String? ?? 'character',
            entriesJson: charData['entries_json'] as String? ?? '[]',
            openingGreetings: charData['opening_greetings'] as String? ?? '[]',
          );
          await _setCurrentCharacter(newChar);
        }
      });
    } else {
      Future.microtask(() async {
        await _setCurrentCharacter(widget.character);
      });
    }
  }

  Future<void> _ensureOpeningGreetingForEmptyHistory() async {
    if (_currentCharacter == null) return;

    // 以数据库为准，避免 UI 状态误判
    final existingMessages =
    await DatabaseService.getMessages(_currentCharacter!.id);
    debugPrint('检查开场白: ${_currentCharacter?.openingGreetings}');
    debugPrint('当前历史数量: ${existingMessages.length}');
    // 只在完全没有历史消息时插入开场白
    if (existingMessages.isNotEmpty) return;

    final greetings = _getCurrentGreetings();
    if (greetings.isEmpty) return;

    final firstGreeting = greetings.first.content.trim();
    if (firstGreeting.isEmpty) return;

    final newId = await DatabaseService.insertMessage(
      characterId: _currentCharacter!.id,
      role: 'assistant',
      content: firstGreeting,
    );

    if (!mounted) return;

    setState(() {
      _messages.clear();
      _messages.add({
        'id': newId.toString(),
        'role': 'assistant',
        'content': firstGreeting,
        'version': 1,
      });
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottomWhenReady();
    });
  }

  Future<void> _setCurrentCharacter(CharacterCard? char) async {
    debugPrint('=== 加载角色卡 ===');
    debugPrint('opening_greetings: ${char?.openingGreetings}');
    debugPrint('entries_json: ${char?.entriesJson}');

    if (char == null) return;

    _currentCharacter = char;

    setState(() {
      _messages.clear();
    });

    // 先加载历史
    await _loadHistory();

    // 这里一定要 await。
    // 因为 _loadUser() 里会重新从数据库刷新 _currentCharacter，
    // 包括 openingGreetings、entriesJson 等最新字段。
    await _loadUser();

    // 如果没有历史记录，则自动插入开场白
    await _ensureOpeningGreetingForEmptyHistory();

    if (mounted) setState(() {});
  }

  Future<String> _buildFinalSystemPrompt() async {
    String systemPrompt = _currentCharacter?.systemPrompt ?? '你是忠于用户的助手。';

    // 注入世界书设定
    if (_currentCharacter?.worldBookId != null &&
        _currentCharacter!.worldBookId.isNotEmpty) {
      if (_cachedWorldBookId != _currentCharacter!.worldBookId) {
        final worldBooks = await DatabaseService.getAllWorldBooks();
        final worldBook = worldBooks.firstWhere(
          (wb) => wb['id'] == _currentCharacter!.worldBookId,
          orElse: () => <String, dynamic>{},
        );
        if (worldBook.isNotEmpty) {
          final entriesJson = worldBook['entries_json'] as String? ?? '[]';
          try {
            final list = jsonDecode(entriesJson) as List;
            _cacheWorldBookEntries(
              list.map((e) => WorldBookEntry.fromJson(e)).toList(),
            );
          } catch (_) {
            _cacheWorldBookEntries([]);
          }
        }
      }

      final activeEntries = _getActiveWorldBookEntries(4);
      if (activeEntries.isNotEmpty) {
        final entryText = activeEntries
            .map((e) => '【${e.title}】\n${e.content}')
            .join('\n\n');
        systemPrompt += '\n\n[世界设定]\n$entryText';
      }
    }

    // 注入用户详细设定
    if (_dynamicUserDetail != null && _dynamicUserDetail!.isNotEmpty) {
      systemPrompt += '\n\n[用户详细设定]\n$_dynamicUserDetail';
    }

    // 注入用户名称
    if (_currentUser.name.isNotEmpty && _currentUser.name != '我') {
      systemPrompt += '\n\n[当前用户名称]\n${_currentUser.name}';
    }

    // 注入角色卡条目
    if (_currentCharacter != null) {
      try {
        final entriesList =
            jsonDecode(
                  _currentCharacter!.entriesJson.isEmpty
                      ? '[]'
                      : _currentCharacter!.entriesJson,
                )
                as List;
        final enabledEntries = entriesList
            .map((e) => CharacterEntry.fromJson(e))
            .where((e) {
          if (!e.enabled || e.content.isEmpty) return false;

          // 系统卡的主角设定已经作为用户设定注入，避免重复塞进角色设定
          if (_currentCharacter?.cardType == 'system' && e.id == 'protagonist') {
            return false;
          }

          return true;
        })
            .toList();
        if (enabledEntries.isNotEmpty) {
          final entryText = enabledEntries
              .map((e) => '【${e.title}】\n${e.content}')
              .join('\n\n');
          systemPrompt += '\n\n[角色设定]\n$entryText';
        }
      } catch (_) {}
    }

    return systemPrompt;
  }

  Future<BackgroundCard?> _getCurrentBackground() async {
    // 优先使用当前角色的独立背景
    if (_currentCharacter?.backgroundId != null &&
        _currentCharacter!.backgroundId.isNotEmpty) {
      final all = await BackgroundService.getAll();
      return all.firstWhere(
        (b) => b.id == _currentCharacter!.backgroundId,
        orElse: () => BackgroundCard(id: '', name: '', type: ''),
      );
    }
    // 否则使用全局背景
    return BackgroundService.getCurrent();
  }

  @override
  void dispose() {
    UserService.versionNotifier.removeListener(_onGlobalUserChanged);
    _scrollController.dispose();
    _inputAnimController.dispose();
    _animController.dispose();
    _msgController.dispose();
    _detailAnimController.dispose();
    _inertiaTicker?.stop();
    _inertiaTicker?.dispose();
    _fanSnapController.dispose();
    super.dispose();

  }

  Future<Map<String, bool>?> _showClearHistoryDialog() {
    bool resetUserSetting = false;

    return showDialog<Map<String, bool>>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('清空历史'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('确定要清空当前角色的聊天记录吗？'),
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    value: resetUserSetting,
                    onChanged: (v) {
                      setDialogState(() {
                        resetUserSetting = v ?? false;
                      });
                    },
                    title: const Text('同时重置用户设定为角色卡默认'),
                    subtitle: const Text(
                      '勾选后会清空当前卡的用户覆盖设定，重新使用角色卡中的主角设定。',
                      style: TextStyle(fontSize: 12),
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('取消'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, {
                    'clear': true,
                    'resetUserSetting': resetUserSetting,
                  }),
                  child: const Text('清空'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _clearHistoryWithOptions() async {
    if (_currentCharacter == null) return;

    final result = await _showClearHistoryDialog();
    if (result == null || result['clear'] != true) return;

    final resetUserSetting = result['resetUserSetting'] == true;

    await DatabaseService.deleteMessagesByCharacterId(_currentCharacter!.id);

    if (resetUserSetting) {
      await DatabaseService.updateCharacter({
        'id': _currentCharacter!.id,
        'user_name': '',
        'user_avatar': '',
        'user_detail_setting': '',
      });

      _currentCharacter!.userName = '';
      _currentCharacter!.userAvatar = '';
      _currentCharacter!.userDetailSetting = '';

      await _loadUser();
    }

    setState(() {
      _messages.clear();
    });

    await _ensureOpeningGreetingForEmptyHistory();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final panelW = panelWidth;

    return MediaQuery.removePadding(
        context: context,
        removeTop: true,        // ✅ 强制抹掉 Flutter 引擎留出的顶部 inset
        child: Scaffold(
          primary: false,
          backgroundColor: Colors.transparent,
          body: SafeArea(
            top: false, // 不保留顶部安全区
            bottom: false,
            maintainBottomViewPadding: true,
            child: GestureDetector(
              onHorizontalDragStart: _onHorizontalDragStart,
              onHorizontalDragUpdate: _onHorizontalDragUpdate,
              onHorizontalDragEnd: _onHorizontalDragEnd,
              child: Stack(
                children: [
                  // 背景图层（动态）
                  Positioned.fill(
                    child: ValueListenableBuilder<int>(
                      valueListenable: BackgroundService.versionNotifier,
                      builder: (context, version, _) {
                        // 每次版本变化都创建新的 future，强制刷新
                        return FutureBuilder<BackgroundCard?>(
                          future: _getCurrentBackground(),
                          builder: (context, snapshot) {
                            final bg = snapshot.data;
                            if (bg == null) {
                              return Container(
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [Color(0xFFE3F2FD), Color(0xFFF3E5F5)],
                                  ),
                                ),
                              );
                            }
                            return _buildBackground(bg);
                          },
                        );
                      },
                    ),
                  ),
                  // 聊天主体 + 右侧面板
                  Positioned(
                    left: -panelW * _animController.value,
                    top: 0,
                    bottom: 0,
                    width: screenWidth + panelW,
                    child: IgnorePointer(
                      ignoring: _showFanPanel,
                      child: Row(
                        children: [
                          IgnorePointer(
                            ignoring: _animController.value > 0.5,
                            child: SizedBox(
                              width: screenWidth,
                              child: Column(
                                children: [
                                  Expanded(
                                    child: ListView.builder(
                                      controller: _scrollController,
                                      padding: const EdgeInsets.only(
                                        top: 50,
                                        bottom: 70,
                                      ),
                                      itemCount:
                                      _messages.length + (_isLoading ? 1 : 0),
                                      itemBuilder: (ctx, index) {
                                        if (index < _messages.length) {
                                          final msg = _messages[index];
                                          final isMe = msg['role'] == 'user';
                                          return Padding(
                                            padding: EdgeInsets.only(
                                              top: 4,
                                              bottom: _isLastMessage(index) ? 0 : 4,
                                              left: 8,
                                              right: 8,
                                            ),
                                            child: Row(
                                              crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                              mainAxisAlignment: isMe
                                                  ? MainAxisAlignment.end
                                                  : MainAxisAlignment.start,
                                              children: [
                                                if (!isMe) ...[
                                                  Column(
                                                    crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      // 头像 + 气泡
                                                      Row(
                                                        crossAxisAlignment:
                                                        CrossAxisAlignment.end,
                                                        children: [
                                                          Padding(
                                                            padding:
                                                            const EdgeInsets.only(
                                                              right: 6,
                                                            ),
                                                            child: CircleAvatar(
                                                              radius: 14,
                                                              backgroundColor:
                                                              _currentCharacter
                                                                  ?.avatar !=
                                                                  null &&
                                                                  _currentCharacter!
                                                                      .avatar
                                                                      .isNotEmpty &&
                                                                  File(
                                                                    _currentCharacter!
                                                                        .avatar,
                                                                  ).existsSync()
                                                                  ? null
                                                                  : Colors
                                                                  .grey
                                                                  .shade300,
                                                              backgroundImage:
                                                              _currentCharacter
                                                                  ?.avatar !=
                                                                  null &&
                                                                  _currentCharacter!
                                                                      .avatar
                                                                      .isNotEmpty &&
                                                                  File(
                                                                    _currentCharacter!
                                                                        .avatar,
                                                                  ).existsSync()
                                                                  ? FileImage(
                                                                File(
                                                                  _currentCharacter!
                                                                      .avatar,
                                                                ),
                                                              )
                                                                  : null,
                                                              child:
                                                              _currentCharacter
                                                                  ?.avatar ==
                                                                  null ||
                                                                  _currentCharacter!
                                                                      .avatar
                                                                      .isEmpty ||
                                                                  !File(
                                                                    _currentCharacter!
                                                                        .avatar,
                                                                  ).existsSync()
                                                                  ? Icon(
                                                                Icons.person,
                                                                size: 18,
                                                                color: Colors
                                                                    .grey
                                                                    .shade600,
                                                              )
                                                                  : null,
                                                            ),
                                                          ),
                                                          Container(
                                                            constraints: BoxConstraints(
                                                              maxWidth:
                                                              MediaQuery.of(
                                                                context,
                                                              ).size.width *
                                                                  0.7 -
                                                                  20,
                                                            ),
                                                            padding:
                                                            const EdgeInsets.all(
                                                              10,
                                                            ),
                                                            decoration: BoxDecoration(
                                                              color: Colors
                                                                  .grey
                                                                  .shade200,
                                                              borderRadius: const BorderRadius.only(
                                                                topLeft:
                                                                Radius.circular(
                                                                  12,
                                                                ),
                                                                topRight:
                                                                Radius.circular(
                                                                  12,
                                                                ),
                                                                bottomRight:
                                                                Radius.circular(
                                                                  12,
                                                                ),
                                                                bottomLeft:
                                                                Radius.circular(
                                                                  4,
                                                                ),
                                                              ),
                                                            ),
                                                            child:
                                                            _buildMarkdownWidget(
                                                              msg['content']!,
                                                            ),
                                                          ),
                                                        ],
                                                      ),

                                                      // 功能图标行（仅最新 AI 消息显示）
                                                      if (_isLatestAiMessage(index))
                                                        SizedBox(
                                                          height: 29,
                                                          child: Padding(
                                                            padding:
                                                            const EdgeInsets.only(
                                                              left: 34,
                                                            ),
                                                            child: Row(
                                                              mainAxisSize:
                                                              MainAxisSize.min,
                                                              children: [
                                                                IconButton(
                                                                  icon: const Icon(
                                                                    Icons.refresh,
                                                                    size: 14,
                                                                    color:
                                                                    Colors.grey,
                                                                  ),
                                                                  onPressed: () =>
                                                                      _regenerateMessage(
                                                                        index,
                                                                      ),
                                                                  constraints:
                                                                  const BoxConstraints(
                                                                    minWidth:
                                                                    24,
                                                                    minHeight:
                                                                    24,
                                                                  ),
                                                                  padding:
                                                                  EdgeInsets
                                                                      .zero,
                                                                  splashRadius: 12,
                                                                ),
                                                                const SizedBox(
                                                                  width: 2,
                                                                ),
                                                                IconButton(
                                                                  icon: const Icon(
                                                                    Icons
                                                                        .more_horiz,
                                                                    size: 14,
                                                                    color:
                                                                    Colors.grey,
                                                                  ),
                                                                  onPressed: () =>
                                                                      _continueMessage(
                                                                        index,
                                                                      ),
                                                                  constraints:
                                                                  const BoxConstraints(
                                                                    minWidth:
                                                                    24,
                                                                    minHeight:
                                                                    24,
                                                                  ),
                                                                  padding:
                                                                  EdgeInsets
                                                                      .zero,
                                                                  splashRadius: 12,
                                                                ),
                                                                // 开场白切换（如果该消息是开场白）
                                                                if (_isGreetingMessage(
                                                                  msg,
                                                                ))
                                                                  Builder(
                                                                    builder: (context) {
                                                                      final greetings =
                                                                      _getCurrentGreetings();
                                                                      final currentContent =
                                                                      msg['content']
                                                                      as String;
                                                                      int
                                                                      cur = greetings
                                                                          .indexWhere(
                                                                            (g) =>
                                                                        g.content ==
                                                                            currentContent,
                                                                      );
                                                                      if (cur == -1) {
                                                                        cur = 0;
                                                                      }
                                                                      return Row(
                                                                        mainAxisSize:
                                                                        MainAxisSize
                                                                            .min,
                                                                        children: [
                                                                          const SizedBox(
                                                                            width:
                                                                            4,
                                                                          ),
                                                                          IconButton(
                                                                            icon: const Icon(
                                                                              Icons
                                                                                  .arrow_back_ios,
                                                                              size:
                                                                              10,
                                                                              color:
                                                                              Colors.grey,
                                                                            ),
                                                                            onPressed: () {
                                                                              if (cur >
                                                                                  0) {
                                                                                setState(() {
                                                                                  msg['content'] =
                                                                                      greetings[cur -
                                                                                          1]
                                                                                          .content;
                                                                                });
                                                                              }
                                                                            },
                                                                            constraints: const BoxConstraints(
                                                                              minWidth:
                                                                              20,
                                                                              minHeight:
                                                                              20,
                                                                            ),
                                                                            padding:
                                                                            EdgeInsets.zero,
                                                                            splashRadius:
                                                                            10,
                                                                          ),
                                                                          Text(
                                                                            '${cur + 1}/${greetings.length}',
                                                                            style: const TextStyle(
                                                                              fontSize:
                                                                              10,
                                                                              color:
                                                                              Colors.grey,
                                                                            ),
                                                                          ),
                                                                          IconButton(
                                                                            icon: const Icon(
                                                                              Icons
                                                                                  .arrow_forward_ios,
                                                                              size:
                                                                              10,
                                                                              color:
                                                                              Colors.grey,
                                                                            ),
                                                                            onPressed: () {
                                                                              if (cur <
                                                                                  greetings.length -
                                                                                      1) {
                                                                                setState(() {
                                                                                  msg['content'] =
                                                                                      greetings[cur +
                                                                                          1]
                                                                                          .content;
                                                                                });
                                                                              }
                                                                            },
                                                                            constraints: const BoxConstraints(
                                                                              minWidth:
                                                                              20,
                                                                              minHeight:
                                                                              20,
                                                                            ),
                                                                            padding:
                                                                            EdgeInsets.zero,
                                                                            splashRadius:
                                                                            10,
                                                                          ),
                                                                        ],
                                                                      );
                                                                    },
                                                                  )
                                                                else if (msg
                                                                    .containsKey(
                                                                  'versions',
                                                                ) &&
                                                                    (msg['versions']
                                                                    as List)
                                                                        .isNotEmpty)
                                                                  Builder(
                                                                    builder: (context) {
                                                                      final versions =
                                                                      List<
                                                                          String
                                                                      >.from(
                                                                        msg['versions']
                                                                        as List,
                                                                      );
                                                                      int cur =
                                                                          (msg['currentVersionIndex']
                                                                          as int?) ??
                                                                              0;
                                                                      return Row(
                                                                        mainAxisSize:
                                                                        MainAxisSize
                                                                            .min,
                                                                        children: [
                                                                          const SizedBox(
                                                                            width:
                                                                            8,
                                                                          ),
                                                                          IconButton(
                                                                            icon: const Icon(
                                                                              Icons
                                                                                  .arrow_back_ios,
                                                                              size:
                                                                              12,
                                                                              color:
                                                                              Colors.grey,
                                                                            ),
                                                                            onPressed: () {
                                                                              if (cur >
                                                                                  0) {
                                                                                setState(() {
                                                                                  msg['currentVersionIndex'] =
                                                                                      cur -
                                                                                          1;
                                                                                  msg['content'] =
                                                                                  versions[cur -
                                                                                      1];
                                                                                  final versionIds =
                                                                                  List<
                                                                                      String
                                                                                  >.from(
                                                                                    msg['versionIds']
                                                                                    as List,
                                                                                  );
                                                                                  msg['id'] =
                                                                                  versionIds[cur -
                                                                                      1];
                                                                                });
                                                                              }
                                                                            },
                                                                            constraints: const BoxConstraints(
                                                                              minWidth:
                                                                              24,
                                                                              minHeight:
                                                                              24,
                                                                            ),
                                                                            padding:
                                                                            EdgeInsets.zero,
                                                                            splashRadius:
                                                                            12,
                                                                          ),
                                                                          Text(
                                                                            '${cur + 1}/${versions.length}',
                                                                            style: const TextStyle(
                                                                              fontSize:
                                                                              11,
                                                                              color:
                                                                              Colors.grey,
                                                                            ),
                                                                          ),
                                                                          IconButton(
                                                                            icon: const Icon(
                                                                              Icons
                                                                                  .arrow_forward_ios,
                                                                              size:
                                                                              12,
                                                                              color:
                                                                              Colors.grey,
                                                                            ),
                                                                            onPressed: () {
                                                                              if (cur <
                                                                                  versions.length -
                                                                                      1) {
                                                                                setState(() {
                                                                                  msg['currentVersionIndex'] =
                                                                                      cur +
                                                                                          1;
                                                                                  msg['content'] =
                                                                                  versions[cur +
                                                                                      1];
                                                                                  final versionIds =
                                                                                  List<
                                                                                      String
                                                                                  >.from(
                                                                                    msg['versionIds']
                                                                                    as List,
                                                                                  );
                                                                                  msg['id'] =
                                                                                  versionIds[cur +
                                                                                      1];
                                                                                });
                                                                              }
                                                                            },
                                                                            constraints: const BoxConstraints(
                                                                              minWidth:
                                                                              24,
                                                                              minHeight:
                                                                              24,
                                                                            ),
                                                                            padding:
                                                                            EdgeInsets.zero,
                                                                            splashRadius:
                                                                            12,
                                                                          ),
                                                                        ],
                                                                      );
                                                                    },
                                                                  ),
                                                              ],
                                                            ),
                                                          ),
                                                        ),
                                                    ],
                                                  ),
                                                ],
                                                if (isMe) ...[
                                                  Stack(
                                                    clipBehavior: Clip.none,
                                                    alignment:
                                                    Alignment.bottomRight,
                                                    children: [
                                                      // 气泡 + 头像
                                                      Padding(
                                                        padding:
                                                        const EdgeInsets.only(
                                                          bottom: 40,
                                                        ),
                                                        child: Row(
                                                          crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .end,
                                                          mainAxisAlignment:
                                                          MainAxisAlignment.end,
                                                          children: [
                                                            GestureDetector(
                                                              onTap: () =>
                                                                  _startEdit(index),
                                                              behavior:
                                                              HitTestBehavior
                                                                  .opaque,
                                                              // 确保整个区域可点击
                                                              child: Container(
                                                                constraints: BoxConstraints(
                                                                  maxWidth:
                                                                  MediaQuery.of(
                                                                    context,
                                                                  ).size.width *
                                                                      0.7 -
                                                                      20,
                                                                ),
                                                                padding:
                                                                const EdgeInsets.all(
                                                                  10,
                                                                ),
                                                                decoration: BoxDecoration(
                                                                  color:
                                                                  _editingIndex ==
                                                                      index
                                                                      ? Colors
                                                                      .green
                                                                      .shade200
                                                                      : Colors
                                                                      .green
                                                                      .shade100,
                                                                  borderRadius: const BorderRadius.only(
                                                                    topLeft:
                                                                    Radius.circular(
                                                                      12,
                                                                    ),
                                                                    topRight:
                                                                    Radius.circular(
                                                                      12,
                                                                    ),
                                                                    bottomLeft:
                                                                    Radius.circular(
                                                                      12,
                                                                    ),
                                                                    bottomRight:
                                                                    Radius.circular(
                                                                      4,
                                                                    ),
                                                                  ),
                                                                ),
                                                                child: MarkdownBody(
                                                                  data:
                                                                  msg['content']!,
                                                                  selectable: false,
                                                                  // 用户消息不可选，避免阻挡点击
                                                                  extensionSet: md
                                                                      .ExtensionSet
                                                                      .gitHubFlavored,
                                                                  onTapLink: (text, href, title) {
                                                                    if (href !=
                                                                        null &&
                                                                        href.startsWith(
                                                                          'action://',
                                                                        )) {
                                                                      final action =
                                                                      href.substring(
                                                                        'action://'
                                                                            .length,
                                                                      );
                                                                      _handleMarkdownAction(
                                                                        action,
                                                                      );
                                                                    }
                                                                  },
                                                                ),
                                                              ),
                                                            ),
                                                            Padding(
                                                              padding:
                                                              const EdgeInsets.only(
                                                                left: 6,
                                                              ),
                                                              child: CircleAvatar(
                                                                radius: 14,
                                                                backgroundColor:
                                                                Colors
                                                                    .grey
                                                                    .shade300,
                                                                backgroundImage:
                                                                _currentUser
                                                                    .avatarPath
                                                                    .isNotEmpty &&
                                                                    File(
                                                                      _currentUser
                                                                          .avatarPath,
                                                                    ).existsSync()
                                                                    ? FileImage(
                                                                  File(
                                                                    _currentUser
                                                                        .avatarPath,
                                                                  ),
                                                                )
                                                                    : null,
                                                                child:
                                                                _currentUser
                                                                    .avatarPath
                                                                    .isEmpty ||
                                                                    !File(
                                                                      _currentUser
                                                                          .avatarPath,
                                                                    ).existsSync()
                                                                    ? Icon(
                                                                  Icons
                                                                      .person,
                                                                  size: 18,
                                                                  color: Colors
                                                                      .grey
                                                                      .shade600,
                                                                )
                                                                    : null,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                      // 功能图标：放在气泡底部外侧，紧贴但不遮挡
                                                      if (_editingIndex != index &&
                                                          _isLatestUserMessage(
                                                            index,
                                                          ))
                                                        Positioned(
                                                          right: 40,
                                                          bottom: 17,
                                                          width: 20,
                                                          height: 20,
                                                          child: Container(
                                                            width: 20, // 限制点击区域
                                                            height: 20,
                                                            alignment:
                                                            Alignment.center,
                                                            child: IconButton(
                                                              icon: const Icon(
                                                                Icons.shortcut,
                                                                size: 14,
                                                                color: Colors.grey,
                                                              ),
                                                              onPressed: () =>
                                                                  _deleteUserMessage(
                                                                    index,
                                                                  ),
                                                              constraints:
                                                              const BoxConstraints(
                                                                minWidth: 20,
                                                                minHeight: 20,
                                                              ),
                                                              padding:
                                                              EdgeInsets.zero,
                                                              splashRadius: 10,
                                                            ),
                                                          ),
                                                        ),
                                                    ],
                                                  ),
                                                ],
                                              ],
                                            ),
                                          );
                                        } else {
                                          return const Align(
                                            alignment: Alignment.centerLeft,
                                            child: Padding(
                                              padding: EdgeInsets.all(12),
                                              child: Text('...'),
                                            ),
                                          );
                                        }
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          // 右侧设置面板
                          SizedBox(
                            width: panelW,
                            child: Container(
                              color: Theme.of(context).scaffoldBackgroundColor,
                              child: Column(
                                children: [
                                  AppBar(
                                    title: const Text('聊天设置'),
                                    automaticallyImplyLeading: false,
                                  ),
                                  Expanded(
                                    child: ListView(
                                      children: [
                                        ListTile(
                                          leading: const Icon(Icons.person),
                                          title: const Text('用户设定'),
                                          onTap: () {
                                            if (_currentCharacter == null) return;
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    RoleUserSettingsPage(
                                                      character: _currentCharacter!,
                                                    ),
                                              ),
                                            ).then((_) => _loadUser()); // 返回后刷新
                                          },
                                        ),
                                        ListTile(
                                          leading: const Icon(Icons.image),
                                          title: const Text('背景设置'),
                                          onTap: () {
                                            Navigator.push(
                                              context,
                                              PageRouteBuilder(
                                                opaque: false,
                                                // 透明路由
                                                transitionDuration: Duration.zero,
                                                // 无过渡动画（由内部自己做动画）
                                                pageBuilder: (_, _, _) =>
                                                    BackgroundPickerSheet(
                                                      character: _currentCharacter,
                                                    ),
                                              ),
                                            ).then((_) => setState(() {}));
                                          },
                                        ),
                                        ListTile(
                                          leading: const Icon(Icons.clear_all),
                                          title: const Text('清空历史'),
                                          onTap: _clearHistoryWithOptions,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  //扇形面板
                  if (_showFanPanel)
                    Positioned.fill(
                      child: Stack(
                        children: [
                          // 轮盘层（不显示详情时可交互）
                          if (!_showCardDetail)
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => setState(() => _showFanPanel = false),
                              onHorizontalDragUpdate: (details) {
                                _inertiaTicker?.stop();
                                _inertiaTicker?.dispose();
                                _inertiaTicker = null;
                                _fanSnapController.stop();
                                final maxOff =
                                    _halfArcLen + (_cardCount - 1) / 2.0 * _cardDs;
                                setState(() {
                                  // 向右拖(delta.dx>0) → fanOffset减少 → 弧长减小 → 卡片向右移
                                  _fanOffset += details.delta.dx;
                                  _fanOffset = _fanOffset.clamp(-maxOff, maxOff);
                                });
                              },
                              onHorizontalDragEnd: (details) {
                                _startInertia(details.velocity.pixelsPerSecond.dx);
                              },
                              child: Container(
                                color: Colors.black54,
                                child: _buildFanCards(),
                              ),
                            ),
                          // 详情弹窗层
                          if (_showCardDetail && _detailCard != null)
                            _buildCardDetailOverlay(_detailCard!),
                        ],
                      ),
                    ),

                  // 3. 状态栏
                  Positioned(
                    top: 8,
                    left: 16,
                    right: 16,
                    child: IgnorePointer(
                      ignoring: _showFanPanel || _animController.value > 0.5,
                      child: Opacity(
                        opacity: (_showFanPanel || _showCardDetail)
                            ? 0.0
                            : (1.0 - _animController.value),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                            child: Container(
                              height: 36,
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                color: Colors.white.withAlpha(60),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () {
                                  showDialog(
                                    context: context,
                                    builder: (_) => AlertDialog(
                                      title: const Text('状态设置（待实现）'),
                                      content: const Text('未来版本将在此设置好感度、心情等状态。'),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(context),
                                          child: const Text('确定'),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      '❤️ 好感度',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.black87,
                                      ),
                                    ),
                                    const Text(
                                      '12:00',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.black87,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // 5. 角色名（悬浮，居中）
                  Positioned(
                    top: MediaQuery.of(context).padding.top + 28 + 10,
                    left: 60,
                    right: 60,
                    child: IgnorePointer(
                      ignoring: _showFanPanel || _animController.value > 0.5,
                      child: Opacity(
                        opacity: (_showFanPanel || _showCardDetail)
                            ? 0.0
                            : (1.0 - _animController.value),
                        child: Center(
                          child: GestureDetector(
                            onTap: () {
                              if (!_showFanPanel) {
                                _loadSelectableCharacters();
                              }
                              setState(() => _showFanPanel = !_showFanPanel);
                            },
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: BackdropFilter(
                                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withAlpha(80),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    _currentCharacter?.name ?? '聊天',
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // 悬浮毛玻璃输入栏（最上层）
                  if (_animController.value < 0.1 && !_showFanPanel)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: IgnorePointer(
                        ignoring: _showFanPanel,
                        child: Padding(
                          padding: EdgeInsets.only(
                            bottom: MediaQuery.of(context).padding.bottom,
                          ),
                          child: SizedBox(
                            width: double.infinity,
                            height: 42 + 16 + 20,
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                if (_inputExpanded)
                                  Positioned(
                                    left: 16,
                                    top: -5,
                                    child: Text(
                                      'Tokens: ${_estimateTokens()}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade500,
                                      ),
                                    ),
                                  ),
                                AnimatedBuilder(
                                  animation: _inputAnimController,
                                  builder: (context, child) {
                                    final animValue = _inputExpandAnimation.value;
                                    final screenWidth = MediaQuery.of(
                                      context,
                                    ).size.width;
                                    const buttonSize = 36.0;
                                    const padding = 12.0;
                                    final buttonLeft =
                                        padding +
                                            (screenWidth - padding * 2 - buttonSize) *
                                                animValue;
                                    final inputWidth =
                                        (screenWidth -
                                            padding * 2 -
                                            buttonSize -
                                            8) *
                                            animValue;

                                    return Stack(
                                      children: [
                                        if (animValue > 0.0)
                                          Positioned(
                                            left: padding,
                                            top: 16,
                                            width: inputWidth,
                                            height: 42,
                                            child: Opacity(
                                              opacity: animValue,
                                              child: ClipRRect(
                                                borderRadius: BorderRadius.circular(
                                                  28,
                                                ),
                                                child: BackdropFilter(
                                                  filter: ImageFilter.blur(
                                                    sigmaX: 20,
                                                    sigmaY: 20,
                                                  ),
                                                  child: Container(
                                                    decoration: BoxDecoration(
                                                      color: Colors.white.withAlpha(
                                                        80,
                                                      ),
                                                      borderRadius:
                                                      BorderRadius.circular(28),
                                                      boxShadow: [
                                                        BoxShadow(
                                                          color: Colors.black12,
                                                          blurRadius: 12,
                                                          offset: const Offset(
                                                            0,
                                                            4,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    child: Row(
                                                      children: [
                                                        if (animValue > 0.3)
                                                          IconButton(
                                                            icon: const Icon(
                                                              Icons.add_outlined,
                                                              color: Colors.grey,
                                                            ),
                                                            onPressed: () =>
                                                                _showExtensionMenu(
                                                                  context,
                                                                ),
                                                            padding:
                                                            EdgeInsets.zero,
                                                            constraints:
                                                            const BoxConstraints(
                                                              minWidth: 32,
                                                              minHeight: 32,
                                                            ),
                                                          ),
                                                        if (animValue > 0.3)
                                                          Flexible(
                                                            child: TextField(
                                                              controller:
                                                              _msgController,
                                                              style:
                                                              const TextStyle(
                                                                fontSize: 15,
                                                              ),
                                                              decoration: const InputDecoration(
                                                                hintText: '输入消息...',
                                                                hintStyle:
                                                                TextStyle(
                                                                  color: Colors
                                                                      .grey,
                                                                ),
                                                                border: InputBorder
                                                                    .none,
                                                                contentPadding:
                                                                EdgeInsets.symmetric(
                                                                  horizontal: 8,
                                                                  vertical: 10,
                                                                ),
                                                              ),
                                                              onChanged: (text) {
                                                                if (_editingIndex !=
                                                                    -1) {
                                                                  setState(() {
                                                                    _messages[_editingIndex]['content'] =
                                                                        text;
                                                                  });
                                                                }
                                                              },
                                                              onSubmitted: (_) =>
                                                                  _sendMessage(),
                                                            ),
                                                          ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        Positioned(
                                          left: buttonLeft,
                                          top: 16,
                                          child: GestureDetector(
                                            onTap: () {
                                              if (!_inputExpanded) {
                                                _inputAnimController.forward();
                                                setState(
                                                      () => _inputExpanded = true,
                                                );
                                              } else {
                                                if (_msgController.text
                                                    .trim()
                                                    .isEmpty) {
                                                  _inputAnimController.reverse();
                                                  setState(
                                                        () => _inputExpanded = false,
                                                  );
                                                } else {
                                                  _sendMessage();
                                                }
                                              }
                                            },
                                            child: ClipOval(
                                              child: BackdropFilter(
                                                filter: ImageFilter.blur(
                                                  sigmaX: 15,
                                                  sigmaY: 15,
                                                ),
                                                child: Container(
                                                  width: buttonSize,
                                                  height: buttonSize,
                                                  decoration: BoxDecoration(
                                                    color: Theme.of(
                                                      context,
                                                    ).primaryColor.withAlpha(220),
                                                    shape: BoxShape.circle,
                                                  ),
                                                  child: Icon(
                                                    !_inputExpanded
                                                        ? Icons.arrow_right_alt
                                                        : _editingIndex != -1
                                                        ? Icons.check
                                                        : Icons.arrow_right_alt,
                                                    color: Colors.white,
                                                    size: 16,
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
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
    );
  }

  void _startEdit(int index) {
    if (_editingIndex == index) {
      _cancelEdit();
      return;
    }
    if (_editingIndex != -1) {
      _cancelEdit();
    }
    setState(() {
      _editingIndex = index;
      _editingOriginalContent = _messages[index]['content'] as String;
      _msgController.text = _editingOriginalContent;
    });
    if (!_inputExpanded) {
      _inputAnimController.forward();
      setState(() => _inputExpanded = true);
    }
  }

  void _cancelEdit() {
    if (_editingIndex == -1) return;
    setState(() {
      _messages[_editingIndex]['content'] = _editingOriginalContent;
      _msgController.clear();
      _editingIndex = -1;
      _editingOriginalContent = '';
    });
  }

  void _showExtensionMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 24,
              runSpacing: 16,
              children: [
                _buildExtensionItem(
                  icon: Icons.image,
                  label: '图片',
                  onTap: () {
                    Navigator.pop(ctx);
                    // TODO: 接入图片生成/上传
                  },
                ),
                _buildExtensionItem(
                  icon: Icons.mic,
                  label: '语音',
                  onTap: () {
                    Navigator.pop(ctx);
                    // TODO: 接入语音输入
                  },
                ),
                _buildExtensionItem(
                  icon: Icons.camera_alt,
                  label: '拍照',
                  onTap: () {
                    Navigator.pop(ctx);
                    // TODO: 接入拍照功能
                  },
                ),
                _buildExtensionItem(
                  icon: Icons.emoji_emotions,
                  label: '表情',
                  onTap: () {
                    Navigator.pop(ctx);
                    // TODO: 接入表情/贴图
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _openPanel() {
    if (_editingIndex != -1) _cancelEdit(); // ← 新增这一行
    _animController.animateTo(1.0, curve: Curves.easeOut);
  }

  void _closePanel() => _animController.animateTo(0.0, curve: Curves.easeOut);

  void _onHorizontalDragStart(DragStartDetails details) {
    _dragStartOffset = details.globalPosition.dx;
    _panelStartValue = _animController.value;
    _animController.stop();
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    final dx = details.globalPosition.dx - _dragStartOffset;
    final totalMove = panelWidth;
    double newValue = (_panelStartValue - dx / totalMove).clamp(0.0, 1.0);
    _animController.value = newValue;
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    if (details.primaryVelocity != null && details.primaryVelocity! < -300) {
      _openPanel();
    } else if (details.primaryVelocity != null &&
        details.primaryVelocity! > 300) {
      _closePanel();
    } else if (_animController.value > 0.3) {
      _openPanel();
    } else {
      _closePanel();
    }
  }

  Widget _buildMarkdownWidget(String text) {
    return MarkdownBody(
      data: text,
      selectable: true,
      extensionSet: md.ExtensionSet.gitHubFlavored,
      onTapLink: (text, href, title) {
        if (href != null && href.startsWith('action://')) {
          final action = href.substring('action://'.length);
          _handleMarkdownAction(action);
        }
      },
    );
  }

  List<OpeningGreeting> _getCurrentGreetings() {
    if (_currentCharacter == null) return [];
    try {
      final list =
          jsonDecode(
                _currentCharacter!.openingGreetings.isEmpty
                    ? '[]'
                    : _currentCharacter!.openingGreetings,
              )
              as List;
      return list.map((e) => OpeningGreeting.fromJson(e)).toList();
    } catch (_) {
      return [];
    }
  }

  bool _isGreetingMessage(Map<String, dynamic> msg) {
    if (msg['role'] != 'assistant') return false;
    final content = msg['content'] as String? ?? '';
    if (content.isEmpty) return false;
    final greetings = _getCurrentGreetings();
    return greetings.any((g) => g.content == content);
  }

  /// 处理 Markdown 中 action:// 开头的动作
  void _handleMarkdownAction(String action) {
    switch (action) {
      case 'retry':
        // 重试最后一次 AI 回复（对应你的重新生成逻辑）
        final lastAiIndex = _messages.lastIndexWhere(
          (m) => m['role'] == 'assistant',
        );
        if (lastAiIndex != -1) {
          _regenerateMessage(lastAiIndex);
        }
        break;
      case 'continue':
        final lastAiIndex = _messages.lastIndexWhere(
          (m) => m['role'] == 'assistant',
        );
        if (lastAiIndex != -1) {
          _continueMessage(lastAiIndex);
        }
        break;
      // 后续可扩展更多动作
      default:
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('未知动作: $action')));
    }
  }

  Future<void> _scrollToBottom({bool animated = true}) async {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final double target = position.maxScrollExtent;

    if (animated) {
      await _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    } else {
      _scrollController.jumpTo(target);
    }

    await Future.delayed(const Duration(milliseconds: 50));
    if (_scrollController.hasClients) {
      final double stableMax = _scrollController.position.maxScrollExtent;
      if ((stableMax - target).abs() > 1.0) {
        _scrollController.jumpTo(stableMax);
      }
    }
  }

  Future<void> _switchCharacter(CharacterCard newChar) async {
    if (_currentCharacter?.id == newChar.id) return;
    await _setCurrentCharacter(newChar);
    setState(() {}); // 触发背景刷新
  }

  Future<void> _saveEdit() async {
    if (_editingIndex == -1) return;
    final newText = _msgController.text.trim();
    if (newText.isEmpty) return;
    if (newText == _editingOriginalContent) {
      _cancelEdit();
      return;
    }

    final userIndex = _editingIndex;

    // 收集从 userIndex 到列表末尾的所有消息索引（整个尾部）
    final List<int> indicesToRemove = List.generate(
      _messages.length - userIndex,
      (i) => userIndex + i,
    );

    // 收集这些消息的数据库 id
    final List<int> idsToDelete = [];
    for (final i in indicesToRemove) {
      final msg = _messages[i];
      if (msg.containsKey('versionIds')) {
        final versionIds = List<String>.from(msg['versionIds'] as List);
        for (final vid in versionIds) {
          final id = int.tryParse(vid);
          if (id != null) idsToDelete.add(id);
        }
      } else {
        final id = int.tryParse(msg['id'] ?? '');
        if (id != null) idsToDelete.add(id);
      }
    }

    // 从数据库删除
    for (final id in idsToDelete) {
      await DatabaseService.deleteMessage(id);
    }

    // 从 UI 删除尾部，再插入新用户消息
    setState(() {
      _messages.removeRange(userIndex, _messages.length);
      _messages.insert(userIndex, {'role': 'user', 'content': newText});
      _editingIndex = -1;
      _editingOriginalContent = '';
      _msgController.clear();
    });

    if (_currentCharacter != null) {
      await DatabaseService.insertMessage(
        characterId: _currentCharacter!.id,
        role: 'user',
        content: newText,
      );
    }
    _requestAiReply();
  }

  Future<void> _sendMessage() async {
    if (_editingIndex != -1) {
      _saveEdit();
      return;
    }
    final text = _msgController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _messages.add({'role': 'user', 'content': text});
      _msgController.clear();
      _isLoading = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });

    // ✅ 修复：使用 _currentCharacter 而不是 widget.character
    if (_currentCharacter != null) {
      await DatabaseService.insertMessage(
        characterId: _currentCharacter!.id,
        role: 'user',
        content: text,
      );
    }
    _requestAiReply();
  }

  Future<void> _requestAiReply() async {
    final config = await ApiConfigService.getActiveConfig();
    if (config == null || config.apiKey.isEmpty) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('请先配置 API')));
      }
      return;
    }
    final module = context.read<ChatModule>();

    // 构建请求消息列表（基于当前对话）
    final requestMessages = _messages
        .map(
          (m) => {
            'role': m['role'] as String,
            'content': m['content'] as String,
          },
        )
        .toList();

    String finalSystemPrompt = await _buildFinalSystemPrompt();
    if (_currentCharacter?.worldBookId != null &&
        _currentCharacter!.worldBookId.isNotEmpty) {
      // 延迟加载并缓存
      if (_cachedWorldBookId != _currentCharacter!.worldBookId) {
        final worldBooks = await DatabaseService.getAllWorldBooks();
        final worldBook = worldBooks.firstWhere(
          (wb) => wb['id'] == _currentCharacter!.worldBookId,
          orElse: () => <String, dynamic>{},
        );
        if (worldBook.isNotEmpty) {
          final entriesJson = worldBook['entries_json'] as String? ?? '[]';
          try {
            final list = jsonDecode(entriesJson) as List;
            _cacheWorldBookEntries(
              list.map((e) => WorldBookEntry.fromJson(e)).toList(),
            );
          } catch (_) {
            _cacheWorldBookEntries([]);
          }
        }
      }

      final activeEntries = _getActiveWorldBookEntries(4);
      if (activeEntries.isNotEmpty) {
        final entryText = activeEntries
            .map((e) => '【${e.title}】\n${e.content}')
            .join('\n\n');
        finalSystemPrompt += '\n\n[世界设定]\n$entryText';
      }
    }
    // 新增：注入用户详细设定
    if (_dynamicUserDetail != null && _dynamicUserDetail!.isNotEmpty) {
      finalSystemPrompt += '\n\n[用户详细设定]\n$_dynamicUserDetail';
    }
    // 注入用户名称（跳过默认值"我"，避免无效注入）
    if (_currentUser.name.isNotEmpty && _currentUser.name != '我') {
      finalSystemPrompt += '\n\n[当前用户名称]\n${_currentUser.name}';
    }
    // 注入角色卡条目
    if (_currentCharacter != null) {
      try {
        final entriesList =
            jsonDecode(
                  _currentCharacter!.entriesJson.isEmpty
                      ? '[]'
                      : _currentCharacter!.entriesJson,
                )
                as List;
        final enabledEntries = entriesList
            .map((e) => CharacterEntry.fromJson(e))
            .where((e) => e.enabled && e.content.isNotEmpty)
            .toList();
        if (enabledEntries.isNotEmpty) {
          final entryText = enabledEntries
              .map((e) => '【${e.title}】\n${e.content}')
              .join('\n\n');
          // 用条目构建角色画像，替代原有的简单 systemPrompt
          finalSystemPrompt = '$finalSystemPrompt\n\n[角色设定]\n$entryText';
        }
      } catch (_) {}
    }

    String aiResponseContent = '';
    setState(() => _isLoading = true);

    module
        .sendMessage(finalSystemPrompt, requestMessages)
        .listen(
          (chunk) {
            aiResponseContent += chunk;
            setState(() {});
          },
          onDone: () {
            setState(() {
              _messages.add({
                'role': 'assistant',
                'content': aiResponseContent,
              });
              _isLoading = false;
            });
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _scrollToBottom();
            });

            // ✅ 修复：使用 _currentCharacter
            if (_currentCharacter != null && aiResponseContent.isNotEmpty) {
              DatabaseService.insertMessage(
                characterId: _currentCharacter!.id,
                role: 'assistant',
                content: aiResponseContent,
              );
            }
          },
          onError: (e) {
            setState(() {
              _messages.add({'role': 'assistant', 'content': '错误: $e'});
              _isLoading = false;
            });
          },
        );
  }

  Future<void> _scrollToBottomWhenReady() async {
    await Future.delayed(const Duration(milliseconds: 100));
    if (mounted) {
      await _scrollToBottom(animated: false);
    }
  }

  Future<void> _loadHistory() async {
    if (_currentCharacter == null) return;
    final rawMessages = await DatabaseService.getMessages(
      _currentCharacter!.id,
    );
    final List<Map<String, dynamic>> processed = [];

    for (final m in rawMessages) {
      final role = m['role'] as String;
      final content = m['content'] as String;
      final id = m['id'].toString();
      final version = (m['version'] as int?) ?? 1;

      if (role == 'assistant' &&
          processed.isNotEmpty &&
          processed.last['role'] == 'assistant') {
        final last = processed.last;
        if (last['versions'] == null) {
          last['versions'] = <String>[last['content']];
          last['versionIds'] = <String>[last['id'].toString()];
          last['currentVersionIndex'] = 0;
        }
        (last['versions'] as List<String>).add(content);
        (last['versionIds'] as List<String>).add(id);
        last['content'] = content;
        last['id'] = id;
        last['currentVersionIndex'] =
            (last['versions'] as List<String>).length - 1;
      } else {
        processed.add({
          'id': id,
          'role': role,
          'content': content,
          'version': version,
        });
      }
    }

    setState(() {
      _messages.clear();
      _messages.addAll(processed.cast<Map<String, dynamic>>());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottomWhenReady();
    });
  }

  Future<void> _deleteUserMessage(int userIndex) async {
    if (userIndex < 0 || userIndex >= _messages.length) return;
    final userMsg = _messages[userIndex];
    if (userMsg['role'] != 'user') return;

    // 收集要删除的条目索引：从当前用户消息开始，直到下一个用户消息之前
    final List<int> indicesToRemove = [];
    for (int i = userIndex; i < _messages.length; i++) {
      final msg = _messages[i];
      if (msg['role'] == 'user' && i != userIndex) break;
      indicesToRemove.add(i);
    }

    // 收集要删除的数据库 id
    final List<int> idsToDelete = [];
    for (final i in indicesToRemove) {
      final msg = _messages[i];
      if (msg.containsKey('versionIds')) {
        final versionIds = List<String>.from(msg['versionIds'] as List);
        for (final vid in versionIds) {
          final id = int.tryParse(vid);
          if (id != null) idsToDelete.add(id);
        }
      } else {
        final id = int.tryParse(msg['id'] ?? '');
        if (id != null) idsToDelete.add(id);
      }
    }

    // 从数据库删除
    for (final id in idsToDelete) {
      await DatabaseService.deleteMessage(id);
    }

    // 从 UI 删除
    setState(() {
      _messages.removeRange(indicesToRemove.first, indicesToRemove.last + 1);
    });
  }

  Future<void> _regenerateMessage(int aiIndex) async {
    if (aiIndex <= 0 || aiIndex >= _messages.length) return;
    final prevMsg = _messages[aiIndex - 1];
    if (prevMsg['role'] != 'user') return;

    final oldAiMsg = _messages[aiIndex];
    int newVersion = 2;
    if (oldAiMsg.containsKey('versions')) {
      final versions = oldAiMsg['versions'] as List<String>;
      newVersion = versions.length + 1;
    }

    final module = context.read<ChatModule>();
    final systemPrompt = _currentCharacter?.systemPrompt ?? '你是忠于用户的助手。';

    final requestMessages = _messages
        .where((m) => m['role'] != null && m['role'] != 'assistant')
        .map(
          (m) => {
            'role': m['role'] as String,
            'content': m['content'] as String,
          },
        )
        .toList();

    String aiResponseContent = '';
    setState(() => _isLoading = true);

    module
        .sendMessage(systemPrompt, requestMessages)
        .listen(
          (chunk) {
            aiResponseContent += chunk;
            setState(() {});
          },
          onDone: () async {
            if (aiResponseContent.isEmpty) {
              setState(() => _isLoading = false);
              return;
            }
            // ✅ 修复：使用 _currentCharacter
            int? newMsgId;
            if (_currentCharacter != null) {
              newMsgId = await DatabaseService.insertMessage(
                characterId: _currentCharacter!.id,
                role: 'assistant',
                content: aiResponseContent,
                version: newVersion,
              );
            }
            setState(() {
              if (oldAiMsg['versions'] == null) {
                oldAiMsg['versions'] = <String>[oldAiMsg['content']];
                oldAiMsg['versionIds'] = <String>[oldAiMsg['id'].toString()];
              }
              (oldAiMsg['versions'] as List<String>).add(aiResponseContent);
              (oldAiMsg['versionIds'] as List<String>).add(
                newMsgId?.toString() ?? '',
              );
              oldAiMsg['content'] = aiResponseContent;
              oldAiMsg['id'] = newMsgId?.toString() ?? '';
              oldAiMsg['currentVersionIndex'] =
                  (oldAiMsg['versions'] as List<String>).length - 1;
              _isLoading = false;
            });
          },
          onError: (e) {
            setState(() {
              _isLoading = false;
            });
          },
        );
  }

  Future<void> _continueMessage(int aiIndex) async {
    if (aiIndex < 0 || aiIndex >= _messages.length) return;
    final aiMsg = _messages[aiIndex];
    final currentContent = aiMsg['content'] as String;
    final curIdStr = aiMsg['id'] as String?;
    final curId = curIdStr != null ? int.tryParse(curIdStr) : null;

    final module = context.read<ChatModule>();
    final systemPrompt = await _buildFinalSystemPrompt();

    final requestMessages = _messages
        .where((m) => m['role'] != null && m['role'] != 'assistant')
        .map(
          (m) => {
            'role': m['role'] as String,
            'content': m['content'] as String,
          },
        )
        .toList();
    requestMessages.add({'role': 'assistant', 'content': currentContent});
    requestMessages.add({'role': 'user', 'content': '请接着上面继续写，不要重复，直接续写'});

    String aiResponseContent = '';
    setState(() => _isLoading = true);

    module
        .sendMessage(systemPrompt, requestMessages)
        .listen(
          (chunk) {
            aiResponseContent += chunk;
            setState(() {});
          },
          onDone: () async {
            if (aiResponseContent.isEmpty) {
              setState(() => _isLoading = false);
              return;
            }
            final newFullContent = '$currentContent\n$aiResponseContent';
            if (curId != null) {
              await DatabaseService.updateMessageContent(curId, newFullContent);
            }
            setState(() {
              aiMsg['content'] = newFullContent;
              if (aiMsg['versions'] != null) {
                final versions = List<String>.from(aiMsg['versions'] as List);
                final curIdx = aiMsg['currentVersionIndex'] as int? ?? 0;
                if (curIdx >= 0 && curIdx < versions.length) {
                  versions[curIdx] = newFullContent;
                  aiMsg['versions'] = versions;
                }
              }
              _isLoading = false;
            });
          },
          onError: (e) {
            setState(() => _isLoading = false);
          },
        );
  }

  Widget _buildExtensionItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, size: 28, color: Colors.grey[700]),
          ),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

class _FanCard {
  final CharacterCard character;
  final double t;
  double _x = 0.0;
  double _y = 0.0;
  double _arcS = 0.0; // 弧长位置
  int _index = 0; // 在 _selectableCharacters 中的索引

  _FanCard({required this.character, required this.t});
}
