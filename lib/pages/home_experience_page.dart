import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/character_card.dart';
import '../services/active_character_store.dart';
import '../services/background_service.dart';
import '../services/database_service.dart';
import '../shared/theme/app_theme_manager.dart';
import '../shared/theme/app_theme_tokens.dart';
import '../shared/transition/home_transitions.dart';
import 'background_library_page.dart';
import 'character_library_page.dart';
import 'world_book_library_page.dart';
import 'ui_asset_gallery.dart';
import 'chat_page.dart';

/// A mobile-first experience home.
///
/// The page is intentionally a stage rather than a feature dashboard:
/// the current role is the primary entry point, while management modules stay
/// in the lower-right rail. The existing MainMenuPage continues to own the
/// top-level settings side-swipe and guide overlay.
class HomeExperiencePage extends StatefulWidget {
  const HomeExperiencePage({
    super.key,
    this.chatTileKey,
    this.characterTileKey,
    this.worldBookTileKey,
    this.backgroundTileKey,
    this.chatTextKey,
    this.characterTextKey,
    this.worldBookTextKey,
    this.backgroundTextKey,
  });

  final GlobalKey? chatTileKey;
  final GlobalKey? characterTileKey;
  final GlobalKey? worldBookTileKey;
  final GlobalKey? backgroundTileKey;
  final GlobalKey? chatTextKey;
  final GlobalKey? characterTextKey;
  final GlobalKey? worldBookTextKey;
  final GlobalKey? backgroundTextKey;

  @override
  State<HomeExperiencePage> createState() => _HomeExperiencePageState();
}

class _HomeExperiencePageState extends State<HomeExperiencePage>
    with TickerProviderStateMixin {

  // Entrance choreography timings, mapped from the HTML prototype.
  // 入场错峰：Brand 先行 → Theme → Role → Stage → Rail，像逐张翻开。
  // 总时长 1050ms（_entrance duration），_span 是单个元素的滑动窗口。
  static const _brandBegin = 0.000;
  static const _themeBegin = 0.130;
  static const _roleBegin = 0.260;
  static const _stageBegin = 0.420;
  static const _railBegin = 0.600;
  static const _itemBase = 0.680;
  static const _itemStep = 0.056;
  static const _span = 0.30;

  List<CharacterCard> _characters = const <CharacterCard>[];
  Map<String, int> _lastMessageAt = const <String, int>{};
  CharacterCard? _activeCharacter;
  int _worldBookCount = 0;
  int _backgroundCount = 0;
  int _uiAssemblyCount = 0;
  bool _loading = true;
  bool _roleSelecting = false;
  bool _roleClosing = false; // 选择层淡出阶段：与入口卡淡入交叉，避免空帧闪烁。
  String? _pendingRoleId;
  String? _promotingRoleId;
  Object? _error;

  late final AnimationController _entrance;
  late final AnimationController _cover;
  bool _entranceReady = false;

  /// 首次加载的完整数据快照：返回主页时复用，不再重拉 DB 造成闪烁。
  List<CharacterCard>? _homeCacheCharacters;

  Timer? _promoteTimer;
  late final bool _reduceMotion;
  bool _motionInitialized = false;

  // 主页进入其他页的转场锚点：用于计算形变扩张的起点 Rect。
  // 模块轨道已有外部传入的 GlobalKey（供导览高亮用），这里复用；
  // 角色入口和 UI 模组库需要内部自建 Key。
  final GlobalKey _roleEntryKey = GlobalKey();
  final GlobalKey _uiModuleKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1050),
    );
    _cover = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 16),
    );
    _loadHomeData();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_motionInitialized) return;
    _motionInitialized = true;
    // 继承组件不能在 initState 里读，减少动效决策放这里。
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion) {
      // 减少动效：入场直接定格到最终状态，封面呼吸停在静态中值。
      _entrance.value = 1.0;
      _entranceReady = true;
      _cover.value = 0.5;
    } else {
      _cover.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _promoteTimer?.cancel();
    _entrance.dispose();
    _cover.dispose();
    super.dispose();
  }

  Future<void> _loadHomeData() async {
    try {
      final rawCharacters = await DatabaseService.getAllCharacters();
      final timestamps = await DatabaseService.getLatestMessageTimestamps();
      final worldBooks = await DatabaseService.getAllWorldBooks();
      final backgrounds = await BackgroundService.getAll();
      final lastActiveId = await ActiveCharacterStore.resolve();

      final characters = rawCharacters
          .map(CharacterCard.fromDb)
          .toList(growable: true);
      characters.sort((a, b) {
        final left = timestamps[a.id] ?? 0;
        final right = timestamps[b.id] ?? 0;
        if (left != right) return right.compareTo(left);
        return a.name.compareTo(b.name);
      });

      CharacterCard? active;
      if (lastActiveId != null) {
        for (final character in characters) {
          if (character.id == lastActiveId) {
            active = character;
            break;
          }
        }
      }
      active ??= characters.isNotEmpty ? characters.first : null;

      var uiCount = 0;
      for (final character in characters) {
        uiCount += character.meta.uiAssemblies.length;
      }

      if (!mounted) return;
      _homeCacheCharacters = characters;
      setState(() {
        _characters = characters;
        _lastMessageAt = timestamps;
        _activeCharacter = active;
        _worldBookCount = worldBooks.length;
        _backgroundCount = backgrounds.length;
        _uiAssemblyCount = uiCount;
        _loading = false;
        _error = null;
      });
      _scheduleEntrance();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error;
      });
      _scheduleEntrance();
    }
  }

  /// 轻量刷新：从库返回主页时只补「最近消息时间戳」，不复刻整页。
  ///
  /// 完整数据快照 [_homeCacheCharacters] 仍在，界面无需重拉角色 / 背景 /
  /// 世界书，避免转场返回瞬间整页闪烁。
  Future<void> _refreshHomeLightly() async {
    if (_homeCacheCharacters == null) {
      await _loadHomeData();
      return;
    }
    try {
      final timestamps = await DatabaseService.getLatestMessageTimestamps();
      if (!mounted) return;
      setState(() {
        _lastMessageAt = timestamps;
        final characters = List<CharacterCard>.from(_homeCacheCharacters!)
          ..sort((a, b) {
            final left = timestamps[a.id] ?? 0;
            final right = timestamps[b.id] ?? 0;
            if (left != right) return right.compareTo(left);
            return a.name.compareTo(b.name);
          });
        _characters = characters;
        _homeCacheCharacters = characters;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      // 轻量刷新失败不打断主页：保持现有快照即可。
    }
  }

  void _scheduleEntrance() {
    if (_entranceReady) return;
    _entranceReady = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _entrance.forward();
    });
  }

  Future<void> _openCharacterLibrary() async {
    final tokens = AppThemeTokens.of(context);
    await Navigator.push<void>(
      context,
      HomeTransitions.module(
        context: context,
        sourceKey: widget.characterTileKey,
        accent: tokens.moduleRole,
        page: const CharacterLibraryPage(),
      ),
    );
    _loadHomeData();
  }

  Future<void> _openWorldBookLibrary() async {
    final tokens = AppThemeTokens.of(context);
    await Navigator.push<void>(
      context,
      HomeTransitions.module(
        context: context,
        sourceKey: widget.worldBookTileKey,
        accent: tokens.moduleWorld,
        page: const WorldBookLibraryPage(),
      ),
    );
    _loadHomeData();
  }

  Future<void> _openBackgroundLibrary() async {
    final tokens = AppThemeTokens.of(context);
    await Navigator.push<void>(
      context,
      HomeTransitions.module(
        context: context,
        sourceKey: widget.backgroundTileKey,
        accent: tokens.moduleBackground,
        page: const BackgroundLibraryPage(),
      ),
    );
    _loadHomeData();
  }

  Future<void> _openUIAssetGallery() async {
    final tokens = AppThemeTokens.of(context);
    await Navigator.push<void>(
      context,
      HomeTransitions.module(
        context: context,
        sourceKey: _uiModuleKey,
        accent: tokens.moduleUi,
        page: const UIAssetGallery(),
      ),
    );
    _loadHomeData();
  }

  Future<void> _openChat() async {
    final character = _activeCharacter;
    if (character == null) {
      await _openCharacterLibrary();
      return;
    }

    // 外置胶囊三段式：卡片先到中间态悬停，UIEngine 在后台解析，完成后才全屏。
    // ready 信号由 ChatPage 在重型初始化完成后回调（onReady），
    // 转场结束前不欠主线程一屁股 DB/JSON 活。
    final ready = Completer<void>();
    final tokens = AppThemeTokens.of(context);
    _preloadForChat(character); // 预热 DB 查询缓存，不阻塞转场
    await Navigator.push<void>(
      context,
      HomeTransitions.stagedRole(
        context: context,
        sourceKey: _roleEntryKey,
        accent: tokens.accent,
        character: character,
        readyFuture: ready.future,
        page: ChatPage(character: character, onReady: () {
          if (!ready.isCompleted) ready.complete();
        }),
      ),
    );
    _refreshHomeLightly();
  }

  /// 转场前预热聊天页要用的重数据，避免转场结束后主线程被 DB/JSON 阻塞。
  ///
  /// 并发拉取会话副本 / 消息历史，并触发一次 [CharacterCard.meta] 解析
  /// 预热缓存。结果不落 UI，只让后续 init 命中热缓存。
  Future<void> _preloadForChat(CharacterCard character) async {
    try {
      // 触发热 meta 解析（缓存一次，ChatPage 里 hasAssembly 不再重复解码）
      character.meta;
      await Future.wait([
        DatabaseService.getSessionStateJson(character.id),
        DatabaseService.getMessages(character.id),
      ]);
    } catch (_) {}
    // 让出一次事件循环，保证 60fps
    await Future.delayed(Duration.zero);
  }

  void _openRoleSelection() {
    final character = _activeCharacter;
    if (character == null) {
      _openCharacterLibrary();
      return;
    }

    setState(() {
      _pendingRoleId = character.id;
      _roleSelecting = true;
    });
  }

  void _cancelRoleSelection() {
    if (!mounted) return;
    _promoteTimer?.cancel();
    setState(() {
      _pendingRoleId = null;
      _promotingRoleId = null;
      _roleSelecting = false;
      _roleClosing = true;
    });
    Future<void>.delayed(_reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 260)).then((_) {
      if (mounted) setState(() => _roleClosing = false);
    });
  }

  /// 第一次点击某张角色卡：聚焦并吸附到主页角色槽位（对应 HTML 第一次点击）。
  void _focusRolePlane(CharacterCard character) {
    if (_pendingRoleId == character.id) {
      _confirmRolePlane(character);
      return;
    }
    _promoteTimer?.cancel();
    setState(() {
      _pendingRoleId = character.id;
      _promotingRoleId = character.id;
    });
    _promoteTimer = Timer(const Duration(milliseconds: 420), () {
      if (mounted) setState(() => _promotingRoleId = null);
    });
  }

  /// 第二次点击（或已聚焦时再点）：确认并替换主页当前角色（对应 HTML 第二次点击）。
  Future<void> _confirmRolePlane(CharacterCard character) async {
    // 点击任意卡片 = 直接确认并切换（去掉「先聚焦、再点一次确认」的两步，
    // 用户反馈之前要点两次才切得过去，容易误以为切换无效）。
    _promoteTimer?.cancel();
    setState(() {
      _pendingRoleId = character.id;
      _promotingRoleId = null;
    });
    await ActiveCharacterStore.write(character.id);
    if (!mounted) return;
    setState(() {
      _activeCharacter = character;
      _pendingRoleId = null;
      _promotingRoleId = null;
      // 进入"关闭中"：选择层淡出，入口卡淡入，交叉过渡避免空帧闪烁。
      _roleSelecting = false;
      _roleClosing = true;
    });
    await Future<void>.delayed(_reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 260));
    if (!mounted) return;
    setState(() => _roleClosing = false);
  }

  /// 滑动吸附后直接选中（对应聊天页角色切换的滑动选中）：无提升闪光，
  /// 仅在吸附到位时替换当前聚焦角色。
  void _swipeSelectRolePlane(CharacterCard character) {
    if (_pendingRoleId == character.id) return;
    _promoteTimer?.cancel();
    setState(() {
      _pendingRoleId = character.id;
      _promotingRoleId = null;
    });
  }

  String _relativeTime(String characterId) {
    final timestamp = _lastMessageAt[characterId];
    if (timestamp == null || timestamp <= 0) return '尚未开始聊天';

    final elapsed = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(timestamp),
    );
    if (elapsed.inMinutes < 1) return '刚刚聊过';
    if (elapsed.inHours < 1) return '${elapsed.inMinutes} 分钟前';
    if (elapsed.inDays < 1) return '${elapsed.inHours} 小时前';
    if (elapsed.inDays < 7) return '${elapsed.inDays} 天前';
    return '${(elapsed.inDays / 7).floor()} 周前';
  }

  HomeState get _homeState {
    if (_loading) return HomeState.loading;
    if (_error != null) return HomeState.error;
    if (_activeCharacter == null) return HomeState.empty;
    if ((_lastMessageAt[_activeCharacter!.id] ?? 0) <= 0) {
      return HomeState.readyToStart;
    }
    return HomeState.resume;
  }

  /// 角色选择层展示的卡片：当前角色排在最前（吸附轨道初始以它为中心），
  /// 其余保持最近聊天优先顺序。吸附以位置驱动，不再重新排序卡片。
  List<CharacterCard> get _selectableCharacters {
    final activeId = _activeCharacter?.id;
    final ordered = <CharacterCard>[];
    if (activeId != null) {
      for (final character in _characters) {
        if (character.id == activeId) {
          ordered.add(character);
          break;
        }
      }
    }
    for (final character in _characters) {
      if (character.id != activeId) ordered.add(character);
    }
    return ordered;
  }

  Widget _buildBrand(AppThemeTokens tokens) {
    return _Staggered(
      animation: _entrance,
      begin: _brandBegin,
      end: (_brandBegin + _span).clamp(0.0, 1.0),
      offset: const Offset(0, -8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _BrandMark(color: tokens.accent, colorSoft: tokens.accentSoft),
          const SizedBox(width: 9),
          Text(
            'LLM PROJECT',
            style: TextStyle(
              color: tokens.accent,
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopActions(AppThemeTokens tokens) {
    final themeManager = context.watch<AppThemeManager>();
    return _Staggered(
      animation: _entrance,
      begin: _themeBegin,
      end: (_themeBegin + _span).clamp(0.0, 1.0),
      offset: const Offset(0, -8),
      child: _ThemeToggleButton(
        night: themeManager.isNight,
        onPressed: themeManager.toggle,
        tokens: tokens,
      ),
    );
  }

  Widget _buildRoleEntry(
    AppThemeTokens tokens, {
    required double roleWidth,
    required double roleHeight,
  }) {
    final character = _activeCharacter;
    final empty = character == null;
    final imagePath = character?.cardImagePath ?? '';
    final hasImage = imagePath.isNotEmpty && File(imagePath).existsSync();
    final stateLabel = empty
        ? 'FIRST EXPERIENCE'
        : _homeState == HomeState.resume
            ? 'CONTINUE EXPERIENCE'
            : 'FIRST EXPERIENCE';
    final title = empty ? '开始第一次体验' : character.name;
    final detail = empty
        ? '从角色库导入或创建一个角色'
        : character.description.trim().isEmpty
            ? (_homeState == HomeState.resume
                ? '距上次聊天 ${_relativeTime(character.id)}'
                : '开始新体验')
            : character.description.trim();

    final cover = hasImage
        ? Image.file(File(imagePath), fit: BoxFit.cover)
        : DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [tokens.accent, tokens.accentStrong],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          );

    return SizedBox(
      key: _roleEntryKey,
      width: roleWidth,
      height: roleHeight,
      child: Stack(
        children: [
          // 角色入口以干净斜切色面落在画布上；滑入阶段带一道长投影
          // （shadowAlpha 随入场 0→1 渐显后衰减到常驻的 0.035），
          // 落下后只剩轻微悬浮感，不抢内容。
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _entrance,
              builder: (context, child) {
                final raw = (_entrance.value - _roleBegin) / _span;
                final t = Curves.easeOutCubic.transform(raw.clamp(0.0, 1.0));
                final resting = 0.035;
                final shadowAlpha = resting + 0.22 * (1 - t);
                return PhysicalShape(
                  clipper: _SlantedSurfaceClipper(),
                  color: tokens.surfaceElevated,
                  shadowColor: tokens.accent.withValues(alpha: shadowAlpha),
                  elevation: (t < 1.0 ? 10.0 * (1 - t) + 0.1 : 0.1),
                  clipBehavior: Clip.antiAlias,
                  child: child,
                );
              },
              child: Stack(
                fit: StackFit.expand,
                children: [
                  AnimatedBuilder(
                    animation: _cover,
                    builder: (context, child) {
                      final t = Curves.easeInOut.transform(_cover.value);
                      return Opacity(
                        opacity: 0.91 + 0.09 * t,
                        child: Transform.scale(
                          // 对齐 HTML `transform-origin: 58% 50%`。
                          scale: 1.015 + 0.025 * t,
                          alignment: const FractionalOffset(0.58, 0.5),
                          // 对齐 HTML `translate3d(-1.5%, -0.6%, 0)`，百分比按卡片自身尺寸折算。
                          child: FractionalTranslation(
                            translation: Offset(-0.015 * t, -0.006 * t),
                            child: child,
                          ),
                        ),
                      );
                    },
                    child: cover,
                  ),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          // 对齐 HTML 的 `linear-gradient(112deg, rgba(44,52,132,0.88), rgba(42,48,112,0.3) 58%, rgba(12,15,27,0.5))`。
                          begin: const Alignment(-1, -0.55),
                          end: const Alignment(1, 0.55),
                          colors: [
                            tokens.accentStrong.withValues(alpha: 0.88),
                            tokens.accentStrong.withValues(alpha: 0.30),
                            Colors.black.withValues(alpha: 0.50),
                          ],
                          stops: const [0.0, 0.58, 1.0],
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _ConcentricRingsPainter(
                          ringColor: Colors.white.withValues(alpha: 1.0),
                        ),
                      ),
                    ),
                  ),
                  if (empty)
                    Positioned(
                      right: 26,
                      top: 27,
                      child: RotatedBox(
                        quarterTurns: 1,
                        child: Text(
                          'START HERE',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.52),
                            fontSize: 8,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.4,
                          ),
                        ),
                      ),
                    )
                  else
                    Positioned(
                      right: 32,
                      top: 27,
                      child: Text(
                        '01',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.6,
                        ),
                      ),
                    ),
                  if (empty)
                    Positioned.fill(
                      child: _RoleEntryHitArea(
                        onTap: _openCharacterLibrary,
                        child: _roleText(
                          tokens,
                          stateLabel: stateLabel,
                          title: title,
                          detail: detail,
                          cardWidth: roleWidth,
                          empty: true,
                        ),
                      ),
                    )
                  else ...[
                    Positioned.fill(
                      child: IgnorePointer(
                        child: _roleText(
                          tokens,
                          stateLabel: stateLabel,
                          title: title,
                          detail: detail,
                          cardWidth: roleWidth,
                          titleKey: widget.chatTextKey,
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      top: 0,
                      right: 72,
                      bottom: 0,
                      child: _RoleEntryHitArea(
                        onTap: _openRoleSelection,
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ],
                  Positioned(
                    right: 29,
                    bottom: 17,
                    child: empty
                        ? IgnorePointer(
                            child: _EnterChatButton(
                              onPressed: null,
                              color: tokens.onAccent,
                              foreground: tokens.textPrimary,
                            ),
                          )
                        : _EnterChatButton(
                            key: widget.chatTileKey,
                            onPressed: _openChat,
                            color: tokens.onAccent,
                            foreground: tokens.textPrimary,
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _roleText(
    AppThemeTokens tokens, {
    required String stateLabel,
    required String title,
    required String detail,
    required double cardWidth,
    GlobalKey? titleKey,
    bool empty = false,
  }) {
    return Stack(
      children: [
        Positioned(
          top: 25,
          left: 24,
          child: Text(
            stateLabel,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.6,
            ),
          ),
        ),
        Positioned(
          top: 44,
          left: 24,
          right: 34,
          child: _AdaptiveNameText(
            text: title,
            key: titleKey,
            maxWidth: cardWidth - 24 - 34,
            fontSize: empty ? 29 : 32,
            color: Colors.white,
            fontWeight: FontWeight.w800,
            letterSpacing: empty ? -1.2 : -1.5,
          ),
        ),
        Positioned(
          left: 24,
          right: 94,
          bottom: 20,
          child: Text(
            detail,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
        ),
      ],
    );
  }

  Widget _buildRoleSelectionLayer(
    AppThemeTokens tokens, {
    required double roleTop,
    required double roleWidth,
    required double roleHeight,
    required bool reduceMotion,
    bool closing = false,
  }) {
    final planes = _selectableCharacters;
    final fadeDuration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 260);
    // 关闭时反向：从可见淡出到隐藏，与入口卡淡入交叉，避免空帧闪烁。
    final opacityTween = closing
        ? Tween<double>(begin: 1.0, end: 0.0)
        : Tween<double>(begin: 0.0, end: 1.0);
    final scaleTween = closing
        ? Tween<double>(begin: 1.0, end: 0.96)
        : Tween<double>(begin: 0.96, end: 1.0);
    return Positioned.fill(
      child: TweenAnimationBuilder<double>(
        tween: opacityTween,
        duration: fadeDuration,
        curve: Curves.easeOutCubic,
        builder: (context, value, child) {
          return Opacity(
            opacity: value,
            child: Transform.scale(
              scale: scaleTween.transform(value),
              alignment: Alignment.topLeft,
              child: child,
            ),
          );
        },
        child: Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: roleTop - 14,
              height: roleHeight + 28,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _cancelRoleSelection,
                // Mirrors HTML's .role-picker-backdrop: a local band that
                // blurs the role row, darkens the center via a radial, and
                // fades at the top/bottom through a vertical mask.
                child: ShaderMask(
                  shaderCallback: (bounds) => LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black,
                      Colors.black,
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.13, 0.84, 1.0],
                  ).createShader(bounds),
                  blendMode: BlendMode.dstIn,
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 2, sigmaY: 2),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: const Alignment(0, 0.1),
                          radius: 0.9,
                          colors: [
                            const Color(0x3305080F),
                            const Color(0x1C05080F),
                            Colors.transparent,
                          ],
                          stops: const [0.0, 0.62, 1.0],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // 灰色轨道蒙版：铺满整行的软边轨道底。上下边缘渐隐过渡、右侧渐隐让
            // 卡片带从轨道里滑出，左侧占满整行（不再留边）。
            Positioned(
              left: 0,
              right: 0,
              top: roleTop - 6,
              height: roleHeight + 12,
              child: IgnorePointer(
                child: ShaderMask(
                  // 纵向：上 / 下边缘过渡，形成软边的轨道带。
                  shaderCallback: (bounds) => LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: const [
                      Colors.transparent,
                      Colors.black,
                      Colors.black,
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.10, 0.90, 1.0],
                  ).createShader(bounds),
                  blendMode: BlendMode.dstIn,
                  child: ShaderMask(
                    // 横向：右侧渐隐，后面的卡带从轨道里滑出。
                    shaderCallback: (bounds) => LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: const [
                        Colors.black,
                        Colors.black,
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.80, 1.0],
                    ).createShader(bounds),
                    blendMode: BlendMode.dstIn,
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.16),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 12,
              right: 0,
              top: roleTop,
              height: roleHeight,
              child: _RoleSnapDeck(
                characters: planes,
                pendingRoleId: _pendingRoleId,
                promotingRoleId: _promotingRoleId,
                activeWidth: roleWidth,
                activeHeight: roleHeight,
                recentLabel: (id) => _relativeTime(id),
                tokens: tokens,
                reduceMotion: reduceMotion,
                onFocused: (c) => _focusRolePlane(c),
                onConfirmed: (c) => _confirmRolePlane(c),
                onSwiped: (c) => _swipeSelectRolePlane(c),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModuleRail(AppThemeTokens tokens) {
    final entries = <_HomeModuleEntry>[
      _HomeModuleEntry(
        title: '角色库',
        symbol: '♟',
        preview: _characters.isEmpty
            ? '从这里开始 · 导入或创建'
            : '${_characters.length} 个角色',
        previewKind: 'people',
        onTap: _openCharacterLibrary,
        key: widget.characterTileKey,
        textKey: widget.characterTextKey,
        accent: tokens.moduleRole,
      ),
      _HomeModuleEntry(
        title: '世界书库',
        symbol: '◇',
        preview: '$_worldBookCount 种世界书',
        previewKind: 'lines',
        onTap: _openWorldBookLibrary,
        key: widget.worldBookTileKey,
        textKey: widget.worldBookTextKey,
        accent: tokens.moduleWorld,
      ),
      _HomeModuleEntry(
        title: '背景图库',
        symbol: '▧',
        preview: '$_backgroundCount 个背景',
        previewKind: 'images',
        onTap: _openBackgroundLibrary,
        key: widget.backgroundTileKey,
        textKey: widget.backgroundTextKey,
        accent: tokens.moduleBackground,
      ),
      _HomeModuleEntry(
        title: 'UI 模组库',
        symbol: '✦',
        preview: '$_uiAssemblyCount 个模组',
        previewKind: 'chips',
        onTap: _openUIAssetGallery,
        key: _uiModuleKey,
        accent: tokens.moduleUi,
      ),
    ];

    return _Staggered(
      animation: _entrance,
      begin: _railBegin,
      end: (_railBegin + _span).clamp(0.0, 1.0),
      offset: const Offset(22, 0),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 10, bottom: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'MODULES',
                      style: TextStyle(
                        color: tokens.textSecondary,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.4,
                      ),
                    ),
                    Text(
                      entries.length.toString().padLeft(2, '0'),
                      style: TextStyle(
                        color: tokens.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.only(right: 4, bottom: 16),
                  itemCount: entries.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final begin =
                        (_itemBase + index * _itemStep).clamp(0.0, 1.0);
                    Widget tile = _ModulePreviewTile(
                      entry: entries[index],
                      tokens: tokens,
                    );
                    // 新用户状态：第一个模块（角色库）承担"从这里开始"的引导强调。
                    if (_characters.isEmpty && index == 0) {
                      tile = _ModuleFocusGuide(
                        accent: entries[index].accent,
                        reduceMotion: _reduceMotion,
                        child: tile,
                      );
                    }
                    return _Staggered(
                      animation: _entrance,
                      begin: begin,
                      end: (begin + _span).clamp(0.0, 1.0),
                      offset: const Offset(18, 0),
                      child: tile,
                    );
                  },
                ),
              ),
            ],
          ),
          Positioned(
            right: 1,
            bottom: 1,
            child: _RailScrollHint(tokens: tokens),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return LayoutBuilder(
      builder: (context, constraints) {
        final railWidth = (constraints.maxWidth * 0.45)
            .clamp(170.0, 230.0)
            .toDouble();
        // 矮屏时压缩布局，对应 index.html 的 @media (max-height: 750px)。
        final shortScreen = constraints.maxHeight <= 750;
        final roleHeight = shortScreen
            ? 128.0
            : (_activeCharacter == null ? 142.0 : 136.0);
        // 对齐 index.html 的 .role-panel: top 119px，矮屏 93px。
        final roleTop = shortScreen ? 93.0 : 119.0;
        // 角色入口长度固定为上次 2:1 时的宽度（332），不再与当前高度保持
        // 2:1 比例——块更扁更修长，只在屏幕过窄时收缩以免贴边溢出。
        final roleWidth = (constraints.maxWidth - 40).clamp(200.0, 332.0).toDouble();
        final stageTop = math.min(
          shortScreen ? 296.0 : 320.0,
          constraints.maxHeight * 0.42,
        );
        var railHeight = (constraints.maxHeight * (shortScreen ? 0.44 : 0.48))
            .clamp(180.0, double.infinity)
            .toDouble();
        final railBottom = 12.0 + bottomInset;
        // 轨道顶部不允许压到角色入口：railTop = maxHeight - railBottom - railHeight。
        final maxRailHeight = constraints.maxHeight -
            railBottom -
            roleTop -
            roleHeight -
            12;
        if (maxRailHeight < railHeight) {
          railHeight = maxRailHeight.clamp(140.0, double.infinity);
        }
        final lineSoft = tokens.outline.withValues(alpha: 0.55);

        return Stack(
          children: [
            Positioned.fill(
              child: RepaintBoundary(
                child: _HomeBackground(tokens: tokens),
              ),
            ),
            Positioned(
              top: stageTop,
              left: 12,
              right: railWidth + 15,
              bottom: railBottom,
              child: _Staggered(
                animation: _entrance,
                begin: _stageBegin,
                end: (_stageBegin + _span).clamp(0.0, 1.0),
                offset: const Offset(0, 13),
                scaleFrom: 0.96,
                child: RepaintBoundary(
                  child: _AvatarStage(
                    tokens: tokens,
                    empty: _activeCharacter == null,
                  ),
                ),
              ),
            ),
            Positioned(
              top: roleTop,
              left: 12,
              child: AnimatedOpacity(
                opacity: _roleSelecting || _roleClosing ? 0.0 : 1.0,
                duration: _reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                child: _Staggered(
                  animation: _entrance,
                  begin: _roleBegin,
                  end: (_roleBegin + _span).clamp(0.0, 1.0),
                  // 垂直偏移仅用于入场，结束时必须精确归零，否则卡会比 HTML 原型(119)
                  // 高出一截。保持入场动感的同时避免静态残留。
                  offset: const Offset(-24, 0),
                  child: _loading
                      ? _LoadingRoleEntry(
                          key: _roleEntryKey,
                          tokens: tokens,
                          width: roleWidth,
                          height: roleHeight,
                        )
                      : _buildRoleEntry(
                          tokens,
                          roleWidth: roleWidth,
                          roleHeight: roleHeight,
                        ),
                ),
              ),
            ),
            Positioned(
              top: null,
              right: 12,
              bottom: railBottom,
              width: railWidth,
              height: railHeight,
              child: _buildModuleRail(tokens),
            ),
            Positioned(
              // 主页右缘的细呼吸光带：铺满整个高度，作为主页与设置面板
              // 交界处的柔和装饰分隔线（取代原来右下角的细短呼吸灯）。
              // 亮度由 _EdgeGestureHint 内部控制（细线低、发光源高）。
              top: 0,
              bottom: 0,
              right: 0,
              child: _EdgeGestureHint(
                accent: tokens.accent,
                line: lineSoft.withValues(alpha: 0.6),
              ),
            ),
            Positioned(
              top: 17,
              left: 22,
              child: _buildBrand(tokens),
            ),
            Positioned(
              top: 14,
              right: 18,
              child: _buildTopActions(tokens),
            ),
            if (_roleSelecting || _roleClosing)
              _buildRoleSelectionLayer(
                tokens,
                roleTop: roleTop,
                roleWidth: roleWidth,
                roleHeight: roleHeight,
                reduceMotion: _reduceMotion,
                closing: _roleClosing,
              ),
            if (_error != null)
              Positioned(
                left: 24,
                right: railWidth + 24,
                bottom: 24,
                child: Text(
                  '主页数据读取失败，请稍后重试',
                  style: TextStyle(color: tokens.danger, fontSize: 11),
                ),
              ),
          ],
        );
      },
    );
  }
}

enum HomeState { loading, empty, readyToStart, resume, selectingRole, error }

class _HomeModuleEntry {
  const _HomeModuleEntry({
    required this.title,
    required this.symbol,
    required this.preview,
    required this.previewKind,
    required this.onTap,
    required this.accent,
    this.key,
    this.textKey,
  });

  final String title;
  final String symbol;
  final String preview;
  final String previewKind;
  final VoidCallback onTap;
  final Color accent;
  final GlobalKey? key;
  final GlobalKey? textKey;
}

class _ModulePreviewTile extends StatelessWidget {
  const _ModulePreviewTile({required this.entry, required this.tokens});

  final _HomeModuleEntry entry;
  final AppThemeTokens tokens;

  static const _radius = BorderRadius.only(
    topLeft: Radius.circular(13),
    topRight: Radius.circular(6),
    bottomRight: Radius.circular(13),
    bottomLeft: Radius.circular(6),
  );

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: entry.key,
      height: 84,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tokens.surface,
          borderRadius: _radius,
          border: Border.all(color: tokens.outline.withValues(alpha: 0.6)),
          boxShadow: [
            BoxShadow(
              color: const Color.fromRGBO(48, 60, 84, 0.07),
              offset: const Offset(5, 6),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: _radius,
            onTap: entry.onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(9, 8, 7, 7),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      _ModuleSymbol(glyph: entry.symbol, color: entry.accent),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          entry.title,
                          key: entry.textKey,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: tokens.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Text(
                        '›',
                        style: TextStyle(
                          color: entry.accent,
                          fontSize: 18,
                          height: 1,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _ModulePreviewVisual(
                    kind: entry.previewKind,
                    label: entry.preview,
                    color: entry.accent,
                    textColor: tokens.textMuted,
                  ),
                  const SizedBox(height: 3),
                  Padding(
                    padding: const EdgeInsets.only(left: 3, right: 2),
                    child: Container(
                      height: 1,
                      color: entry.accent.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// First-run emphasis for the role library module when no character exists yet.
///
/// Mirrors new_user.html's `module-focus`: after a short delay the first rail
/// card nudges left twice with a soft highlight, then settles. Honored reduced
/// motion by staying still.
class _ModuleFocusGuide extends StatefulWidget {
  const _ModuleFocusGuide({
    required this.child,
    required this.accent,
    required this.reduceMotion,
  });

  final Widget child;
  final Color accent;
  final bool reduceMotion;

  @override
  State<_ModuleFocusGuide> createState() => _ModuleFocusGuideState();
}

class _ModuleFocusGuideState extends State<_ModuleFocusGuide>
    with SingleTickerProviderStateMixin {
  static const _playout = Duration(milliseconds: 3800);

  late final AnimationController _controller;
  Timer? _delayTimer;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    // 减少动效：不播放引导强调，直接静态显示。
    _controller = AnimationController(vsync: this, duration: _playout);
    if (widget.reduceMotion) return;
    _controller.addStatusListener((status) {
      if (status != AnimationStatus.completed || !mounted) return;
      setState(() => _playing = false);
    });
    // Delayed start matches new_user.html's 1.1s `animation-delay`.
    _delayTimer = Timer(const Duration(milliseconds: 1100), () {
      if (!mounted || _playing) return;
      _playing = true;
      _controller.repeat(count: 2);
    });
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_playing) return widget.child;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        // Pause at rest until 30%, then nudge left twice with a soft shadow.
        double shift = 0.0;
        double glow = 0.0;
        if (_controller.value >= 0.30) {
          final pulse = (_controller.value - 0.30) % 0.35;
          final t = pulse / 0.35;
          if (t < 0.4) {
            shift = -3 * (t / 0.4);
            glow = 0.0;
          } else if (t < 0.6) {
            shift = -3 * (1 - (t - 0.4) / 0.2);
            glow = 0.25 * (t - 0.4) / 0.2;
          } else {
            shift = 0.0;
            glow = 0.25 * (1 - (t - 0.6) / 0.4);
          }
        }
        return Transform.translate(
          offset: Offset(shift, 0),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(13),
                topRight: Radius.circular(6),
                bottomRight: Radius.circular(13),
                bottomLeft: Radius.circular(6),
              ),
              boxShadow: [
                BoxShadow(
                  color: widget.accent.withValues(alpha: glow),
                  blurRadius: 14,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

class _ModuleSymbol extends StatelessWidget {
  const _ModuleSymbol({required this.glyph, required this.color});

  final String glyph;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        border: Border.all(color: color),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(9),
          topRight: Radius.circular(4),
          bottomRight: Radius.circular(9),
          bottomLeft: Radius.circular(4),
        ),
      ),
      child: glyph == '♟'
          ? CustomPaint(
              painter: _ChessPawnPainter(color: color),
              size: const Size(15, 17),
            )
          : Text(
              glyph,
              style: TextStyle(color: color, fontSize: 14),
            ),
    );
  }
}

/// A skeuomorphic chess pawn: base + body + collar + round head, shaded with a
/// vertical linear gradient so it reads dimensional (light top-left, dark
/// bottom-right) instead of the flat glyph the font provides.
class _ChessPawnPainter extends CustomPainter {
  const _ChessPawnPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final bodyPath = Path()
      ..moveTo(w * 0.17, h * 0.92)
      ..quadraticBezierTo(w * 0.16, h * 0.86, w * 0.26, h * 0.84)
      ..quadraticBezierTo(w * 0.30, h * 0.76, w * 0.34, h * 0.64)
      ..quadraticBezierTo(w * 0.26, h * 0.52, w * 0.24, h * 0.42)
      ..quadraticBezierTo(w * 0.23, h * 0.20, w * 0.48, h * 0.14)
      ..quadraticBezierTo(w * 0.73, h * 0.20, w * 0.72, h * 0.42)
      ..quadraticBezierTo(w * 0.70, h * 0.52, w * 0.62, h * 0.64)
      ..quadraticBezierTo(w * 0.66, h * 0.76, w * 0.70, h * 0.84)
      ..quadraticBezierTo(w * 0.80, h * 0.86, w * 0.79, h * 0.92)
      ..close();

    final bodyPaint = Paint()
      ..shader = LinearGradient(
        begin: const Alignment(-0.8, -0.8),
        end: const Alignment(0.9, 0.9),
        colors: [
          _lighten(color, 0.35),
          color,
          _darken(color, 0.35),
        ],
      ).createShader(
        Rect.fromLTWH(w * 0.1, h * 0.1, w * 0.8, h * 0.9),
      );

    canvas.drawPath(bodyPath, bodyPaint);

    // Round head on top.
    canvas.drawCircle(
      Offset(w * 0.48, h * 0.10),
      w * 0.17,
      Paint()
        ..shader = RadialGradient(
          colors: [_lighten(color, 0.55), _darken(color, 0.25)],
        ).createShader(Rect.fromCircle(
          center: Offset(w * 0.44, h * 0.08),
          radius: w * 0.2,
        )),
    );

    // Subtle rim light along the lower-left silhouette to sell the "solid"
    // sculpted look.
    final rimPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: 0.35);
    final rim = Path()
      ..moveTo(w * 0.22, h * 0.86)
      ..quadraticBezierTo(w * 0.20, h * 0.80, w * 0.27, h * 0.70);
    canvas.drawPath(rim, rimPaint);
  }

  Color _lighten(Color c, double t) => Color.lerp(c, Colors.white, t)!;
  Color _darken(Color c, double t) => Color.lerp(c, Colors.black, t)!;

  @override
  bool shouldRepaint(covariant _ChessPawnPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _ModulePreviewVisual extends StatelessWidget {
  const _ModulePreviewVisual({
    required this.kind,
    required this.label,
    required this.color,
    required this.textColor,
  });

  final String kind;
  final String label;
  final Color color;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    final glyphs = switch (kind) {
      'people' => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PreviewGlyph(type: 'person', color: color),
            const SizedBox(width: 3),
            _PreviewGlyph(type: 'person', color: color),
            const SizedBox(width: 3),
            _PreviewGlyph(type: 'person', color: color),
          ],
        ),
      'images' => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PreviewGlyph(type: 'image', color: color),
            const SizedBox(width: 3),
            _PreviewGlyph(type: 'image', color: color),
            const SizedBox(width: 3),
            _PreviewGlyph(type: 'image', color: color),
          ],
        ),
      'lines' => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 24, height: 3, decoration: BoxDecoration(color: color.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(4))),
            const SizedBox(width: 4),
            Container(width: 14, height: 3, decoration: BoxDecoration(color: color.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(4))),
          ],
        ),
      'chips' => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PreviewChip(label: 'SCENE', color: color),
            const SizedBox(width: 4),
            _PreviewChip(label: 'OPEN', color: color),
          ],
        ),
      _ => const SizedBox.shrink(),
    };

    return Row(
      children: [
        glyphs,
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: textColor, fontSize: 9),
          ),
        ),
      ],
    );
  }
}

class _PreviewChip extends StatelessWidget {
  const _PreviewChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: color.withValues(alpha: 0.65)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 7, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _PreviewGlyph extends StatelessWidget {
  const _PreviewGlyph({required this.type, required this.color});

  final String type;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 16,
      height: 14,
      child: CustomPaint(painter: _PreviewGlyphPainter(type, color)),
    );
  }
}

class _PreviewGlyphPainter extends CustomPainter {
  const _PreviewGlyphPainter(this.type, this.color);

  final String type;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.25
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    if (type == 'person') {
      paint.style = PaintingStyle.fill;
      canvas.drawCircle(const Offset(8, 3.5), 2.4, paint);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(3.3, 7, 9.4, 6),
          const Radius.circular(3),
        ),
        paint,
      );
      return;
    }

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(0.8, 0.8, 14.4, 12.2),
        const Radius.circular(2),
      ),
      paint,
    );
    paint.style = PaintingStyle.fill;
    canvas.drawCircle(const Offset(11.4, 4), 1.2, paint);
    final mountain = Path()
      ..moveTo(2.2, 11.1)
      ..lineTo(5.8, 6.8)
      ..lineTo(8.2, 9.1)
      ..lineTo(10.2, 7.1)
      ..lineTo(13.7, 11.1)
      ..close();
    canvas.drawPath(mountain, paint);
  }

  @override
  bool shouldRepaint(covariant _PreviewGlyphPainter oldDelegate) {
    return oldDelegate.type != type || oldDelegate.color != color;
  }
}

class _RoleEntryHitArea extends StatelessWidget {
  const _RoleEntryHitArea({required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(onTap: onTap, behavior: HitTestBehavior.opaque, child: child);
  }
}

/// 角色名字自适应：单行放不下（超过可用宽的 2/3）时字号减半并换两行，
/// 两行行高保持与单行一致；仍放不下则省略号截断。
class _AdaptiveNameText extends StatelessWidget {
  const _AdaptiveNameText({
    super.key,
    required this.text,
    required this.maxWidth,
    required this.fontSize,
    required this.color,
    required this.fontWeight,
    this.letterSpacing = 0,
  });

  final String text;
  final double maxWidth;
  final double fontSize;
  final Color color;
  final FontWeight fontWeight;
  final double letterSpacing;

  @override
  Widget build(BuildContext context) {
    TextStyle style(double size) => TextStyle(
          color: color,
          fontSize: size,
          fontWeight: fontWeight,
          letterSpacing: letterSpacing,
          height: 1.0,
        );

    // 用单行测量：超过可用宽 2/3 就切换为半号字体的两行模式。
    final singlePainter = TextPainter(
      text: TextSpan(text: text, style: style(fontSize)),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: double.infinity);

    final singleWidth = singlePainter.width;
    final needsTwoLines = singleWidth > maxWidth * 2 / 3;
    final displaySize = needsTwoLines ? fontSize / 2 : fontSize;
    // 行高统一为 fontSize（height:1.0），两行 = 2 * fontSize = 与 fontSize*2 单行等高。
    final lineHeight = fontSize;

    if (!needsTwoLines) {
      return Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style(displaySize),
      );
    }

    return SizedBox(
      height: lineHeight * 2,
      child: Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: style(displaySize),
      ),
    );
  }
}

/// 角色选择层上的吸附卡片轨道。
class _RoleSnapDeck extends StatefulWidget {
  const _RoleSnapDeck({
    required this.characters,
    required this.pendingRoleId,
    required this.promotingRoleId,
    required this.activeWidth,
    required this.activeHeight,
    required this.recentLabel,
    required this.tokens,
    required this.reduceMotion,
    required this.onFocused,
    required this.onConfirmed,
    required this.onSwiped,
  });

  final List<CharacterCard> characters;
  final String? pendingRoleId;
  final String? promotingRoleId;
  final double activeWidth;
  final double activeHeight;
  final String Function(String characterId) recentLabel;
  final AppThemeTokens tokens;
  final bool reduceMotion;
  final ValueChanged<CharacterCard> onFocused;
  final ValueChanged<CharacterCard> onConfirmed;
  final ValueChanged<CharacterCard> onSwiped;

  @override
  State<_RoleSnapDeck> createState() => _RoleSnapDeckState();
}

/// 角色选择层上的滑动翻页卡片轨道。
///
/// 卡片并排排列（统一尺寸 + 间距，能完整看到相邻卡，不重叠），选中卡位于
/// 轨道左侧并与主页角色入口对齐（对应 HTML `.picker-card` 的
/// `flex-basis` 缩放 + `gap: 10px`）。
///
/// 交互是"滑动翻页"：按住时卡片跟手移动；松手时按起始位置与松手位置判定
/// 左滑 / 右滑，切到相邻一张卡并带过冲回弹动画（滑动距离越大，初始力越大，
/// 越过目标卡再回弹一段，形成"刹车感"）；动画结束后选中该卡。点击任意卡片
/// 则带吸附动画跳转到该卡片并聚焦（第一次点击），再次点击已聚焦卡片确认替换。
class _RoleSnapDeckState extends State<_RoleSnapDeck>
    with TickerProviderStateMixin {
  static const double _spacing = 10;
  static const double _inactiveScale = 0.68;
  static const double _inactiveOpacity = 0.5;
  static const double _flingDistance = 48; // 判定"滑动翻页"的最小位移(px)。
  static const double _tapSlop = 8; // 小于该位移当作点击，不翻页。

  double _position = 0.0; // 选中/落点格位（确定性，由松手时直接写入，不参与动画）。
  double _dragStartX = 0.0;
  double _dragPosition = 0.0; // 手指按住期间跟手显示的格位（可越过 0..max）。
  bool _dragActive = false;
  int _lastSwipedIndex = -1;

  int get _count => widget.characters.length;

  /// 相邻两卡中心距：选中卡半宽 + 间距 + 未选中卡半宽。
  /// 卡片按原尺寸渲染，一格即一张卡的平移距离。
  double get _step => widget.activeWidth * (1 + _inactiveScale) / 2 + _spacing;

  void _selectAt(int index) {
    if (index == _lastSwipedIndex) return;
    final character = widget.characters[index];
    if (character.id == widget.pendingRoleId) return;
    _lastSwipedIndex = index;
    widget.onSwiped(character);
  }

  void _onDragStart(DragStartDetails details) {
    _dragStartX = details.localPosition.dx;
    _dragPosition = _position;
    _dragActive = true;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final deltaPx = details.localPosition.dx - _dragStartX;
    setState(() {
      // 跟手：左滑（deltaPx<0）→ 下一张从左侧滑向前台；右滑 → 上一张滑入。
      // 一格对一卡。越过边界时做"拉动"阻尼：越拉越费劲，松手后弹回边缘。
      final raw = _position.round() - deltaPx / _step;
      _dragPosition = _rubberBand(raw);
    });
  }

  /// 橡皮筋阻尼：范围 [0, max] 内线性跟手，越界按平方衰减，制造"拉动到头"的阻力。
  double _rubberBand(double value) {
    final max = _count - 1;
    if (max <= 0) return 0.0;
    const resist = 0.28;
    if (value < 0) {
      final overshoot = -value;
      return -overshoot * overshoot * resist;
    }
    if (value > max) {
      final overshoot = value - max;
      return max + overshoot * overshoot * resist;
    }
    return value;
  }

  void _onDragEnd(DragEndDetails details) {
    if (!_dragActive) return;
    _dragActive = false;
    final start = _position.round().clamp(0, _count - 1);
    final totalPx = details.localPosition.dx - _dragStartX;
    final absPx = totalPx.abs();
    final maxPos = _count - 1;

    // 越界（拉过头）：确定性回到边缘。
    // （试过 easeOutBack 回弹，从被橡皮筋拉远的值回弹时大幅过冲，把轨道甩到
    //  前面的卡片——最后一张再滑动会弹到第二张，正是因为这里。）
    if (_dragPosition < 0 || _dragPosition > maxPos) {
      setState(() => _position = _dragPosition < 0 ? 0.0 : maxPos.toDouble());
      return;
    }

    // 位移太小 → 当作点击，回原位。
    if (absPx < _tapSlop || absPx < _flingDistance) {
      setState(() => _position = start.toDouble());
      return;
    }

    final target = _swipeTarget(start, totalPx);

    if (target == start) {
      // 距离不足以换卡：回落到当前格。
      setState(() => _position = start.toDouble());
      return;
    }

    // 确定性落位 + 选中（不依赖任何动画完成回调——动画中途把轨道弹回中间格
    // 时落点会停错卡，第三张及以后就选不中）。视觉上的平滑滑动由 build 里的
    // TweenAnimationBuilder 完成，它只动画「布局位置」，与选中完全解耦。
    setState(() => _position = target.toDouble());
    _selectAt(target);
  }

  /// 按滑动距离换算松手后的目标格。
  ///
  /// 滑动超过半格就按距离跨多张（一次手势可直接滑到后面的角色），
  /// 不足半格但已越过翻页阈值时至少前进一格，方向由滑动方向决定。
  int _swipeTarget(int start, double totalPx) {
    final moved = (totalPx / _step).round();
    var target = (start - moved).clamp(0, _count - 1);
    if (target == start && moved == 0) {
      target = (start + (totalPx < 0 ? 1 : -1)).clamp(0, _count - 1);
    }
    return target.toInt();
  }

  @override
  Widget build(BuildContext context) {
    if (_count == 0) return const SizedBox.shrink();

    // 布局目标格位：拖动中跟手（_dragPosition），松手后落到确定性选中格（_position）。
    // 动画只驱动这个「布局位置」，选中永远读 _position，二者完全解耦——
    // 所以无论动画怎么播，第三张及以后的卡片都能稳定选中。
    final target = _dragActive ? _dragPosition : _position;
    // 拖动中即时跟手（零时长）；松手后平滑滑到目标（300ms）。减少动效则一直零时长。
    final slideDuration = (_dragActive || widget.reduceMotion)
        ? Duration.zero
        : const Duration(milliseconds: 300);

    return GestureDetector(
      // translucent：卡片上的点击归卡片，行内空白处的点击穿透到背景遮罩取消。
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: _onDragStart,
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      // TweenAnimationBuilder：把布局位置从当前平滑动画到 target。它只影响
      // 卡片怎么排，不触发任何选中逻辑（_selectAt 只在 _onDragEnd 里确定性调用）。
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: target, end: target),
        duration: slideDuration,
        curve: Curves.easeOutCubic,
        builder: (context, p, _) {
          return _buildDeckAt(p);
        },
      ),
    );
  }

  /// 用布局位置 p 排布整条卡片轨道（位置 / 宽度 / 缩放 / 透明度都随 p 连续变化）。
  Widget _buildDeckAt(double p) {
    final selectedIdx = p.round().clamp(0, _count - 1);
    final a = p.floor().toInt().clamp(0, _count - 1);
    final frac = (p - a).clamp(0.0, 1.0);
    final iw = _inactiveScale;
    final aw = widget.activeWidth;

    // 卡片 i 的渲染宽度因子：过渡段内两张卡在满宽与未选中宽之间连续插值。
    double widthFactor(int i) {
      if (i == a) return 1.0 - (1.0 - iw) * frac;
      if (i == a + 1) return iw + (1.0 - iw) * frac;
      return iw;
    }

    double wAt(int i) => aw * widthFactor(i);

    // 卡片 i 相对卡片 a（左缘为 0）的左缘，按各自宽度 + 间距累计，保证并排不重叠。
    double stripLeft(int i) {
      var x = 0.0;
      if (i <= a) {
        for (var j = a - 1; j >= i; j--) {
          x -= wAt(j) + _spacing;
        }
      } else {
        for (var j = a; j < i; j++) {
          x += wAt(j) + _spacing;
        }
      }
      return x;
    }

    // 让过渡对像（a↔b）平滑地滑向左侧选中位：屏幕中心 X = 选中卡中心。
    final ca = wAt(a) / 2;
    final cb = wAt(a) + _spacing + wAt(a + 1) / 2;
    final frame = aw / 2 - (ca * (1 - frac) + cb * frac);

    return ClipRect(
      child: Stack(
        children: [
          for (var i = 0; i < _count; i++)
            Builder(
              builder: (context) {
                final w = wAt(i);
                final scale = widthFactor(i);
                final distance = (i - p).abs();
                final opacity = 1.0 -
                    (1.0 - _inactiveOpacity) * distance.clamp(0.0, 1.0);
                final center = stripLeft(i) + w / 2 + frame;
                return Positioned(
                  left: center - aw / 2,
                  top: 0,
                  width: aw,
                  height: widget.activeHeight,
                  child: _RolePlane(
                    character: widget.characters[i],
                    active: i == selectedIdx,
                    promoting: i == selectedIdx &&
                        widget.promotingRoleId == widget.characters[i].id,
                    scale: scale,
                    opacity: opacity,
                    width: aw,
                    height: widget.activeHeight,
                    recentLabel: widget.recentLabel(widget.characters[i].id),
                    tokens: widget.tokens,
                    reduceMotion: widget.reduceMotion,
                    onTap: () {
                      // 点击任意卡片直接切换（单选，无需先聚焦再点一次确认）。
                      widget.onConfirmed(widget.characters[i]);
                    },
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _RolePlane extends StatelessWidget {
  const _RolePlane({
    required this.character,
    required this.active,
    required this.promoting,
    required this.scale,
    required this.opacity,
    required this.width,
    required this.height,
    required this.recentLabel,
    required this.tokens,
    required this.reduceMotion,
    required this.onTap,
  });

  final CharacterCard character;
  final bool active;
  final bool promoting;

  /// 由 _RoleSnapDeck 逐帧驱动的缩放与透明度：拖拽 / 吸附过程无需重建动画即可跟手。
  final double scale;
  final double opacity;
  final double width;
  final double height;
  final String recentLabel;
  final AppThemeTokens tokens;
  final bool reduceMotion;
  final VoidCallback onTap;

  // 对齐 HTML `.picker-card` 未选中态 `filter: saturate(0.7)`。
  static const List<double> _inactiveColorMatrix = <double>[
    0.44882, 0.21456, 0.02166, 0, 0, //
    0.06378, 0.80064, 0.02166, 0, 0, //
    0.06378, 0.21456, 0.35054, 0, 0, //
    0, 0, 0, 1, 0,
  ];

  @override
  Widget build(BuildContext context) {
    final imagePath = character.cardImagePath;
    final hasImage = imagePath.isNotEmpty && File(imagePath).existsSync();
    final fallback = active ? tokens.accent : tokens.surfaceElevated;

    Widget card = GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: width,
        height: height,
        child: PhysicalShape(
          clipper: _SlantedSurfaceClipper(),
          color: fallback,
          shadowColor: tokens.shadow,
          elevation: active ? 5 : 1,
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (hasImage)
                Image.file(File(imagePath), fit: BoxFit.cover)
              else
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: active
                          ? [tokens.accent, tokens.accentStrong]
                          : [
                              tokens.surfaceElevated,
                              tokens.surfaceInteractive,
                            ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      active
                          ? tokens.accentStrong.withValues(alpha: 0.72)
                          : Colors.black.withValues(alpha: 0.2),
                      Colors.black.withValues(alpha: active ? 0.28 : 0.08),
                    ],
                    begin: const Alignment(-1, -0.55),
                    end: const Alignment(1, 0.55),
                  ),
                ),
              ),
              // 对应 HTML `.picker-card::before`：左上轻微受光、右下压暗的
              // 蒙版，让整张卡带更有“轨道/封面”的层次感。
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: const Alignment(-1, -1),
                        end: const Alignment(1, 1),
                        colors: [
                          Colors.white.withValues(alpha: 0.10),
                          Colors.transparent,
                          Colors.black.withValues(alpha: active ? 0.18 : 0.35),
                        ],
                        stops: const [0.0, 0.48, 1.0],
                      ),
                    ),
                  ),
                ),
              ),
              if (active)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _ConcentricRingsPainter(
                        ringColor: Colors.white.withValues(alpha: 1.0),
                      ),
                    ),
                  ),
                ),
              IgnorePointer(
                child: Stack(
                  children: [
                    Positioned(
                      top: active ? 25 : 15,
                      left: active ? 24 : 15,
                      child: Text(
                        recentLabel,
                        style: TextStyle(
                          color: active ? Colors.white70 : tokens.textMuted,
                          fontSize: active ? 9 : 8,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ),
                    Positioned(
                      top: active ? 44 : 32,
                      left: active ? 24 : 15,
                      right: 12,
                      child: _AdaptiveNameText(
                        text: character.name,
                        maxWidth: width - (active ? 24 : 15) - 12,
                        fontSize: active ? 32 : 20,
                        color: active ? Colors.white : tokens.textPrimary,
                        fontWeight: FontWeight.w800,
                        letterSpacing: active ? -1.5 : -0.6,
                      ),
                    ),
                    Positioned(
                      left: active ? 24 : 15,
                      right: 12,
                      bottom: active ? 20 : 13,
                      child: Text(
                        '${character.name} · $recentLabel',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: active ? Colors.white70 : tokens.textMuted,
                          fontSize: active ? 11 : 8,
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

    // 未选中卡片淡化 + 去饱和：对齐 HTML `.picker-card` 的
    // `opacity: 0.5; filter: saturate(0.7)`。
    if (!active) {
      card = ColorFiltered(
        colorFilter: const ColorFilter.matrix(_inactiveColorMatrix),
        child: card,
      );
    }

    // 点击聚焦时的提升动画：对应 HTML `.picker-card.promoting` 的
    // `picker-promote`，带回弹缩放与一次亮度闪光。
    if (active && promoting) {
      card = TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: 1.0),
        duration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
        builder: (context, value, child) {
          final promoteScale = 0.96 + 0.05 * Curves.easeOutBack.transform(value);
          final brightness = 1.0 + 0.14 * (value < 0.5
              ? value / 0.5
              : (1.0 - value) / 0.5);
          return Transform.scale(
            scale: promoteScale,
            child: ColorFiltered(
              colorFilter: ColorFilter.matrix(<double>[
                brightness, 0, 0, 0, 0,
                0, brightness, 0, 0, 0,
                0, 0, brightness, 0, 0,
                0, 0, 0, 1, 0,
              ]),
              child: child,
            ),
          );
        },
        child: card,
      );
    }

    // 整体缩放与透明度由 deck 控制：缩放以卡片中心为锚，保证吸附时左右平滑过渡。
    return Transform.scale(
      scale: scale,
      child: Opacity(
        opacity: opacity,
        child: card,
      ),
    );
  }
}

class _EnterChatButton extends StatelessWidget {
  const _EnterChatButton({
    super.key,
    required this.onPressed,
    required this.color,
    required this.foreground,
  });

  final VoidCallback? onPressed;
  final Color color;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: ClipPath(
        clipper: _ParallelogramClipper(),
        child: Container(
          width: 49,
          height: 38,
          alignment: Alignment.center,
          color: color,
          child: Icon(Icons.arrow_forward_rounded, color: foreground, size: 23),
        ),
      ),
    );
  }
}

class _LoadingRoleEntry extends StatelessWidget {
  const _LoadingRoleEntry({
    super.key,
    required this.tokens,
    required this.width,
    required this.height,
  });

  final AppThemeTokens tokens;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        children: [
          Positioned.fill(
            child: PhysicalShape(
              clipper: _SlantedSurfaceClipper(),
              color: tokens.surfaceElevated,
              shadowColor: tokens.shadow,
              elevation: 6,
              clipBehavior: Clip.antiAlias,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [tokens.accent, tokens.accentStrong],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: tokens.onAccent,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AvatarStage extends StatefulWidget {
  const _AvatarStage({required this.tokens, required this.empty});

  final AppThemeTokens tokens;
  final bool empty;

  @override
  State<_AvatarStage> createState() => _AvatarStageState();
}

class _AvatarStageState extends State<_AvatarStage>
    with TickerProviderStateMixin {
  late final AnimationController _breathe;
  late final AnimationController _orbit;
  late final bool _reduceMotion;
  bool _motionInitialized = false;

  @override
  void initState() {
    super.initState();
    _breathe = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    );
    _orbit = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 9),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_motionInitialized) return;
    _motionInitialized = true;
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion) {
      _breathe.value = 0.5;
      _orbit.value = 0.5;
    } else {
      _breathe.repeat(reverse: true);
      _orbit.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _breathe.dispose();
    _orbit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stage = widget.tokens.stage;
    return AnimatedBuilder(
      animation: Listenable.merge([_breathe, _orbit]),
      builder: (context, child) {
        final b = Curves.easeInOut.transform(_breathe.value);
        final o = Curves.easeInOut.transform(_orbit.value);
        return Stack(
          alignment: Alignment.bottomCenter,
          children: [
          // 同心椭圆环组：三个椭圆共享同一个中心（对应 HTML 的 .stage-ring 及其
          // ::before/::after 用 inset 相对同一容器定位，天然同心）。呼吸/轨道
          // 动画只改旋转角与尺寸，不移动中心。
          Positioned(
            bottom: 9,
            child: SizedBox(
              width: 206,
              height: 92,
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  Transform.rotate(
                    angle: -0.227 + o * 0.105,
                    child: Container(
                      width: 158 + b * 6,
                      height: 55 + b * 3,
                      decoration: BoxDecoration(
                        border: Border.all(color: stage.withValues(alpha: 0.42)),
                        borderRadius: const BorderRadius.all(
                          Radius.elliptical(80, 28),
                        ),
                      ),
                    ),
                  ),
                  Transform.rotate(
                    angle: 0.384 + o * 0.05,
                    child: Container(
                      width: 114,
                      height: 87,
                      decoration: BoxDecoration(
                        border: Border.all(color: stage.withValues(alpha: 0.18)),
                        borderRadius: const BorderRadius.all(
                          Radius.elliptical(57, 43.5),
                        ),
                      ),
                    ),
                  ),
                  Transform.rotate(
                    angle: -0.489 - o * 0.05,
                    child: Container(
                      width: 200,
                      height: 29,
                      decoration: BoxDecoration(
                        border: Border.all(color: stage.withValues(alpha: 0.18)),
                        borderRadius: const BorderRadius.all(
                          Radius.elliptical(100, 14.5),
                        ),
                      ),
                    ),
                  ),
                  // HTML 式青色光源：径向渐变 + 模糊 + 呼吸，叠加在环状图案之上。
                  // HTML 的 stage-glow 是 rgba(105,189,180,0.16) + blur(11px)，
                  // 呼吸 0.62→1.0。放在 rings 之后绘制，即盖在环上面。
                  Opacity(
                    opacity: 0.62 + 0.38 * b,
                    child: Transform.scale(
                      scale: 0.96 + 0.09 * b,
                      child: ImageFiltered(
                        imageFilter: ui.ImageFilter.blur(sigmaX: 11, sigmaY: 11),
                        child: Container(
                          width: 205,
                          height: 140,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.all(
                              Radius.elliptical(102.5, 70),
                            ),
                            gradient: RadialGradient(
                              colors: [
                                stage.withValues(alpha: 0.16),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
            Positioned(
              bottom: 3,
              child: widget.empty
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'YOUR STAGE',
                          style: TextStyle(
                            color: stage,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.0,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '等待第一个角色登场',
                          style: TextStyle(
                            color: widget.tokens.textMuted,
                            fontSize: 8,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ],
                    )
                  : Text(
                      'AVATAR STAGE · RESERVED',
                      style: TextStyle(
                        color: widget.tokens.textMuted,
                        fontSize: 8,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.4,
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _SlantedSurfaceClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width * 0.94, 0)
      ..lineTo(size.width, size.height * 0.12)
      ..lineTo(size.width * 0.92, size.height)
      ..lineTo(size.width * 0.02, size.height * 0.94)
      ..close();
    return path;
  }

  @override
  bool shouldReclip(covariant _SlantedSurfaceClipper oldClipper) => false;
}

class _ParallelogramClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    return Path()
      ..moveTo(size.width * 0.13, 0)
      ..lineTo(size.width, size.height * 0.10)
      ..lineTo(size.width * 0.88, size.height)
      ..lineTo(0, size.height * 0.88)
      ..close();
  }

  @override
  bool shouldReclip(covariant _ParallelogramClipper oldClipper) => false;
}

class _ConcentricRingsPainter extends CustomPainter {
  const _ConcentricRingsPainter({required this.ringColor});

  final Color ringColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width - 107, 22);
    void ring(double radius, double alpha) {
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = ringColor.withValues(alpha: alpha),
      );
    }

    ring(86, 0.17);
    ring(86 + 18, 0.035);
    ring(86 + 42, 0.025);
  }

  @override
  bool shouldRepaint(covariant _ConcentricRingsPainter oldDelegate) {
    return oldDelegate.ringColor != ringColor;
  }
}

class _DiagonalRingsPainter extends CustomPainter {
  const _DiagonalRingsPainter({required this.line});

  final Color line;

  @override
  void paint(Canvas canvas, Size size) {
    // Design target: several 1px, extremely faint light-grey ellipse hairlines,
    // slightly scattered so they read as refined geometry rather than a solid
    // hoop. Each ring drifts a little along the major axis instead of being
    // perfectly concentric.
    final rect = Rect.fromLTWH(
      size.width * 0.21,
      size.height * 0.19,
      size.width * 1.15,
      size.height * 0.45,
    );
    canvas.save();
    canvas.translate(rect.center.dx, rect.center.dy);
    canvas.rotate(-57 * math.pi / 180);

    Rect ovalInset(double inset) => Rect.fromCenter(
          center: Offset.zero,
          width: rect.width + inset * 2,
          height: rect.height + inset * 2,
        );

    // 设计上是两条相接的环带：内侧深灰细环、外侧浅灰粗环，中间不重合。
    // 用 Path.combine(difference) 填充椭圆环（外椭圆挖去内椭圆）画出实心
    // 带状区域。两带共享同一个分界半径 split，接壤处即这条椭圆。
    Path oval(Rect r) => Path()..addOval(r);
    final split = 30.0;
    // 内侧深灰环：做薄，宽度约 12。
    final innerRing = Path.combine(
      PathOperation.difference,
      oval(ovalInset(split)),
      oval(ovalInset(split - 12)),
    );
    // 外侧浅灰环：比深灰环稍厚一些，但比之前收窄。
    final outerRing = Path.combine(
      PathOperation.difference,
      oval(ovalInset(split + 40)),
      oval(ovalInset(split)),
    );

    // 深灰做浅些、浅灰更浅，整体都是极淡的氛围线。
    final darkFill = Paint()
      ..style = PaintingStyle.fill
      ..color = line.withValues(alpha: 0.09);
    final lightFill = Paint()
      ..style = PaintingStyle.fill
      ..color = line.withValues(alpha: 0.04);

    canvas.drawPath(innerRing, darkFill);
    canvas.drawPath(outerRing, lightFill);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _DiagonalRingsPainter oldDelegate) {
    return oldDelegate.line != line;
  }
}

class _DiagonalLinePainter extends CustomPainter {
  const _DiagonalLinePainter({required this.line});

  final Color line;

  @override
  void paint(Canvas canvas, Size size) {
    // Mirrors .screen::after in the HTML prototype: a 150%-wide, 1px line
    // centered around (55%, 50%) and rotated -57deg.
    const angle = -57 * math.pi / 180;
    final halfWidth = size.width * 0.75;
    final center = Offset(size.width * 0.55, size.height * 0.5);
    final dir = Offset(math.cos(angle), math.sin(angle));
    final from = center - dir * halfWidth;
    final to = center + dir * halfWidth;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..shader = LinearGradient(
        colors: [Colors.transparent, line, Colors.transparent],
      ).createShader(Rect.fromPoints(from, to));
    canvas.drawLine(from, to, paint);
  }

  @override
  bool shouldRepaint(covariant _DiagonalLinePainter oldDelegate) {
    return oldDelegate.line != line;
  }
}

class _HomeBackground extends StatelessWidget {
  const _HomeBackground({required this.tokens});

  final AppThemeTokens tokens;

  @override
  Widget build(BuildContext context) {
    // The HTML prototype draws its ring decoration with a faint dark line in
    // day and a faint light line in night; textPrimary flips correctly for
    // both, so we derive the decorative line from it rather than from outline.
    // 椭圆轨道环是背景主体（HTML --line-soft），斜线更淡（--line 的一半左右）。
    // 环带 alpha 由 painter 内部控制，这里只决定基准颜色。
    final isNight = Theme.of(context).brightness == Brightness.dark;
    // 深色模式下让环带偏蓝：把近白 textPrimary 向淡蓝方向拉一点。
    final baseLine = isNight
        ? Color.lerp(tokens.textPrimary, const Color(0xFF9DB7FF), 0.55)!
        : tokens.textPrimary;
    final rings = baseLine.withValues(alpha: 0.05);
    final diagonal = baseLine.withValues(alpha: 0.035);
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: tokens.canvas,
            gradient: RadialGradient(
              // HTML 用 `radial-gradient(ellipse at 4% 76%, rgba(105,189,180,0.11), transparent 14rem)`：
              // 左下角只有一小片极淡的朦胧青调光晕，14rem≈224px 后就淡出，过渡要柔和。
              // 此前 0.11 叠在纯色上偏浑浊，压到 0.06 让氛围更轻盈。
              center: const Alignment(-0.92, 0.52),
              radius: 0.33,
              colors: [
                tokens.stage.withValues(alpha: 0.06),
                tokens.canvas.withValues(alpha: 0.0),
              ],
              stops: const [0.0, 1.0],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [tokens.canvas.withValues(alpha: 0.0), tokens.canvasDeep],
              stops: const [0.6, 1.0],
            ),
          ),
        ),
        CustomPaint(painter: _DiagonalRingsPainter(line: rings)),
        CustomPaint(painter: _DiagonalLinePainter(line: diagonal)),
      ],
    );
  }
}

class _Staggered extends StatelessWidget {
  const _Staggered({
    required this.animation,
    required this.begin,
    required this.end,
    required this.offset,
    this.scaleFrom = 1.0,
    required this.child,
  });

  final Animation<double> animation;
  final double begin;
  final double end;
  final Offset offset;
  final double scaleFrom;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final raw = (animation.value - begin) / (end - begin);
        final t = Curves.easeOutCubic.transform(raw.clamp(0.0, 1.0));
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: offset * (1 - t),
            child: Transform.scale(
              scale: scaleFrom + (1.0 - scaleFrom) * t,
              child: child,
            ),
          ),
        );
      },
      child: child,
    );
  }
}

class _BrandMark extends StatefulWidget {
  const _BrandMark({required this.color, required this.colorSoft});

  final Color color;
  final Color colorSoft;

  @override
  State<_BrandMark> createState() => _BrandMarkState();
}

class _BrandMarkState extends State<_BrandMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final bool _reduceMotion;
  bool _motionInitialized = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4200),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_motionInitialized) return;
    _motionInitialized = true;
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion) {
      _controller.value = 0.5;
    } else {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_controller.value);
        return Opacity(
          opacity: 0.72 + 0.28 * t,
          child: Container(
            width: 8,
            height: 8,
            transform: Matrix4.rotationZ(math.pi / 4),
            decoration: BoxDecoration(
              color: widget.color,
              borderRadius: BorderRadius.circular(2),
              boxShadow: [
                BoxShadow(
                  color: widget.color.withValues(alpha: 0.45 + 0.55 * t),
                  blurRadius: 5 + 11 * t,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ThemeToggleButton extends StatelessWidget {
  const _ThemeToggleButton({
    required this.night,
    required this.onPressed,
    required this.tokens,
  });

  final bool night;
  final VoidCallback onPressed;
  final AppThemeTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: Container(
          width: 35,
          height: 35,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: tokens.surface,
            border: Border.all(color: tokens.outline),
          ),
          child: Icon(
            night ? Icons.wb_sunny_rounded : Icons.nightlight_round,
            size: 16,
            color: tokens.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _RailScrollHint extends StatelessWidget {
  const _RailScrollHint({required this.tokens});

  final AppThemeTokens tokens;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: 22,
        height: 22,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: tokens.outline),
          color: tokens.canvas,
        ),
        child: Text(
          '⌄',
          style: TextStyle(color: tokens.textMuted, fontSize: 12),
        ),
      ),
    );
  }
}

class _EdgeGestureHint extends StatefulWidget {
  const _EdgeGestureHint({required this.accent, required this.line});

  final Color accent;
  final Color line;

  @override
  State<_EdgeGestureHint> createState() => _EdgeGestureHintState();
}

class _EdgeGestureHintState extends State<_EdgeGestureHint>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final bool _reduceMotion;
  bool _motionInitialized = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 6000),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_motionInitialized) return;
    _motionInitialized = true;
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion) {
      _controller.value = 0.84;
    } else {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 发光色：Day 青蓝、Night 浅紫。
    final isNight = Theme.of(context).brightness == Brightness.dark;
    final glowColor =
        isNight ? const Color(0xFFB8A8FF) : const Color(0xFF3FC6C2);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final phase = _controller.value;
        // 呼吸脉冲：0.1（低）到 1.0（高），用于发光源的强度。
        double pulse;
        if (phase < 0.72) {
          pulse = 0.10;
        } else if (phase < 0.86) {
          pulse = 0.10 + 0.90 * (phase - 0.72) / 0.14;
        } else {
          pulse = 1.00 - 0.90 * (phase - 0.86) / 0.14;
        }
        // 一条 1px 细线贴右边界 + 中间一段高强度呼吸发光源（同样贴右边界）。
        return IgnorePointer(
          child: SizedBox(
            width: 1,
            height: double.infinity,
            child: Stack(
              fit: StackFit.expand,
              clipBehavior: Clip.none,
              children: [
                // 整条低强度细线（背景分隔线）。
                ColoredBox(color: widget.line.withValues(alpha: 0.7)),
                // 中间一段呼吸发光源：占约 22% 高度、垂直居中，贴右边界，
                // 光晕向右侧发散（Clip.none 允许溢出线宽）。
                FractionallySizedBox(
                  alignment: Alignment.center,
                  widthFactor: 1.0,
                  heightFactor: 0.22,
                  child: Container(
                    decoration: BoxDecoration(
                      color: glowColor.withValues(alpha: 0.55 + 0.45 * pulse),
                      boxShadow: [
                        BoxShadow(
                          color: glowColor.withValues(alpha: 0.55 * pulse),
                          blurRadius: 18,
                          spreadRadius: 3,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
